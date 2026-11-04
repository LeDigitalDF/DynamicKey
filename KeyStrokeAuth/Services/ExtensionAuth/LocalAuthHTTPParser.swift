// LocalAuthHTTPParser.swift
// Minimal HTTP/1.1 request parsing for localhost extension API (M5).
//
// Flow: read headers → read Content-Length body → route by method and path.

import Foundation

struct LocalHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct LocalHTTPResponse {
    let statusCode: Int
    let statusText: String
    let headers: [String: String]
    let body: Data

    /// Serializes a complete HTTP/1.1 response with Connection: close.
    func serialize() -> Data {
        var headerLines = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Content-Type: application/json; charset=utf-8",
        ]

        for (key, value) in headers {
            headerLines.append("\(key): \(value)")
        }

        var data = Data(headerLines.joined(separator: "\r\n").utf8)
        data.append(contentsOf: "\r\n\r\n".utf8)
        data.append(body)
        return data
    }
}

enum LocalHTTPParser {
    /// Attempts to parse a full HTTP request from accumulated socket data.
    static func parseRequest(from data: Data) -> LocalHTTPRequest? {
        guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }

        let method = String(requestParts[0])
        let path = String(requestParts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[name.lowercased()] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEndRange.upperBound
        let availableBody = data.count - bodyStart
        guard availableBody >= contentLength else { return nil }

        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return LocalHTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    /// Builds a JSON HTTP response with the given status code.
    static func jsonResponse<T: Encodable>(
        statusCode: Int,
        statusText: String,
        body: T,
        encoder: JSONEncoder = JSONEncoder()
    ) -> LocalHTTPResponse {
        encoder.dateEncodingStrategy = .iso8601
        let encoded = (try? encoder.encode(body)) ?? Data()
        return LocalHTTPResponse(
            statusCode: statusCode,
            statusText: statusText,
            headers: ["Access-Control-Allow-Origin": "*"],
            body: encoded
        )
    }

    /// Builds a JSON error response for failed API calls.
    static func errorResponse(statusCode: Int, statusText: String, error: String, message: String) -> LocalHTTPResponse {
        jsonResponse(
            statusCode: statusCode,
            statusText: statusText,
            body: ExtensionAPIErrorResponse(
                protocolVersion: ExtensionAuthConfig.protocolVersion,
                error: error,
                message: message
            )
        )
    }
}
