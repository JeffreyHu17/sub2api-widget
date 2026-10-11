import Foundation

/// Server-supplied text can echo request context (authorization fragments, emails,
/// account identifiers). That text is rendered on the desktop widget, which anyone
/// walking past the machine can read, so it must be scrubbed before display.
enum SafeMessage {
    private static let sensitivePatterns: [NSRegularExpression] = {
        [
            // Bearer / token / key / secret values, quoted or bare.
            "(?i)\\b(bearer|token|access[_-]?token|refresh[_-]?token|api[_-]?key|apikey|secret|password|authorization)\\b\\s*[:=]?\\s*\"?[A-Za-z0-9._\\-]{6,}\"?"
                ,
            // JWT-shaped values.
            "\\beyJ[A-Za-z0-9._\\-]{10,}",
            // Common provider key prefixes.
            "\\b(ghp_|gho_|sk-|xox[baprs]-|AKIA)[A-Za-z0-9._\\-]{6,}"
                ,
            // Email addresses.
            "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}"
        ]
        .compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let whitespace = try? NSRegularExpression(pattern: "\\s+")

    static let maxLength = 140
    static let redactionMarker = "[已隐藏]"
    private static let placeholder = "内容已隐藏"

    /// Redacts credential-shaped substrings, collapses whitespace, and truncates.
    /// Empty or fully-redacted results collapse to `placeholder` so the UI never
    /// renders a blank error line.
    static func sanitize(_ raw: String) -> String {
        var text = raw

        for pattern in sensitivePatterns {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = pattern.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: redactionMarker)
            )
        }

        if let whitespace {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = whitespace.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty || text == redactionMarker {
            return placeholder
        }
        if text.count > maxLength {
            text = String(text.prefix(maxLength)) + "…"
        }
        return text
    }

    /// Sanitizes a localized error description for display.
    static func sanitize(_ error: Error) -> String {
        sanitize(error.localizedDescription)
    }
}