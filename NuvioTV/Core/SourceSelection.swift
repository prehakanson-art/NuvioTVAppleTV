import Foundation

/// Quality split: the resolution a stream advertises. Display order.
enum ResolutionTier: Int, CaseIterable {
    case uhd2160 = 0
    case fhd1080
    case hd720
    case sd480
    case other

    var title: String {
        switch self {
        case .uhd2160: return "2160p"
        case .fhd1080: return "1080p"
        case .hd720:   return "720p"
        case .sd480:   return "480p"
        case .other:   return "Other"
        }
    }

    static func from(resolutionLabel: String?) -> ResolutionTier {
        switch resolutionLabel {
        case "2160p": return .uhd2160
        case "1080p": return .fhd1080
        case "720p":  return .hd720
        case "480p":  return .sd480
        default:      return .other
        }
    }
}

/// One block on the Sources page: a heading (an addon, or the synthetic
/// "★ Top Picks") with resolution sections under it.
struct AddonSourceGroup: Identifiable {
    var id: String { addonName }
    let addonName: String
    let sections: [SourceSection]

    var entries: [StreamEntry] { sections.flatMap(\.entries) }
}

struct SourceSection: Identifiable {
    let id: String
    /// Resolution header ("2160p" …). Empty when the list isn't tiered.
    let title: String
    let entries: [StreamEntry]
}

/// Source curation, built on `StreamEntry.sourceScore` (see
/// Stream.qualityScore): cached links dominate, then release quality, codec
/// (AV1 punished — no hardware decode on the A10X), HDR/DV, audio, seeders,
/// and a per-resolution size sweet spot. The addon's own ordering survives as
/// the tiebreak (sorts are stable).
enum SourceSelection {
    static let topPicksName = "★ Top Picks"

    /// First-seen order of the addons that returned links.
    private static func addonOrder(_ entries: [StreamEntry]) -> [String] {
        var order: [String] = []
        var seen = Set<String>()
        for entry in entries where seen.insert(entry.addonName).inserted {
            order.append(entry.addonName)
        }
        return order
    }

    /// Confirmed junk: a KNOWN size under 250 MB can't be the real thing
    /// (the 0/14 MB decoy "movies" some addons return). Unknown size passes.
    private static func isJunk(_ entry: StreamEntry) -> Bool {
        if let bytes = entry.sizeBytes, bytes > 0, bytes < 250 * 1_048_576 { return true }
        return false
    }

    private static func scored(_ entries: [StreamEntry]) -> [StreamEntry] {
        entries.sorted { $0.sourceScore > $1.sourceScore }
    }

    /// Cached/direct first, addon order preserved within each half — the
    /// filters-OFF ordering (no other curation).
    static func cachedFirst(_ entries: [StreamEntry]) -> [StreamEntry] {
        entries.filter(\.isInstant) + entries.filter { !$0.isInstant }
    }

    /// The single best link per resolution across EVERY addon — the row you
    /// click 95% of the time, surfaced instead of buried per-addon.
    static func topPicks(_ entries: [StreamEntry]) -> AddonSourceGroup? {
        let eligible = entries.filter { !isJunk($0) }
        guard !eligible.isEmpty else { return nil }
        var sections: [SourceSection] = []
        for tier in ResolutionTier.allCases {
            let inTier = eligible.filter { ResolutionTier.from(resolutionLabel: $0.resolutionLabel) == tier }
            guard let best = scored(inTier).first else { continue }
            sections.append(SourceSection(id: "picks.\(tier.rawValue)", title: tier.title, entries: [best]))
        }
        guard !sections.isEmpty else { return nil }
        return AddonSourceGroup(addonName: topPicksName, sections: sections)
    }

    /// Per-addon blocks: resolution sections, best-scored first, capped at
    /// `perTier` links per resolution. Junk dropped, empty sections omitted.
    static func byAddon(_ entries: [StreamEntry], perTier: Int) -> [AddonSourceGroup] {
        let cap = max(perTier, 1)
        return addonOrder(entries).compactMap { name in
            let own = entries.filter { $0.addonName == name && !isJunk($0) }
            let sections: [SourceSection] = ResolutionTier.allCases.compactMap { tier in
                let inTier = own.filter { ResolutionTier.from(resolutionLabel: $0.resolutionLabel) == tier }
                guard !inTier.isEmpty else { return nil }
                let picked = Array(scored(inTier).prefix(cap))
                return SourceSection(id: "\(name).\(tier.rawValue)", title: tier.title, entries: picked)
            }
            return sections.isEmpty ? nil : AddonSourceGroup(addonName: name, sections: sections)
        }
    }

    /// The full curated page: Top Picks on top, then each addon's blocks.
    static func curated(_ entries: [StreamEntry], perTier: Int) -> [AddonSourceGroup] {
        let perAddon = byAddon(entries, perTier: perTier)
        guard let picks = topPicks(entries), perAddon.count > 0 else { return perAddon }
        return [picks] + perAddon
    }

    /// Filters OFF: each addon's links as returned (cached floated up),
    /// capped per addon, no tiers.
    static func byAddonUnfiltered(_ entries: [StreamEntry], cap: Int) -> [AddonSourceGroup] {
        addonOrder(entries).compactMap { name in
            let own = entries.filter { $0.addonName == name }
            let capped = Array(cachedFirst(own).prefix(max(cap, 1)))
            guard !capped.isEmpty else { return nil }
            return AddonSourceGroup(
                addonName: name,
                sections: [SourceSection(id: "\(name).all", title: "", entries: capped)]
            )
        }
    }

    /// Flat list for the in-player Sources panel and failover ordering: Top
    /// Picks first (so failover tries the best links first), then addon
    /// blocks — de-duplicated by URL/hash so a pick and its addon-row twin
    /// don't cost two failover attempts.
    static func select(_ entries: [StreamEntry], perTier: Int) -> [StreamEntry] {
        dedupe(curated(entries, perTier: perTier).flatMap(\.entries))
    }

    static func selectUnfiltered(_ entries: [StreamEntry], cap: Int) -> [StreamEntry] {
        dedupe(byAddonUnfiltered(entries, cap: cap).flatMap(\.entries))
    }

    private static func dedupe(_ entries: [StreamEntry]) -> [StreamEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            let key = entry.stream.url ?? entry.stream.infoHash ?? entry.id.uuidString
            return seen.insert(key).inserted
        }
    }
}
