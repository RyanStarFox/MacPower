import Foundation

enum AppVersion {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(candidate)
        let right = components(current)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    static func display(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        return value
    }

    static func components(_ raw: String) -> [Int] {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        return value.split { !$0.isNumber }.compactMap { Int($0) }
    }
}

/// Localized notes for the running version, and the same shape fetched from a GitHub release.
struct ReleaseNotes: Equatable, Sendable {
    var sections: [String: String]

    static let markerStart = "<!-- macpower-notes"
    static let markerEnd = "-->"
    static let shaMarkerStart = "<!-- macpower-sha256"

    static let current: ReleaseNotes = {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return ReleaseNotes(sections: [:]) }
        return ReleaseNotes(sections: decoded)
    }()

    /// Pulls the JSON object between the markers in a GitHub release body.
    static func parse(releaseBody: String) -> ReleaseNotes {
        guard let start = releaseBody.range(of: markerStart),
              let end = releaseBody.range(of: markerEnd, range: start.upperBound..<releaseBody.endIndex)
        else { return ReleaseNotes(sections: [:]) }
        let json = releaseBody[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return ReleaseNotes(sections: [:]) }
        return ReleaseNotes(sections: decoded)
    }

    /// Lowercase hex digest published beside the notes in a GitHub release body.
    static func sha256(in releaseBody: String) -> String? {
        guard let start = releaseBody.range(of: shaMarkerStart),
              let end = releaseBody.range(of: markerEnd, range: start.upperBound..<releaseBody.endIndex)
        else { return nil }
        let token = releaseBody[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }

    /// One visual row per bullet. Wrapped lines in the source stay with that bullet.
    static func paragraphs(in text: String) -> [String] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var items: [String] = []
        for line in lines {
            let stripped = stripMarker(line)
            if stripped.isItem || items.isEmpty {
                if !stripped.text.isEmpty { items.append(stripped.text) }
            } else if !stripped.text.isEmpty {
                items[items.count - 1] += " " + stripped.text
            }
        }
        return items
    }

    private static func stripMarker(_ line: String) -> (text: String, isItem: Bool) {
        let markers = ["•", "·", "●", "–", "—", "-", "*"]
        for marker in markers where line.hasPrefix(marker) {
            let rest = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return (rest, true)
        }
        if let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            return (String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces), true)
        }
        return (line, false)
    }

    func text(for language: AppLanguage) -> String {
        for key in Self.languageKeys(for: language) {
            if let text = sections[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return ""
    }

    /// A missing stored version counts as an update into this one, so a build
    /// from before this record still shows its notes once.
    static func shouldPresentWhatsNew(stored: String?, current: String) -> Bool {
        stored != current
    }

    static func languageKeys(for language: AppLanguage) -> [String] {
        var keys: [String] = []
        if language == .system {
            for identifier in Locale.preferredLanguages {
                let normalized = identifier.replacingOccurrences(of: "_", with: "-")
                keys.append(normalized)
                if normalized.hasPrefix("zh-Hans") || normalized == "zh-CN" || normalized == "zh-SG" {
                    keys.append("zh-Hans")
                } else if normalized.hasPrefix("zh-Hant") || normalized == "zh-TW" || normalized == "zh-HK" || normalized == "zh-MO" {
                    keys.append("zh-Hant")
                } else if normalized == "zh" {
                    keys.append("zh-Hans")
                }
                if normalized.hasPrefix("pt") { keys.append("pt-BR") }
                if let code = normalized.split(separator: "-").first {
                    keys.append(String(code))
                }
            }
        } else {
            keys.append(language.rawValue)
        }
        keys.append("en")
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }
}
