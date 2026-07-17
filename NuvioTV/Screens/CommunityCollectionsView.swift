import SwiftUI
import UIKit

/// One ready-made, individually-installable category — a single stable TMDB
/// network/company/discover source. Picked independently ("Install" is
/// per-category, not per-group), but installs as a FOLDER inside its group's
/// shared collection (Streaming Services / Major Studios / Trending & Top
/// Rated) rather than its own standalone collection. That grouping matches
/// the real Nuvio Android app, which renders exactly one Home row per
/// collection with no way to merge several into one row — so a shared group
/// collection is what makes Home look the same (folder tabs within one row)
/// on both platforms, instead of a separate row per category on Android. No
/// search, no manifest URL, no setup: covers are the services'/studios' own
/// official TMDB logos, fetched live so they're always current.
struct CommunityCollectionPreset: Identifiable {
    /// Section this category is grouped under while browsing — AND the group
    /// collection it installs into (see `groupCollectionID`).
    enum Group: String, CaseIterable {
        case streaming = "Streaming Services"
        case studios = "Major Studios"
        case trending = "Trending & Top Rated"

        var subtitle: String {
            switch self {
            case .streaming: return "Pick exactly the services you use — each becomes a tab in one Streaming Services row"
            case .studios: return "Every film from the studio, direct from TMDB — pick the ones you care about"
            case .trending: return "What's popular, best-reviewed, and newest right now"
            }
        }
        var icon: String {
            switch self {
            case .streaming: return "sparkles.tv.fill"
            case .studios: return "film.stack.fill"
            case .trending: return "flame.fill"
            }
        }
    }
    /// What kind of source this is — drives both the marker chips and the
    /// fallback art (an emoji tint) when there's no TMDB brand logo to fetch.
    enum Kind {
        case network, studio, trending, topRated, newest

        var markerLabel: String {
            switch self {
            case .network: return "Streaming Network"
            case .studio: return "Studio"
            case .trending: return "Trending"
            case .topRated: return "Top Rated"
            case .newest: return "Newest"
            }
        }
        /// Fallback emoji cover for sources with no brand logo (DISCOVER-type).
        var emoji: String? {
            switch self {
            case .trending: return "🔥"
            case .topRated: return "⭐️"
            case .newest: return "✨"
            case .network, .studio: return nil   // these get a real fetched logo
            }
        }
    }

    let id: String
    let group: Group
    let kind: Kind
    let title: String
    let source: CollectionSourceDTO

    var mediaLabel: String { (source.mediaType ?? "movie").lowercased() == "tv" ? "TV Shows" : "Movies" }
}

enum CommunityCollections {
    /// Stable id prefix so an installed community category can be recognized
    /// (and not duplicated) even after a rename.
    static let idPrefix = "community."

    /// Per-category cover style: "Dark" sits a logo on a tinted-dark tile
    /// (matches the app's near-black surfaces); "Bright" sits it on a
    /// near-white tile instead, which is how most streaming/studio logos are
    /// actually designed to be seen and reads much closer to their real
    /// brand color. Chosen independently per category (id → isBright), one
    /// shared UserDefaults key holding the whole map as JSON, so every view
    /// that renders a community folder — the browse picker AND the
    /// installed Home rows — reads the same live choice for that category.
    static let coverStyleKey = "nuvio.communitycoverstyle.v1"

    static func decodeCoverStyles(_ json: String) -> [String: Bool] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return dict
    }

    static func encodeCoverStyles(_ styles: [String: Bool]) -> String {
        guard let data = try? JSONEncoder().encode(styles),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private static func network(_ slug: String, _ title: String, _ tmdbId: Int) -> CommunityCollectionPreset {
        CommunityCollectionPreset(
            id: idPrefix + "streaming." + slug, group: .streaming, kind: .network, title: title,
            source: CollectionSourceDTO(tmdbSourceType: "NETWORK", title: title, tmdbId: tmdbId, mediaType: "tv")
        )
    }
    /// `extraCompanyIDs` combines several TMDB company records into one
    /// OR-matched query (verified live against TMDB) for franchises legally
    /// fragmented across multiple company entities — a single id badly
    /// undercounts those. Plain single-studio collections leave this empty.
    private static func studio(_ slug: String, _ title: String, _ tmdbId: Int,
                                extraCompanyIDs: [Int] = []) -> CommunityCollectionPreset {
        var source = CollectionSourceDTO(tmdbSourceType: "COMPANY", title: title, tmdbId: tmdbId, mediaType: "movie")
        if !extraCompanyIDs.isEmpty {
            let combined = ([tmdbId] + extraCompanyIDs).map(String.init).joined(separator: "|")
            source.filters = TmdbFiltersDTO(withCompanies: combined)
        }
        return CommunityCollectionPreset(
            id: idPrefix + "studio." + slug, group: .studios, kind: .studio, title: title, source: source
        )
    }
    private static func discover(_ slug: String, _ title: String, kind: CommunityCollectionPreset.Kind,
                                  mediaType: String, sortBy: String) -> CommunityCollectionPreset {
        CommunityCollectionPreset(
            id: idPrefix + "trending." + slug, group: .trending, kind: kind, title: title,
            source: CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: title, tmdbId: nil,
                                        mediaType: mediaType, sortBy: sortBy)
        )
    }

    static let presets: [CommunityCollectionPreset] = [
        // MARK: Streaming Services — each its own installable category.
        network("netflix", "Netflix", 213),
        network("disneyplus", "Disney+", 2739),
        network("max", "Max", 49),
        network("primevideo", "Prime Video", 1024),
        network("appletvplus", "Apple TV+", 2552),
        network("hulu", "Hulu", 453),
        network("paramountplus", "Paramount+", 4330),
        network("peacock", "Peacock", 3353),
        network("fx", "FX", 88),
        network("amc", "AMC", 174),
        network("bbc", "BBC", 4),
        network("crunchyroll", "Crunchyroll", 1112),

        // MARK: Major Studios — each its own installable category.
        // Marvel Studios (420) alone is MCU-only (~100 titles) and misses
        // classic/crossover Marvel films still legally credited elsewhere
        // (2002 Spider-Man, Into/Across the Spider-Verse, Logan, …). Combined
        // with its other TMDB company records: ~142 titles, verified live.
        studio("marvel", "Marvel Studios", 420, extraCompanyIDs: [19551, 7505, 108634, 160251]),
        studio("disney", "Walt Disney Pictures", 2),
        studio("pixar", "Pixar", 3),
        studio("lucasfilm", "Lucasfilm", 1),
        studio("warnerbros", "Warner Bros.", 174),
        studio("universal", "Universal Pictures", 33),
        studio("paramount", "Paramount Pictures", 4),
        studio("sony", "Sony Pictures", 34),
        studio("a24", "A24", 41077),
        // "DC Films" (128064) alone is only ~17 titles — a narrow, recent
        // production label. Combined with DC Entertainment (9993), the real
        // DC catalog (Batman, Joker, Aquaman, Justice League, Wonder Woman,
        // Shazam, Teen Titans, animated DC movies, …): ~69 titles, verified
        // live. (Adding Atlas Entertainment — co-produced several DC films —
        // was tried and rejected: it also makes many unrelated films, e.g.
        // Oppenheimer, Uncharted, so it pollutes rather than completes this.)
        studio("dcfilms", "DC Films", 128064, extraCompanyIDs: [9993]),
        studio("ghibli", "Studio Ghibli", 10342),
        studio("blumhouse", "Blumhouse", 3172),

        // MARK: Trending & Top Rated — each its own installable category.
        discover("moviesnow", "Trending Movies", kind: .trending, mediaType: "movie", sortBy: "popularity.desc"),
        discover("showsnow", "Trending Shows", kind: .trending, mediaType: "tv", sortBy: "popularity.desc"),
        discover("moviestop", "Top Rated Movies", kind: .topRated, mediaType: "movie", sortBy: "vote_average.desc"),
        discover("showstop", "Top Rated Shows", kind: .topRated, mediaType: "tv", sortBy: "vote_average.desc"),
        discover("newest", "Newest Releases", kind: .newest, mediaType: "movie", sortBy: "primary_release_date.desc"),
    ]

    static func presets(in group: CommunityCollectionPreset.Group) -> [CommunityCollectionPreset] {
        presets.filter { $0.group == group }
    }
}

struct CommunityCollectionsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var collections: CollectionsStore
    @EnvironmentObject private var tmdbSettings: TMDBSettingsStore
    let onDone: () -> Void

    @State private var installing: Set<String> = []
    /// Per-category cover style (id → isBright), JSON-encoded. Each category
    /// picks its own — set from the toggle on its own card, and read back by
    /// this picker AND by every already-installed community row on Home.
    @AppStorage(CommunityCollections.coverStyleKey) private var coverStylesJSON = "{}"
    /// Live-fetched official logos, keyed by preset id — fetched once per
    /// category so browsing shows real brand art, not a shared generic icon.
    @State private var logos: [String: String] = [:]
    /// True once the logo fetch pass has finished, so a network/studio whose
    /// fetch genuinely failed falls back to an icon instead of spinning
    /// forever (a nil result is never written into `logos`).
    @State private var logosLoaded = false

    /// Every installed category's preset id, across ALL group collections —
    /// "installed" is per-FOLDER now (a group collection holds several
    /// categories), not per top-level collection.
    private var installedPresetIDs: Set<String> {
        var ids = Set<String>()
        for collection in collections.collections where collection.id.hasPrefix(CommunityCollections.idPrefix) {
            for folder in collection.folders { ids.insert(folder.id) }
        }
        return ids
    }

    private let columns = [GridItem(.adaptive(minimum: 360), spacing: NuvioSpacing.lg)]

    private func isBright(_ id: String) -> Bool {
        CommunityCollections.decodeCoverStyles(coverStylesJSON)[id] ?? false
    }

    private func setBright(_ bright: Bool, for id: String) {
        var styles = CommunityCollections.decodeCoverStyles(coverStylesJSON)
        styles[id] = bright
        coverStylesJSON = CommunityCollections.encodeCoverStyles(styles)
    }

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: NuvioSpacing.xxl) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Community Collections")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(theme.palette.textPrimary)
                            Text("Curated, high-quality categories — install just the ones you want, grouped into one Home row per section.")
                                .font(.system(size: 20))
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                        Spacer()
                        Button("Done", action: onDone)
                            .font(.system(size: 22, weight: .semibold))
                    }

                    if !tmdbSettings.isEnabled {
                        Text("Enable TMDB in Settings → Integrations so these categories have something to show.")
                            .font(.system(size: 19))
                            .foregroundStyle(NuvioPrimitives.error)
                    }

                    ForEach(CommunityCollectionPreset.Group.allCases, id: \.self) { group in
                        section(for: group)
                    }
                }
                .padding(NuvioSpacing.huge)
            }
        }
        .task {
            consolidateIndividualCollections()
            resyncPresetSources()
            await remeasureInstalledLogos()
            await loadLogos()
        }
        .onExitCommand { onDone() }
    }

    private func section(for group: CommunityCollectionPreset.Group) -> some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.lg) {
            HStack(spacing: NuvioSpacing.md) {
                Image(systemName: group.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(theme.palette.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.rawValue)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(theme.palette.textPrimary)
                    Text(group.subtitle)
                        .font(.system(size: 17))
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }

            LazyVGrid(columns: columns, spacing: NuvioSpacing.lg) {
                ForEach(CommunityCollections.presets(in: group)) { preset in
                    CommunityCollectionCard(
                        preset: preset,
                        logoURL: logos[preset.id],
                        logosLoaded: logosLoaded,
                        isBright: isBright(preset.id),
                        isInstalled: installedPresetIDs.contains(preset.id),
                        isInstalling: installing.contains(preset.id),
                        onInstall: { Task { await install(preset) } },
                        onRemove: { remove(preset) },
                        onToggleBright: { setBright($0, for: preset.id) }
                    )
                }
            }
        }
    }

    /// Fetch every network/studio's official logo up front (concurrent,
    /// cached in `logos`) so browsing shows real brand art instead of a
    /// generic icon — the whole point of splitting these into individually
    /// recognizable categories. DISCOVER-type entries (Trending/Top Rated/
    /// Newest) have no brand to fetch; they use their kind's emoji instead.
    private func loadLogos() async {
        let targets = CommunityCollections.presets.filter { $0.source.tmdbId != nil }
        await withTaskGroup(of: (String, String?).self) { group in
            for preset in targets {
                group.addTask {
                    (preset.id, await Self.brandLogo(for: preset.source))
                }
            }
            for await (id, url) in group {
                if let url { logos[id] = url }
            }
        }
        logosLoaded = true
    }

    /// A category's group collection id: one shared collection per group
    /// (Streaming Services / Major Studios / Trending & Top Rated), with each
    /// installed category as a folder inside it. The real Nuvio Android app
    /// renders exactly one Home row per collection with no way to merge
    /// several into one row — so this is what makes Home look the same
    /// (folder tabs within one row) on both platforms, instead of a separate
    /// row per category there. You still pick categories individually below;
    /// only where they land groups them.
    private static func groupCollectionID(for group: CommunityCollectionPreset.Group) -> String {
        switch group {
        case .streaming: return "community.streaming"
        case .studios: return "community.studios"
        case .trending: return "community.trending"
        }
    }

    /// One-time migration: an earlier build installed each category as its OWN
    /// standalone collection (its own Home row per category, and its own
    /// folder id — a random UUID). Fold any of those still around into their
    /// group's collection, normalizing the folder id to the stable preset id
    /// so future installs/removals/re-runs of this migration all agree on
    /// identity.
    private func consolidateIndividualCollections() {
        for preset in CommunityCollections.presets {
            guard let standalone = collections.collections.first(where: { $0.id == preset.id }),
                  var folder = standalone.folders.first else { continue }
            collections.remove(id: preset.id)
            folder.id = preset.id
            addFolder(folder, to: preset.group)
        }
    }

    /// One-time fix for categories installed BEFORE a preset's TMDB source was
    /// corrected (e.g. Marvel/DC's single-company id was too narrow and
    /// undercounted their real catalog — see the `studio()` builder). Already-
    /// installed folders keep whatever source they were given at install
    /// time, so without this they'd stay stuck on the old, incomplete query
    /// even after the app fixes it. Finds each preset's folder (by its now-
    /// stable id) across every community collection and re-syncs its
    /// `sources` to the CURRENT preset definition when it's changed.
    private func resyncPresetSources() {
        for preset in CommunityCollections.presets {
            for collection in collections.collections where collection.id.hasPrefix(CommunityCollections.idPrefix) {
                guard let idx = collection.folders.firstIndex(where: { $0.id == preset.id }),
                      collection.folders[idx].sources != [preset.source] else { continue }
                var updated = collection
                updated.folders[idx].sources = [preset.source]
                collections.update(updated)
            }
        }
    }

    /// Insert/replace a category's folder in its group's collection, creating
    /// that group collection on first use.
    private func addFolder(_ folder: NuvioCollectionFolder, to group: CommunityCollectionPreset.Group) {
        let groupID = Self.groupCollectionID(for: group)
        if var existing = collections.collections.first(where: { $0.id == groupID }) {
            if let idx = existing.folders.firstIndex(where: { $0.id == folder.id }) {
                existing.folders[idx] = folder
            } else {
                existing.folders.append(folder)
            }
            collections.update(existing)
        } else {
            var newCollection = NuvioCollection(id: groupID, title: group.rawValue, folders: [folder])
            newCollection.focusGlowEnabled = true
            collections.add(newCollection)
        }
    }

    /// Remove a single category's folder from its group's collection —
    /// deleting the whole group collection only if it was the last one left.
    private func remove(_ preset: CommunityCollectionPreset) {
        let groupID = Self.groupCollectionID(for: preset.group)
        guard var existing = collections.collections.first(where: { $0.id == groupID }) else { return }
        existing.folders.removeAll { $0.id == preset.id }
        if existing.folders.isEmpty {
            collections.remove(id: groupID)
        } else {
            collections.update(existing)
        }
    }

    /// One-time fix for categories installed BEFORE tileShape was measured:
    /// every logo-covered folder was hardcoded "LANDSCAPE" regardless of its
    /// real proportions, which is what warped/cropped the pictures both here
    /// and on the real Nuvio Android app. Re-measures each already-installed
    /// community folder's actual logo and corrects its declared shape.
    private func remeasureInstalledLogos() async {
        for collection in collections.collections where collection.id.hasPrefix(CommunityCollections.idPrefix) {
            var changed = false
            var updated = collection
            for i in updated.folders.indices {
                guard let cover = updated.folders[i].coverImageUrl, !cover.isEmpty else { continue }
                let correctShape = await Self.measuredTileShape(for: cover)
                if updated.folders[i].tileShape != correctShape {
                    updated.folders[i].tileShape = correctShape
                    changed = true
                }
            }
            if changed { collections.update(updated) }
        }
    }

    private func install(_ preset: CommunityCollectionPreset) async {
        guard !installing.contains(preset.id) else { return }
        installing.insert(preset.id)
        defer { installing.remove(preset.id) }

        // The folder id IS the preset id (stable across relaunches/re-installs
        // and across the consolidation migration above) — that's how
        // `installedPresetIDs` and `remove(_:)` find this exact category
        // again inside its shared group collection.
        var folder = NuvioCollectionFolder(id: preset.id, title: preset.title, sources: [preset.source])
        var resolvedLogo = logos[preset.id]
        if resolvedLogo == nil {
            resolvedLogo = await Self.brandLogo(for: preset.source)
        }
        if let logo = resolvedLogo {
            folder.tileShape = await Self.measuredTileShape(for: logo)
            folder.coverImageUrl = logo
        } else {
            folder.tileShape = "SQUARE"
            folder.coverEmoji = preset.kind.emoji
        }

        addFolder(folder, to: preset.group)
    }

    /// Official studio/network logo for a preset source, when TMDB has one.
    private static func brandLogo(for source: CollectionSourceDTO) async -> String? {
        guard let id = source.tmdbId else { return nil }
        switch source.tmdbSourceType?.uppercased() {
        case "NETWORK": return await TMDBService.networkBrand(id: id)?.logoURL
        case "COMPANY": return await TMDBService.companyBrand(id: id)?.logoURL
        default: return nil
        }
    }

    /// Declares the tileShape that actually matches a logo's real proportions.
    /// tvOS renders a folder cover with `.fill` (crop-to-cover); the real
    /// Nuvio Android app renders it with `ContentScale.FillBounds` (stretch to
    /// EXACTLY fill the declared shape's aspect ratio, no crop) — so a logo
    /// whose real aspect ratio doesn't match the declared shape gets visibly
    /// warped on Android and cropped on tvOS. Both were hardcoded to
    /// "LANDSCAPE" (16:9) regardless of the actual image, which is why
    /// pictures came in "the wrong format": most brand marks are much closer
    /// to square (or a wide-but-not-16:9 wordmark) than true 16:9. Measuring
    /// the real image once at install time and declaring the closest-matching
    /// shape makes the stretch/crop a no-op (or minimal) on both platforms.
    private static func measuredTileShape(for urlString: String) async -> String {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data), image.size.height > 0 else { return "SQUARE" }
        let ratio = image.size.width / image.size.height
        // LANDSCAPE's declared ratio is 16:9 (≈1.78); only choose it when the
        // logo is genuinely close to that. Most brand marks are much nearer
        // square (or a moderately wide wordmark), which SQUARE (1:1) fits far
        // better than forcing a 16:9 stretch/crop on them.
        return ratio >= 1.5 ? "LANDSCAPE" : "SQUARE"
    }
}

private struct CommunityCollectionCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let preset: CommunityCollectionPreset
    let logoURL: String?
    let logosLoaded: Bool
    let isBright: Bool
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let onRemove: () -> Void
    let onToggleBright: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            HStack(spacing: NuvioSpacing.md) {
                artTile
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    // Markers derived from THIS category's own source — not a
                    // stale list of sibling tab names — so they always match
                    // what's actually inside.
                    FlowChips(labels: [preset.mediaLabel, preset.kind.markerLabel])
                }
                // The VStack (not a trailing Spacer) claims all remaining
                // width, so the title/chips get every bit of room the card
                // has instead of being squeezed by a competing flexible
                // sibling — that squeeze was cutting chip text off entirely.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Per-category Dark/Bright choice — each category remembers its
            // own pick independently, applied live to its Home row too.
            HStack(spacing: NuvioSpacing.sm) {
                coverStyleOption(title: "Dark", bright: false)
                coverStyleOption(title: "Bright", bright: true)
            }

            Button {
                isInstalled ? onRemove() : onInstall()
            } label: {
                if isInstalling {
                    HStack(spacing: NuvioSpacing.sm) {
                        ProgressView()
                        Text("Installing…")
                    }
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SettingsActionRow(
                        title: isInstalled ? "Installed — Remove" : "Install",
                        leadingIcon: isInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill"
                    )
                }
            }
            .buttonStyle(PlainCardButtonStyle())
            .disabled(isInstalling)
        }
        .padding(NuvioSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: NuvioRadius.lg, style: .continuous)
                .fill(theme.palette.backgroundCard.opacity(0.5))
        )
    }

    private func coverStyleOption(title: String, bright: Bool) -> some View {
        Button { onToggleBright(bright) } label: {
            CoverStylePill(label: title, selected: isBright == bright)
        }
        .buttonStyle(PlainCardButtonStyle())
    }

    /// High-quality per-category art: the real TMDB brand logo for a network
    /// or studio; a tinted emoji badge for the open-ended discover categories
    /// (Trending/Top Rated/Newest have no single brand to show).
    @ViewBuilder
    private var artTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .fill(isBright ? AnyShapeStyle(NuvioPrimitives.neutral100) : AnyShapeStyle(tintColor.opacity(0.18)))
            if let logoURL {
                RemoteImage(url: logoURL, contentMode: .fit)
                    .padding(8)
            } else if let emoji = preset.kind.emoji {
                Text(emoji).font(.system(size: 30))
            } else if !logosLoaded {
                // Still fetching this network/studio's logo.
                ProgressView()
            } else {
                // Fetch finished with no logo (network hiccup, or TMDB has
                // none for this id) — fall back to a generic icon instead of
                // spinning forever.
                Image(systemName: preset.kind == .network ? "tv.fill" : "film.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(tintColor)
            }
        }
        .frame(width: 64, height: 64)
    }

    private var tintColor: Color {
        switch preset.kind {
        case .network: return NuvioPrimitives.blue500
        case .studio: return NuvioPrimitives.violet500
        case .trending: return NuvioPrimitives.amber500
        case .topRated: return NuvioPrimitives.rating
        case .newest: return NuvioPrimitives.green500
        }
    }
}

/// Simple chip row — used here to show each category's own media-type + kind
/// markers. Each label is capped to one line with a shrink fallback so a
/// tight card compresses the text slightly instead of wrapping it inside the
/// capsule (which is what made words disappear/overlap at narrower widths).
private struct FlowChips: View {
    @EnvironmentObject private var theme: ThemeManager
    let labels: [String]

    var body: some View {
        HStack(spacing: NuvioSpacing.sm) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Compact selectable pill for the per-category Dark/Bright toggle — sized
/// for a small in-card control, unlike the larger `FolderTabPill` used for
/// the full-screen collection folder tabs.
private struct CoverStylePill: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let label: String
    let selected: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(selected ? theme.palette.onSecondary : theme.palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, NuvioSpacing.sm)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? theme.palette.secondary
                               : (isFocused ? theme.palette.focusBackground : Color.white.opacity(0.08)))
            )
            .overlay(Capsule().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 2))
            .scaleEffect(isFocused ? 1.05 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }
}
