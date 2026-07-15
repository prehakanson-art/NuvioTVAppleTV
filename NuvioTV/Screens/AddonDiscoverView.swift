import SwiftUI

/// A hand-picked "Recommended" add-on shown at the top of Discover, above the
/// full live community catalog.
struct AddonCatalogEntry: Identifiable {
    let name: String
    let tagline: String
    let category: AddonCategory
    let manifestURL: String
    /// Needs configuration on the add-on's own site (e.g. a debrid key) for
    /// full function; installing the base URL still adds it.
    var needsSetup: Bool = false
    var id: String { manifestURL }
}

enum AddonCategory: String, CaseIterable, Identifiable {
    case streams = "Streams"
    case metadata = "Catalogs & Metadata"
    case anime = "Anime"
    case liveTV = "Live TV"
    case subtitles = "Subtitles"
    case other = "More Add-ons"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .streams: return "play.rectangle.on.rectangle.fill"
        case .metadata: return "square.stack.3d.up.fill"
        case .anime: return "sparkles.tv.fill"
        case .liveTV: return "tv.fill"
        case .subtitles: return "captions.bubble.fill"
        case .other: return "puzzlepiece.extension.fill"
        }
    }
}

enum AddonDirectory {
    /// Recommended quick-picks — the most-wanted add-ons across categories,
    /// including a ready-to-go IPTV add-on (USA TV) that feeds the Live TV tab.
    static let featured: [AddonCatalogEntry] = [
        .init(name: "Cinemeta", tagline: "Official movie & series catalogs and metadata",
              category: .metadata, manifestURL: "https://v3-cinemeta.strem.io/manifest.json"),
        .init(name: "Torrentio", tagline: "Torrent streams from many trackers. Add a debrid key for cached, instant links.",
              category: .streams, manifestURL: "https://torrentio.strem.fun/manifest.json", needsSetup: true),
        .init(name: "Comet", tagline: "Debrid-focused stream scraper with strong caching",
              category: .streams, manifestURL: "https://comet.elfhosted.com/manifest.json", needsSetup: true),
        .init(name: "USA TV", tagline: "Live US TV — news, sports and entertainment channels. Appears in the Live TV tab.",
              category: .liveTV, manifestURL: "https://848b3516657c-usatv.baby-beamup.club/manifest.json"),
        .init(name: "Anime Kitsu", tagline: "Anime catalogs & metadata via Kitsu",
              category: .anime, manifestURL: "https://anime-kitsu.strem.fun/manifest.json"),
        .init(name: "OpenSubtitles v3", tagline: "Community subtitles in most languages",
              category: .subtitles, manifestURL: "https://opensubtitles-v3.strem.io/manifest.json"),
    ]
}

/// A single row's data, unified across the curated "Recommended" picks and the
/// live community catalog so one row view renders both.
private struct DiscoverItem: Identifiable {
    let url: String
    let name: String
    let subtitle: String
    let category: AddonCategory
    let needsSetup: Bool
    var id: String { url }
}

struct AddonDiscoverView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    let onDone: () -> Void
    /// When true, only add-ons that contribute catalogs are shown — the
    /// "Community Catalogs" page reached from the Catalogs settings.
    var catalogsOnly: Bool = false

    @State private var installingID: String?
    @State private var remote: [RemoteAddon] = []
    @State private var loading = true
    // A freshly-presented cover doesn't self-focus a bare list on tvOS; drive
    // initial focus onto the first row.
    @FocusState private var focusedID: String?

    private static let displayOrder: [AddonCategory] =
        [.streams, .liveTV, .metadata, .anime, .subtitles, .other]

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            DetailScaffold(
                title: catalogsOnly ? "Community Catalogs" : "Discover Add-ons",
                subtitle: catalogsOnly
                    ? "Add catalog add-ons — their rows appear on Home"
                    : "Recommended picks and the full Stremio community catalog"
            ) {
                LazyVStack(alignment: .leading, spacing: NuvioSpacing.xl) {
                    section("Recommended", items: featuredItems)

                    if loading {
                        loadingRow
                    } else if remote.isEmpty {
                        Text("Couldn't reach the community catalog right now. The Recommended add-ons above still install, and you can paste any manifest URL in the Install Add-on box.")
                            .font(.system(size: 19))
                            .foregroundStyle(theme.palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(Self.displayOrder) { category in
                            let items = liveItems(for: category)
                            if !items.isEmpty {
                                section(category.rawValue, items: items)
                            }
                        }
                    }
                }
            }
        }
        .onExitCommand { onDone() }
        .task { await loadCatalog() }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if focusedID == nil { focusedID = AddonDirectory.featured.first?.manifestURL }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func section(_ title: String, items: [DiscoverItem]) -> some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 18, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(theme.palette.secondary)
                .padding(.horizontal, 8)
            ForEach(items) { item in
                let installed = isInstalled(item.url)
                Button {
                    if !installed { install(item.url) }
                } label: {
                    AddonDiscoverRowLabel(
                        item: item,
                        installed: installed,
                        installing: installingID == item.url
                    )
                }
                .buttonStyle(PlainCardButtonStyle())
                .focused($focusedID, equals: item.url)
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: NuvioSpacing.md) {
            ProgressView().tint(theme.palette.secondary)
            Text("Loading community add-ons…")
                .font(.system(size: 20))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, NuvioSpacing.md)
    }

    // MARK: Data

    /// Categories that contribute Home catalog rows (used by the catalogs-only page).
    private static let catalogCategories: Set<AddonCategory> = [.metadata, .anime, .liveTV]

    private var featuredItems: [DiscoverItem] {
        AddonDirectory.featured
            .filter { !catalogsOnly || Self.catalogCategories.contains($0.category) }
            .map {
                DiscoverItem(url: $0.manifestURL, name: $0.name, subtitle: $0.tagline,
                             category: $0.category, needsSetup: $0.needsSetup)
            }
    }

    /// Live add-ons in a category, minus any already shown under Recommended.
    /// In catalogs-only mode, only add-ons that actually serve a `catalog`.
    private func liveItems(for category: AddonCategory) -> [DiscoverItem] {
        let featuredBases = Set(AddonDirectory.featured.map { Self.base($0.manifestURL) })
        return remote
            .filter { $0.category == category
                && !featuredBases.contains(Self.base($0.transportUrl))
                && (!catalogsOnly || $0.resources.contains(where: { $0.lowercased() == "catalog" })) }
            .map {
                DiscoverItem(url: $0.transportUrl, name: $0.name,
                             subtitle: $0.description ?? "", category: category, needsSetup: false)
            }
    }

    private func loadCatalog() async {
        loading = true
        remote = await AddonCatalogService.fetchAll()
        loading = false
    }

    private static func base(_ url: String) -> String {
        let n = AddonManager.normalizeManifestURL(url)
        return n.hasSuffix("/manifest.json") ? String(n.dropLast("/manifest.json".count)) : n
    }

    private func isInstalled(_ url: String) -> Bool {
        let base = Self.base(url)
        return addonManager.addons.contains { $0.baseURL == base }
    }

    private func install(_ url: String) {
        guard installingID == nil else { return }
        installingID = url
        Task {
            try? await addonManager.install(manifestURL: url)
            installingID = nil
        }
    }
}

/// The row VISUAL only — used as a Button's `label`, so `@Environment(\.isFocused)`
/// here reflects that button's own focus and the ring/highlight actually shows.
/// (The Button and `.focused` live in the parent; a Button is never disabled —
/// installed rows just no-op — so every row stays focusable.)
private struct AddonDiscoverRowLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let item: DiscoverItem
    let installed: Bool
    let installing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: NuvioSpacing.md) {
            SettingsIconTile(symbol: item.category.icon)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: NuvioSpacing.sm) {
                    Text(item.name)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(theme.palette.textPrimary)
                        .lineLimit(1)
                    if item.needsSetup {
                        Text("Needs setup")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.palette.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(theme.palette.secondary.opacity(0.18)))
                    }
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 1000, alignment: .leading)
                }
            }
            Spacer(minLength: NuvioSpacing.lg)
            accessory
                .padding(.top, 2)
        }
        .padding(.horizontal, NuvioSpacing.md)
        .padding(.vertical, NuvioSpacing.md)
        .frame(minHeight: 76)
        .frame(maxWidth: .infinity)
        .background(SettingsRowBackground(isFocused: isFocused))
    }

    @ViewBuilder
    private var accessory: some View {
        if installing {
            ProgressView().tint(theme.palette.secondary)
        } else if installed {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Installed")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(NuvioPrimitives.success)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Install")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isFocused ? theme.palette.onSecondary : theme.palette.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(isFocused ? theme.palette.secondary : theme.palette.secondary.opacity(0.16)))
        }
    }
}
