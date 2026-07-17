import SwiftUI

/// One ready-made collection: a title/subtitle plus the TMDB sources that fill
/// its folders. Every source is a stable, well-known TMDB network/company/
/// discover id, so installing needs no search, no manifest URL, no setup —
/// the folder covers are the studios'/services' own official logos, fetched
/// live from TMDB so they're always current.
struct CommunityCollectionPreset: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let folders: [(title: String, source: CollectionSourceDTO)]
}

enum CommunityCollections {
    /// Stable id prefix so an installed community collection can be recognized
    /// (and not duplicated) even after a rename.
    static let idPrefix = "community."

    static let presets: [CommunityCollectionPreset] = [
        CommunityCollectionPreset(
            id: idPrefix + "streaming",
            title: "Streaming Services",
            subtitle: "Netflix, Disney+, Max, Prime Video, and more — everything each service has on TMDB",
            icon: "sparkles.tv.fill",
            folders: [
                ("Netflix", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Netflix", tmdbId: 213, mediaType: "tv")),
                ("Disney+", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Disney+", tmdbId: 2739, mediaType: "tv")),
                ("Max", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Max", tmdbId: 49, mediaType: "tv")),
                ("Prime Video", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Prime Video", tmdbId: 1024, mediaType: "tv")),
                ("Apple TV+", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Apple TV+", tmdbId: 2552, mediaType: "tv")),
                ("Hulu", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Hulu", tmdbId: 453, mediaType: "tv")),
                ("Paramount+", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Paramount+", tmdbId: 4330, mediaType: "tv")),
                ("Peacock", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Peacock", tmdbId: 3353, mediaType: "tv")),
                ("FX", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "FX", tmdbId: 88, mediaType: "tv")),
                ("AMC", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "AMC", tmdbId: 174, mediaType: "tv")),
                ("BBC", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "BBC", tmdbId: 4, mediaType: "tv")),
                ("Crunchyroll", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Crunchyroll", tmdbId: 1112, mediaType: "tv")),
            ]
        ),
        CommunityCollectionPreset(
            id: idPrefix + "studios",
            title: "Major Studios",
            subtitle: "Marvel, Pixar, Disney, Warner Bros., A24, and more — every film from the studio, direct from TMDB",
            icon: "film.stack.fill",
            folders: [
                ("Marvel Studios", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Marvel Studios", tmdbId: 420, mediaType: "movie")),
                ("Walt Disney Pictures", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Walt Disney Pictures", tmdbId: 2, mediaType: "movie")),
                ("Pixar", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Pixar", tmdbId: 3, mediaType: "movie")),
                ("Lucasfilm", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Lucasfilm", tmdbId: 1, mediaType: "movie")),
                ("Warner Bros.", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Warner Bros.", tmdbId: 174, mediaType: "movie")),
                ("Universal Pictures", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Universal Pictures", tmdbId: 33, mediaType: "movie")),
                ("Paramount Pictures", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Paramount Pictures", tmdbId: 4, mediaType: "movie")),
                ("Sony Pictures", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Sony Pictures", tmdbId: 34, mediaType: "movie")),
                ("A24", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "A24", tmdbId: 41077, mediaType: "movie")),
                ("DC Films", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "DC Films", tmdbId: 128064, mediaType: "movie")),
                ("Studio Ghibli", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Studio Ghibli", tmdbId: 10342, mediaType: "movie")),
                ("Blumhouse", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Blumhouse", tmdbId: 3172, mediaType: "movie")),
            ]
        ),
        CommunityCollectionPreset(
            id: idPrefix + "trending",
            title: "Trending & Top Rated",
            subtitle: "What's popular and best-reviewed right now, movies and shows",
            icon: "flame.fill",
            folders: [
                ("Trending Movies", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Trending Movies", tmdbId: nil, mediaType: "movie", sortBy: "popularity.desc")),
                ("Trending Shows", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Trending Shows", tmdbId: nil, mediaType: "tv", sortBy: "popularity.desc")),
                ("Top Rated Movies", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Top Rated Movies", tmdbId: nil, mediaType: "movie", sortBy: "vote_average.desc")),
                ("Top Rated Shows", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Top Rated Shows", tmdbId: nil, mediaType: "tv", sortBy: "vote_average.desc")),
                ("Newest Releases", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Newest Releases", tmdbId: nil, mediaType: "movie", sortBy: "primary_release_date.desc")),
            ]
        ),
    ]
}

struct CommunityCollectionsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var collections: CollectionsStore
    @EnvironmentObject private var tmdbSettings: TMDBSettingsStore
    let onDone: () -> Void

    @State private var installing: Set<String> = []

    private var installedIDs: Set<String> {
        Set(collections.collections.map(\.id))
    }

    private let columns = [GridItem(.adaptive(minimum: 420), spacing: NuvioSpacing.lg)]

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: NuvioSpacing.xl) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Community Collections")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(theme.palette.textPrimary)
                            Text("Curated, high-quality collections — one tap and they're on Home. No setup.")
                                .font(.system(size: 20))
                                .foregroundStyle(theme.palette.textSecondary)
                        }
                        Spacer()
                        Button("Done", action: onDone)
                            .font(.system(size: 22, weight: .semibold))
                    }

                    if !tmdbSettings.isEnabled {
                        Text("Enable TMDB in Settings → Integrations so these collections have something to show.")
                            .font(.system(size: 19))
                            .foregroundStyle(NuvioPrimitives.error)
                    }

                    LazyVGrid(columns: columns, spacing: NuvioSpacing.lg) {
                        ForEach(CommunityCollections.presets) { preset in
                            CommunityCollectionCard(
                                preset: preset,
                                isInstalled: installedIDs.contains(preset.id),
                                isInstalling: installing.contains(preset.id),
                                onInstall: { Task { await install(preset) } },
                                onRemove: { collections.remove(id: preset.id) }
                            )
                        }
                    }
                }
                .padding(NuvioSpacing.huge)
            }
        }
        .onExitCommand { onDone() }
    }

    private func install(_ preset: CommunityCollectionPreset) async {
        guard !installing.contains(preset.id) else { return }
        installing.insert(preset.id)
        defer { installing.remove(preset.id) }

        var folders: [NuvioCollectionFolder] = []
        await withTaskGroup(of: (Int, NuvioCollectionFolder).self) { group in
            for (index, entry) in preset.folders.enumerated() {
                group.addTask {
                    let logo = await Self.brandLogo(for: entry.source)
                    var folder = NuvioCollectionFolder(id: UUID().uuidString, title: entry.title, sources: [entry.source])
                    folder.tileShape = "LANDSCAPE"
                    folder.coverImageUrl = logo
                    return (index, folder)
                }
            }
            var ordered = [Int: NuvioCollectionFolder]()
            for await (index, folder) in group { ordered[index] = folder }
            folders = (0..<preset.folders.count).compactMap { ordered[$0] }
        }

        var collection = NuvioCollection(id: preset.id, title: preset.title, folders: folders)
        collection.focusGlowEnabled = true
        collections.add(collection)
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
}

private struct CommunityCollectionCard: View {
    @EnvironmentObject private var theme: ThemeManager
    let preset: CommunityCollectionPreset
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.md) {
            HStack(spacing: NuvioSpacing.md) {
                Image(systemName: preset.icon)
                    .font(.system(size: 30))
                    .foregroundStyle(theme.palette.secondary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(theme.palette.secondary.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(theme.palette.textPrimary)
                    Text("\(preset.folders.count) folders")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.palette.textTertiary)
                }
                Spacer()
            }

            Text(preset.subtitle)
                .font(.system(size: 19))
                .foregroundStyle(theme.palette.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Folder name chips give a preview of what's inside without a fetch.
            FlowChips(labels: preset.folders.map(\.title))

            Button {
                isInstalled ? onRemove() : onInstall()
            } label: {
                if isInstalling {
                    HStack(spacing: NuvioSpacing.sm) {
                        ProgressView()
                        Text("Installing…")
                    }
                    .font(.system(size: 22, weight: .semibold))
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
}

/// Simple wrapping chip row for a folder-name preview.
private struct FlowChips: View {
    @EnvironmentObject private var theme: ThemeManager
    let labels: [String]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: NuvioSpacing.sm) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
        }
        .scrollClipDisabled()
    }
}
