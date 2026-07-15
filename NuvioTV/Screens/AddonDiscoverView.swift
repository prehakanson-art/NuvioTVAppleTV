import SwiftUI

/// A curated, one-tap-install directory of the Stremio add-ons people actually
/// want — so users don't have to hunt down and paste manifest URLs. The manual
/// "Install Add-on" box still covers anything not listed here. Opened from
/// Content & Discovery → Add-ons → Discover.
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
    case metadata = "Catalogs & Metadata"
    case streams = "Streams"
    case anime = "Anime"
    case subtitles = "Subtitles"
    case liveTV = "Live TV"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .metadata: return "square.stack.3d.up.fill"
        case .streams: return "play.rectangle.on.rectangle.fill"
        case .anime: return "sparkles.tv.fill"
        case .subtitles: return "captions.bubble.fill"
        case .liveTV: return "tv.fill"
        }
    }
}

enum AddonDirectory {
    /// Conservative, well-known, stable add-ons. Kept accurate over exhaustive —
    /// dead manifest URLs are worse than a shorter list, and the paste box
    /// handles the long tail.
    static let entries: [AddonCatalogEntry] = [
        .init(name: "Cinemeta", tagline: "Official movie & series catalogs and metadata",
              category: .metadata, manifestURL: "https://v3-cinemeta.strem.io/manifest.json"),
        .init(name: "Torrentio", tagline: "Torrent streams from many trackers. Add a debrid key for cached, instant links.",
              category: .streams, manifestURL: "https://torrentio.strem.fun/manifest.json", needsSetup: true),
        .init(name: "Comet", tagline: "Debrid-focused stream scraper with strong caching",
              category: .streams, manifestURL: "https://comet.elfhosted.com/manifest.json", needsSetup: true),
        .init(name: "MediaFusion", tagline: "Aggregated streams incl. debrid, live and more",
              category: .streams, manifestURL: "https://mediafusion.elfhosted.com/manifest.json", needsSetup: true),
        .init(name: "ThePirateBay+", tagline: "Public torrent streams from The Pirate Bay",
              category: .streams, manifestURL: "https://thepiratebay-plus.strem.fun/manifest.json"),
        .init(name: "Anime Kitsu", tagline: "Anime catalogs & metadata via Kitsu",
              category: .anime, manifestURL: "https://anime-kitsu.strem.fun/manifest.json"),
        .init(name: "OpenSubtitles v3", tagline: "Community subtitles in most languages",
              category: .subtitles, manifestURL: "https://opensubtitles-v3.strem.io/manifest.json"),
    ]
}

struct AddonDiscoverView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    let onDone: () -> Void

    @State private var installingID: String?

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            DetailScaffold(
                title: "Discover Add-ons",
                subtitle: "Popular add-ons, one tap to install"
            ) {
                ForEach(AddonCategory.allCases) { category in
                    let items = AddonDirectory.entries.filter { $0.category == category }
                    if !items.isEmpty {
                        SettingsGroupCard(title: category.rawValue) {
                            ForEach(items) { entry in
                                AddonDiscoverRow(
                                    entry: entry,
                                    installed: isInstalled(entry),
                                    installing: installingID == entry.id,
                                    onInstall: { install(entry) }
                                )
                            }
                        }
                    } else if category == .liveTV {
                        SettingsGroupCard(title: category.rawValue) {
                            Text("Paste your IPTV / M3U add-on's manifest URL in the Install Add-on box. Its channels then appear in the Live TV tab.")
                                .font(.system(size: 20))
                                .foregroundStyle(theme.palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(NuvioSpacing.md)
                        }
                    }
                }

                Text("Some stream add-ons (Torrentio, Comet, MediaFusion) work best after adding a debrid account on their own website; install here first, then open their configuration page to paste your key.")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onExitCommand { onDone() }
    }

    private func isInstalled(_ entry: AddonCatalogEntry) -> Bool {
        let normalized = AddonManager.normalizeManifestURL(entry.manifestURL)
        let base = normalized.hasSuffix("/manifest.json")
            ? String(normalized.dropLast("/manifest.json".count)) : normalized
        return addonManager.addons.contains { $0.baseURL == base }
    }

    private func install(_ entry: AddonCatalogEntry) {
        guard installingID == nil else { return }
        installingID = entry.id
        Task {
            try? await addonManager.install(manifestURL: entry.manifestURL)
            installingID = nil
        }
    }
}

private struct AddonDiscoverRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let entry: AddonCatalogEntry
    let installed: Bool
    let installing: Bool
    let onInstall: () -> Void

    var body: some View {
        Button(action: { if !installed { onInstall() } }) {
            HStack(alignment: .top, spacing: NuvioSpacing.md) {
                SettingsIconTile(symbol: entry.category.icon)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: NuvioSpacing.sm) {
                        Text(entry.name)
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(theme.palette.textPrimary)
                        if entry.needsSetup {
                            Text("Needs setup")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.palette.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(theme.palette.secondary.opacity(0.18)))
                        }
                    }
                    Text(entry.tagline)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.palette.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 900, alignment: .leading)
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
        .buttonStyle(PlainCardButtonStyle())
        .disabled(installed)
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
