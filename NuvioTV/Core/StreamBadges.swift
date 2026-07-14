import Foundation
import SwiftUI

/// Badger integration (https://nintle.github.io/Badger/): community-made
/// badge packs for stream rows. A pack is a JSON config of regex filters —
/// each with a badge image URL and/or tag colors — matched against a link's
/// filename/name/title/description; matches render as chips on the source
/// row. Schema mirrors the official Android app's StreamBadgeRules parser
/// (filters[]: name/pattern/imageURL/isEnabled/tagColor/tagStyle/textColor/
/// borderColor; unknown keys ignored; groups only organize the editor).
struct StreamBadge: Equatable, Identifiable {
    let name: String
    let imageURL: String
    let tagColor: String
    let tagStyle: String
    let textColor: String
    let borderColor: String

    var id: String { "\(name)|\(imageURL)" }
    var isImage: Bool { !imageURL.isEmpty }
}

@MainActor
final class StreamBadgeStore: ObservableObject {
    @Published private(set) var sourceURL: String = ""
    @Published private(set) var filterCount: Int = 0
    /// Human-readable outcome of the last import attempt, for the Settings row.
    @Published private(set) var lastStatus: String?

    var isConfigured: Bool { filterCount > 0 }

    private struct Compiled {
        let regex: NSRegularExpression
        /// Cheap lowercase literal pre-screen (same trick as the Android app):
        /// skip the regex when the candidate doesn't even contain this.
        let hint: String?
        let badge: StreamBadge
    }

    private var compiled: [Compiled] = []
    /// Per-entry match cache — entries are immutable, rows re-render often.
    private var cache: [UUID: [StreamBadge]] = [:]

    private static let urlKey = "nuvio.badges.url.v1"
    private static let payloadKey = "nuvio.badges.payload.v1"

    /// Fired after a LOCAL config change (import/remove) so account sync can
    /// push. Suppressed while applying remote data.
    var onLocalChange: (() -> Void)?
    private var suppressChange = false

    init() {
        sourceURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        if let payload = UserDefaults.standard.data(forKey: Self.payloadKey) {
            compileFilters(from: payload)
        }
    }

    // MARK: - Import / remove

    /// Fetch a Badger JSON config and activate it. Returns nil on success,
    /// else an error description (also mirrored into `lastStatus`).
    @discardableResult
    func importConfig(from urlString: String) async -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            lastStatus = "Enter a valid http(s) URL"
            return lastStatus
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: request)
            let count = try Self.parseFilters(from: data).count
            guard count > 0 else {
                lastStatus = "No usable filters in that config"
                return lastStatus
            }
            UserDefaults.standard.set(trimmed, forKey: Self.urlKey)
            UserDefaults.standard.set(data, forKey: Self.payloadKey)
            sourceURL = trimmed
            compileFilters(from: data)
            lastStatus = "Imported \(filterCount) badge filters"
            if !suppressChange { onLocalChange?() }
            return nil
        } catch {
            lastStatus = "Import failed: \(error.localizedDescription)"
            return lastStatus
        }
    }

    func removeConfig() {
        UserDefaults.standard.removeObject(forKey: Self.urlKey)
        UserDefaults.standard.removeObject(forKey: Self.payloadKey)
        sourceURL = ""
        compiled = []
        cache = [:]
        filterCount = 0
        lastStatus = nil
        if !suppressChange { onLocalChange?() }
    }

    // MARK: - Nuvio account sync (mirrors Android's stream_badge_settings)

    /// Apply the account's badge rules — the Android/Fusion `StreamBadgeRules`
    /// JSON: `{"imports":[{"sourceUrl","filters":[…],"groups":[…],"isActive"}]}`.
    /// The active import's EMBEDDED filters are used directly (no re-fetch),
    /// so a pack imported on another device lights up here immediately.
    func applyRemoteRules(_ rulesJSON: String) {
        guard let data = rulesJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let imports = root["imports"] as? [[String: Any]], !imports.isEmpty
        else {
            // Empty/removed remotely → clear locally too (only if we had one).
            if isConfigured {
                suppressChange = true
                removeConfig()
                suppressChange = false
            }
            return
        }
        let active = imports.first { ($0["isActive"] as? Bool ?? $0["active"] as? Bool) == true } ?? imports[0]
        let remoteURL = (active["sourceUrl"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard let filters = active["filters"] as? [[String: Any]], !filters.isEmpty else { return }
        // Same source already active → nothing to do.
        if isConfigured, !remoteURL.isEmpty, remoteURL.caseInsensitiveCompare(sourceURL) == .orderedSame { return }

        guard let payload = try? JSONSerialization.data(withJSONObject: ["filters": filters]) else { return }
        suppressChange = true
        UserDefaults.standard.set(remoteURL, forKey: Self.urlKey)
        UserDefaults.standard.set(payload, forKey: Self.payloadKey)
        sourceURL = remoteURL
        compileFilters(from: payload)
        lastStatus = "Synced \(filterCount) badge filters from your Nuvio account"
        suppressChange = false
    }

    /// Our config in the Android `StreamBadgeRules` shape, for pushing to the
    /// account. nil when nothing is configured (encoded as empty imports so
    /// other devices clear too).
    func syncRulesJSON() -> String? {
        guard isConfigured,
              let payload = UserDefaults.standard.data(forKey: Self.payloadKey),
              let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let filters = root["filters"] as? [[String: Any]]
        else {
            return #"{"imports":[]}"#
        }
        let rules: [String: Any] = [
            "imports": [[
                "sourceUrl": sourceURL,
                "filters": filters,
                "groups": (root["groups"] as? [[String: Any]]) ?? [],
                "isActive": true,
            ]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Matching

    /// Badges for one source row, matched once and cached (regex work).
    func badges(for entry: StreamEntry) -> [StreamBadge] {
        guard !compiled.isEmpty else { return [] }
        if let hit = cache[entry.id] { return hit }
        if cache.count > 4096 { cache = [:] }   // bound a long session

        // Same candidate set as the Android matcher, reduced to our model.
        let candidates = [
            entry.stream.behaviorHints?.filename,
            entry.stream.name,
            entry.stream.title,
            entry.stream.description,
        ].compactMap { $0?.isEmpty == false ? $0 : nil }
        guard !candidates.isEmpty else { cache[entry.id] = []; return [] }
        let lowered = candidates.map { $0.lowercased() }

        var seen = Set<String>()
        var matched: [StreamBadge] = []
        outer: for filter in compiled {
            for (i, candidate) in candidates.enumerated() {
                if let hint = filter.hint, !lowered[i].contains(hint) { continue }
                let range = NSRange(candidate.startIndex..., in: candidate)
                if filter.regex.firstMatch(in: candidate, range: range) != nil {
                    if seen.insert(filter.badge.id).inserted { matched.append(filter.badge) }
                    continue outer
                }
            }
        }
        cache[entry.id] = matched
        return matched
    }

    // MARK: - Parsing (tolerant, mirrors the Android schema)

    private struct Payload: Decodable {
        struct Filter: Decodable {
            let name: String?
            let pattern: String?
            let imageURL: String?
            let isEnabled: Bool?
            let tagColor: String?
            let tagStyle: String?
            let textColor: String?
            let borderColor: String?
        }
        let filters: [Filter]?
    }

    private static func parseFilters(from data: Data) throws -> [(pattern: String, badge: StreamBadge)] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return (payload.filters ?? []).compactMap { filter in
            let name = (filter.name ?? "").trimmingCharacters(in: .whitespaces)
            let pattern = (filter.pattern ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !pattern.isEmpty, filter.isEnabled ?? true else { return nil }
            let badge = StreamBadge(
                name: name,
                imageURL: filter.imageURL ?? "",
                tagColor: filter.tagColor ?? "",
                tagStyle: filter.tagStyle ?? "",
                textColor: filter.textColor ?? "",
                borderColor: filter.borderColor ?? ""
            )
            return (pattern, badge)
        }
    }

    private func compileFilters(from data: Data) {
        let parsed = (try? Self.parseFilters(from: data)) ?? []
        compiled = parsed.compactMap { pattern, badge in
            // No implicit flags — Badger patterns carry their own (?i) etc.,
            // matching how the Android app compiles them.
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return Compiled(regex: regex, hint: Self.literalHint(pattern), badge: badge)
        }
        filterCount = compiled.count
        cache = [:]
    }

    /// A short literal extracted from simple patterns for the pre-screen;
    /// nil when the pattern is too regex-y to reduce safely.
    private static func literalHint(_ pattern: String) -> String? {
        let meta = CharacterSet(charactersIn: #"\[](){}*+?|^$."#)
        if pattern.count >= 2, pattern.rangeOfCharacter(from: meta) == nil {
            return pattern.lowercased()
        }
        if pattern.contains("|") { return nil }
        let stripped = pattern
            .replacingOccurrences(of: #"\b"#, with: "")
            .replacingOccurrences(of: "(?i)", with: "")
            .replacingOccurrences(of: "(?:", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if stripped.count >= 2, stripped.rangeOfCharacter(from: meta) == nil {
            return stripped.lowercased()
        }
        return nil
    }
}

// MARK: - Chip rendering

/// One row of badge chips (image badges first, then colored text tags),
/// visually matching the Android app: 20pt-tall chips, filled or outlined.
struct StreamBadgeChips: View {
    let badges: [StreamBadge]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges.prefix(6)) { badge in
                if badge.isImage {
                    AsyncImage(url: URL(string: badge.imageURL)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit()
                        } else {
                            Color.clear.frame(width: 1)
                        }
                    }
                    .frame(height: 20)
                } else {
                    Text(badge.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(badgeHex: badge.textColor) ?? .white)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(
                            Capsule().fill(
                                badge.tagStyle.lowercased() == "filled"
                                    ? (Color(badgeHex: badge.tagColor) ?? .white.opacity(0.15))
                                    : Color.clear
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                Color(badgeHex: badge.borderColor) ?? .clear, lineWidth: 1
                            )
                        )
                }
            }
        }
    }
}

extension Color {
    /// Badger color strings: "#RRGGBB" / "#AARRGGBB" / bare hex.
    init?(badgeHex raw: String) {
        var hex = raw.trimmingCharacters(in: .whitespaces)
        guard !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard let value = UInt64(hex, radix: 16) else { return nil }
        switch hex.count {
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        case 8:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: Double((value >> 24) & 0xFF) / 255
            )
        default:
            return nil
        }
    }
}
