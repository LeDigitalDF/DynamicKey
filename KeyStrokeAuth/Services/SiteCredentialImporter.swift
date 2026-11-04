// SiteCredentialImporter.swift
// Parses CSV exports from password managers into manual site credentials (W3.4).
//
// Flow: user picks CSV in Settings → parse rows → save via CredentialStore (Manual badge).

import Foundation

enum SiteCredentialImporterError: Error, LocalizedError {
    case emptyFile
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected file is empty."
        case .unreadableFile:
            return "Could not read the selected CSV file."
        }
    }
}

struct SiteCredentialImportResult {
    let importedCount: Int
    let skippedCount: Int
    let rowErrors: [String]
}

enum SiteCredentialImporter {
    private static let originHeaderKeys = ["url", "origin", "login_uri", "site", "website", "login url"]
    private static let usernameHeaderKeys = ["username", "login_username", "user", "email", "login"]
    private static let passwordHeaderKeys = ["password", "login_password", "pass"]

    /// Reads and imports credentials from a user-selected CSV file URL.
    static func importFromFile(url: URL) throws -> SiteCredentialImportResult {
        guard let data = try? Data(contentsOf: url) else {
            throw SiteCredentialImporterError.unreadableFile
        }
        return try importCSV(data: data)
    }

    /// Parses CSV bytes and saves manual credentials through the credential store.
    static func importCSV(data: Data, into store: CredentialStore = .shared) throws -> SiteCredentialImportResult {
        guard let text = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\u{FEFF}", with: "") else {
            throw SiteCredentialImporterError.unreadableFile
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lines.isEmpty else {
            throw SiteCredentialImporterError.emptyFile
        }

        var originIndex = 0
        var usernameIndex = 1
        var passwordIndex = 2
        var dataLines = lines

        if let header = parseCSVLine(lines[0]),
           header.count >= 3,
           looksLikeHeader(header) {
            originIndex = indexForHeader(header, keys: originHeaderKeys) ?? 0
            usernameIndex = indexForHeader(header, keys: usernameHeaderKeys) ?? 1
            passwordIndex = indexForHeader(header, keys: passwordHeaderKeys) ?? 2
            dataLines = Array(lines.dropFirst())
        }

        var importedCount = 0
        var skippedCount = 0
        var rowErrors: [String] = []

        for (offset, line) in dataLines.enumerated() {
            let rowNumber = offset + (lines.count == dataLines.count ? 1 : 2)
            guard let fields = parseCSVLine(line) else {
                rowErrors.append("Row \(rowNumber): could not parse CSV line.")
                skippedCount += 1
                continue
            }

            let maxIndex = max(originIndex, usernameIndex, passwordIndex)
            guard fields.count > maxIndex else {
                rowErrors.append("Row \(rowNumber): expected at least \(maxIndex + 1) columns.")
                skippedCount += 1
                continue
            }

            let origin = SiteCredential.normalizeOrigin(fields[originIndex])
            let username = fields[usernameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let password = fields[passwordIndex]

            guard !origin.isEmpty else {
                rowErrors.append("Row \(rowNumber): missing website URL.")
                skippedCount += 1
                continue
            }

            guard !password.isEmpty else {
                rowErrors.append("Row \(rowNumber): missing password.")
                skippedCount += 1
                continue
            }

            let credential = SiteCredential(
                origin: origin,
                username: username,
                password: password,
                isGenerated: false
            )

            do {
                try store.save(credential)
                importedCount += 1
            } catch {
                rowErrors.append("Row \(rowNumber): \(error.localizedDescription)")
                skippedCount += 1
            }
        }

        if importedCount == 0, skippedCount > 0, rowErrors.isEmpty {
            rowErrors.append("No valid rows were found.")
        }

        if importedCount > 0 {
            AuditLogService.shared.append(
                AuditEvent(
                    type: .siteCredentialsImported,
                    detail: "Imported \(importedCount), skipped \(skippedCount)"
                )
            )
        }

        return SiteCredentialImportResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
            rowErrors: rowErrors
        )
    }

    private static func looksLikeHeader(_ fields: [String]) -> Bool {
        let lowered = fields.map { $0.lowercased() }
        return lowered.contains(where: { originHeaderKeys.contains($0) })
            || lowered.contains(where: { usernameHeaderKeys.contains($0) })
            || lowered.contains(where: { passwordHeaderKeys.contains($0) })
    }

    private static func indexForHeader(_ fields: [String], keys: [String]) -> Int? {
        let lowered = fields.map { $0.lowercased() }
        for key in keys {
            if let index = lowered.firstIndex(of: key) {
                return index
            }
        }
        return nil
    }

    /// Parses one CSV record, supporting quoted fields that contain commas.
    private static func parseCSVLine(_ line: String) -> [String]? {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if character == "\"" {
                if inQuotes {
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else if current.isEmpty {
                    inQuotes = true
                } else {
                    current.append(character)
                }
            } else if character == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }

            index = line.index(after: index)
        }

        fields.append(current)
        return fields
    }
}
