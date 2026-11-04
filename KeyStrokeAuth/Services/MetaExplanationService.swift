// MetaExplanationService.swift
// Calls Meta Model API (Muse Spark) with a privacy-safe count string only.
// Flow: MorningSummaryService passes verdict text → chat/completions → one or two sentences.

import Foundation

/// Token breakdown from a Chat Completions `usage` object (for test diagnostics).
struct MuseResponseUsage: Equatable {
    var promptTokens: Int?
    var completionTokens: Int?
    var reasoningTokens: Int?
    var totalTokens: Int?
    var finishReason: String?

    var diagnosticSummary: String {
        var parts: [String] = []
        if let finishReason, !finishReason.isEmpty {
            parts.append("finish_reason \(finishReason)")
        }
        if let promptTokens { parts.append("prompt \(promptTokens)") }
        if let completionTokens { parts.append("completion \(completionTokens)") }
        if let reasoningTokens { parts.append("reasoning \(reasoningTokens)") }
        if let totalTokens { parts.append("total \(totalTokens)") }
        return parts.isEmpty ? "usage unavailable" : parts.joined(separator: ", ")
    }
}

enum MetaExplanationError: Error {
    case httpStatus(Int, detail: String?)
    case emptyResponse(usage: MuseResponseUsage?)
    case unparseableBody
}

enum MetaExplanationService {
    private static let endpoint = URL(string: "https://api.meta.ai/v1/chat/completions")!
    private static let model = "muse-spark-1.3"
    private static let requestTimeout: TimeInterval = 12
    /// Reasoning + visible output share this cap (~500 reasoning + short reply).
    private static let outputTokenLimit = 1500

    private enum OutputTokenParameter {
        case maxCompletionTokens
        case maxTokens
    }

    /// Sends only `verdictPrompt` (counts, no PII). Returns assistant text trimmed.
    static func fetchExplanation(
        verdictPrompt: String,
        apiKey: String,
        logRawResponseBody: Bool = false
    ) async throws -> String {
        let messages: [[String: String]] = [
            [
                "role": "system",
                "content": """
                You write one or two short, calm sentences for a Mac password manager daily security brief. \
                No bullet lists, no markdown, no emojis. Do not invent numbers — use only what the user message states.
                """,
            ],
            ["role": "user", "content": verdictPrompt],
        ]

        var tokenParameter: OutputTokenParameter = .maxCompletionTokens
        var includeReasoningEffortLow = true
        while true {
            let body = requestBody(
                messages: messages,
                tokenParameter: tokenParameter,
                includeReasoningEffortLow: includeReasoningEffortLow
            )
            if logRawResponseBody {
                logRequestBodyToConsole(body)
            }

            let result = try await sendChatCompletion(body: body, apiKey: apiKey, logRawResponseBody: logRawResponseBody)

            switch result {
            case .success(let json, let data):
                return try parseAssistantText(from: json, rawData: data, logRawResponseBody: logRawResponseBody)
            case .httpError(let status, let data):
                if logRawResponseBody {
                    logResponseBodyToConsole(data)
                }
                let detail = apiErrorMessage(from: data)
                if status == 400 {
                    if includeReasoningEffortLow {
                        includeReasoningEffortLow = false
                        if logRawResponseBody {
                            print(
                                "[DailySummary Muse test] HTTP 400 with reasoning_effort low"
                                    + (detail.map { " (\($0))" } ?? "")
                                    + " — retrying without reasoning_effort."
                            )
                        }
                        continue
                    }
                    if tokenParameter == .maxCompletionTokens {
                        tokenParameter = .maxTokens
                        if logRawResponseBody {
                            print(
                                "[DailySummary Muse test] HTTP 400 with max_completion_tokens only"
                                    + (detail.map { " (\($0))" } ?? "")
                                    + " — retrying with max_tokens only."
                            )
                        }
                        continue
                    }
                }
                throw MetaExplanationError.httpStatus(status, detail: detail)
            case .transportFailure:
                throw MetaExplanationError.unparseableBody
            }
        }
    }

    private static func requestBody(
        messages: [[String: String]],
        tokenParameter: OutputTokenParameter,
        includeReasoningEffortLow: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
        ]
        if includeReasoningEffortLow {
            body["reasoning_effort"] = "low"
        }
        switch tokenParameter {
        case .maxCompletionTokens:
            body["max_completion_tokens"] = outputTokenLimit
        case .maxTokens:
            body["max_tokens"] = outputTokenLimit
        }
        return body
    }

    private enum SendResult {
        case success(json: [String: Any], data: Data)
        case httpError(status: Int, data: Data)
        case transportFailure
    }

    private static func sendChatCompletion(
        body: [String: Any],
        apiKey: String,
        logRawResponseBody: Bool
    ) async throws -> SendResult {
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .transportFailure
        }

        guard let http = response as? HTTPURLResponse else {
            return .transportFailure
        }
        guard (200...299).contains(http.statusCode) else {
            return .httpError(status: http.statusCode, data: data)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if logRawResponseBody {
                logResponseBodyToConsole(data)
            }
            throw MetaExplanationError.unparseableBody
        }
        return .success(json: json, data: data)
    }

    private static func parseAssistantText(
        from json: [String: Any],
        rawData: Data,
        logRawResponseBody: Bool
    ) throws -> String {
        guard
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            if logRawResponseBody {
                logResponseBodyToConsole(rawData)
            }
            throw MetaExplanationError.unparseableBody
        }

        let finishReason = first["finish_reason"] as? String
        let usage = parseUsage(from: json, finishReason: finishReason)
        let visibleText = visibleContent(from: message)
        if visibleText.isEmpty {
            if logRawResponseBody {
                logResponseBodyToConsole(rawData)
                print("[DailySummary Muse test] Token usage: \(usage.diagnosticSummary)")
            }
            throw MetaExplanationError.emptyResponse(usage: usage)
        }
        return visibleText
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else {
            return nil
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func visibleContent(from message: [String: Any]) -> String {
        let rawContent = message["content"]
        if rawContent == nil || rawContent is NSNull {
            return ""
        }
        if let content = rawContent as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func parseUsage(from json: [String: Any], finishReason: String?) -> MuseResponseUsage {
        guard let usage = json["usage"] as? [String: Any] else {
            return MuseResponseUsage(finishReason: finishReason)
        }

        var reasoning: Int?
        if let details = usage["completion_tokens_details"] as? [String: Any] {
            reasoning = details["reasoning_tokens"] as? Int
        }

        return MuseResponseUsage(
            promptTokens: usage["prompt_tokens"] as? Int,
            completionTokens: usage["completion_tokens"] as? Int,
            reasoningTokens: reasoning,
            totalTokens: usage["total_tokens"] as? Int,
            finishReason: finishReason
        )
    }

    /// Test-only logging — request JSON only (no Authorization header).
    private static func logRequestBodyToConsole(_ body: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            print("[DailySummary Muse test] Request body: <could not serialize>")
            return
        }
        print("[DailySummary Muse test] Request body (POST \(endpoint.absoluteString)):\n\(text)")
    }

    /// Test-only logging — response JSON only, never credentials.
    private static func logResponseBodyToConsole(_ data: Data) {
        let text = String(data: data, encoding: .utf8) ?? "<non-UTF-8 body, \(data.count) bytes>"
        print("[DailySummary Muse test] Raw API response body:\n\(text)")
    }
}
