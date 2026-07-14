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

/// One block on the Sources page: an addon heading with resolution sections
/// under it.
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

    /// Flat list for the in-player Sources panel and failover ordering:
    /// addon blocks in order, best-scored first within each resolution,
    /// de-duplicated by URL/hash.
    static func select(_ entries: [StreamEntry], perTier: Int) -> [StreamEntry] {
        dedupe(byAddon(entries, perTier: perTier).flatMap(\.entries))
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
