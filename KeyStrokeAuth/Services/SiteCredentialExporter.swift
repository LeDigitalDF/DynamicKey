// SiteCredentialExporter.swift
// Builds CSV backups of saved site credentials (W3.4).
//
// Flow: Settings → Export CSV → user picks save location.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SiteCredentialExporter {
    /// CSV header compatible with Import CSV and common password managers.
    static func makeCSV(from credentials: [SiteCredential]) -> Data {
        var lines = ["url,username,password"]
        for credential in credentials {
            lines.append(
                [
                    csvField(credential.origin),
                    csvField(credential.username),
                    csvField(credential.password),
                ].joined(separator: ",")
            )
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

/// FileDocument wrapper for SwiftUI fileExporter.
struct SiteCredentialCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var data: Data

    init(credentials: [SiteCredential]) {
        data = SiteCredentialExporter.makeCSV(from: credentials)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
