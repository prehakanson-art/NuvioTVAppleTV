import SwiftUI

// Alternate movie/show detail pages, selectable via Settings → Themes → Detail
// Page. Reuses the real `DetailViewModel` (meta load, episodes, more-like-this)
// and the same play/select callbacks as the default `DetailView`, so navigation
// and playback are unchanged — only the layout/styling differs.
// Marquee = pure-black stage, white focus; Streamline = navy stage, accent focus.
struct ThemedDetailView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var watched: WatchedStore
    @EnvironmentObject private var mdblist: MDBListSettingsStore
    @EnvironmentObject private var tmdbSettings: TMDBSettingsStore
    @EnvironmentObject private var playerSettings: PlayerSettingsStore
    @StateObject private var viewModel: DetailViewModel

    let variant: ThemeVariant
    let onPlay: (MetaItem, MetaVideo?) -> Void
    let onPlayFromBeginning: (MetaItem, MetaVideo?) -> Void
    let onSelectItem: (MetaItem) -> Void

    init(variant: ThemeVariant, item: MetaItem,
         onPlay: @escaping (MetaItem, MetaVideo?) -> Void,
         onPlayFromBeginning: @escaping (MetaItem, MetaVideo?) -> Void = { _, _ in },
         onSelectItem: @escaping (MetaItem) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: DetailViewModel(item: item))
        self.variant = variant
        self.onPlay = onPlay
        self.onPlayFromBeginning = onPlayFromBeginning
        self.onSelectItem = onSelectItem
    }

    private var meta: MetaItem { viewModel.meta }
    private var stage: Color { variant == .marquee ? .black : HuluStyle.stage }
    private var accent: Color { variant == .marquee ? .white : theme.palette.secondary }
    private var side: CGFloat { 130 }

    private var seasonEpisodes: [MetaVideo] {
        guard let s = viewModel.selectedSeason else { return meta.episodes(season: meta.seasons.first ?? 1) }
        return meta.episodes(season: s)
    }
    /// The episode Play acts on for a series (first of the selected season).
    private var playVideo: MetaVideo? { meta.isSeries ? seasonEpisodes.first : nil }

    var body: some View {
        ZStack {
            stage.ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40) {
                    hero
                    if meta.isSeries { episodesSection }
                    if !viewModel.moreLikeThis.isEmpty { moreLikeThis }
                    Color.clear.frame(height: 60)
                }
            }
            .scrollClipDisabled()
        }
        .ignoresSafeArea(edges: [.top, .trailing])
        .task {
            await viewModel.load(addonManager: addonManager, mdbSettings: mdblist.settings,
                                 tmdb: tmdbSettings.settings,
                                 parentalGuideEnabled: playerSettings.settings.parentalGuideEnabled)
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: meta.background ?? meta.poster)
                .frame(height: 760).frame(maxWidth: .infinity, alignment: .trailing)
                .clipped()
                .overlay(heroScrim)

            VStack(alignment: .leading, spacing: 20) {
                if let logo = meta.logo {
                    RemoteImage(url: logo, contentMode: .fit, alignment: .bottomLeading)
                        .frame(maxWidth: 560, maxHeight: 150, alignment: .leading)
                } else {
                    Text(meta.name).font(.system(size: 60, weight: .heavy))
                        .foregroundStyle(.white).lineLimit(2).frame(maxWidth: 760, alignment: .leading)
                }

                if meta.isSeries, variant == .streamline {
                    Text("\(meta.seasons.count) Season\(meta.seasons.count == 1 ? "" : "s")")
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(accent)
                }

                HStack(spacing: 16) {
                    if let r = meta.imdbRating { Text("IMDb \(r)") }
                    if let g = meta.genres?.first { Text(g) }
                    if let y = meta.year { Text(y) }
                    if let rt = meta.runtimeFormatted { Text(rt) }
                }
                .font(.system(size: 22, weight: .medium)).foregroundStyle(.white.opacity(0.72))

                if let d = meta.description, !d.isEmpty {
                    Text(d).font(.system(size: 24)).foregroundStyle(.white)
                        .lineLimit(3).frame(maxWidth: 760, alignment: .leading)
                }

                HStack(spacing: 22) {
                    ThemedDetailButton(text: meta.isSeries ? "PLAY S\(viewModel.selectedSeason ?? 1) E1" : "PLAY",
                                       icon: "play.fill", filled: true, accent: accent) {
                        onPlay(meta, playVideo)
                    }
                    ThemedDetailCircle(icon: library.contains(meta) ? "checkmark" : "plus",
                                       label: library.contains(meta) ? "My List" : "My List", accent: accent) {
                        library.toggle(meta)
                    }
                    if !meta.isSeries {
                        ThemedDetailCircle(icon: watched.isWatched(meta) ? "eye.slash" : "eye",
                                           label: "Watched", accent: accent) { watched.toggleMovie(meta) }
                    }
                }
                .padding(.top, 6)
            }
            .padding(.leading, side).padding(.bottom, 56)
        }
    }

    private var heroScrim: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: stage, location: 0.0),
                .init(color: stage.opacity(0.82), location: 0.34),
                .init(color: .clear, location: 0.72)
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [stage, stage.opacity(0)], startPoint: .bottom, endPoint: .center)
        }
    }

    // MARK: Episodes

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                Text("Episodes").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                ForEach(meta.seasons, id: \.self) { s in
                    Button { viewModel.selectedSeason = s; Task { await viewModel.loadSeason(s) } } label: {
                        Text("S\(s)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(viewModel.selectedSeason == s ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(viewModel.selectedSeason == s ? accent.opacity(0.25) : .clear))
                    }
                    .buttonStyle(.huluFlat)
                }
            }
            .padding(.leading, side)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(seasonEpisodes) { ep in
                        ThemedEpisodeCard(
                            episode: ep, fallback: meta.background, accent: accent,
                            isWatched: watched.isWatched(contentID: meta.id,
                                                         season: ep.season ?? 0, episode: ep.episode)
                        ) {
                            onPlay(meta, ep)
                        }
                    }
                }
                .padding(.horizontal, side)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: More like this

    private var moreLikeThis: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Like This").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                .padding(.leading, side)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    ForEach(viewModel.moreLikeThis) { item in
                        ThemedPoster(item: item, accent: accent) { onSelectItem(item) }
                    }
                }
                .padding(.horizontal, side)
            }
            .scrollClipDisabled()
        }
    }
}

// MARK: - Pieces

private struct ThemedDetailButton: View {
    let text: String
    let icon: String
    let filled: Bool
    let accent: Color
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold))
                Text(text).font(.system(size: 26, weight: .bold))
            }
            .foregroundStyle(filled ? .black : .white)
            .padding(.horizontal, 40).padding(.vertical, 20)
            .background(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(focused ? 0.28 : 0.16)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent, lineWidth: focused ? 4 : 0))
        }
        .buttonStyle(.huluFlat)
        .focused($focused)
        .scaleEffect(focused ? 1.05 : 1)
        .animation(.easeOut(duration: 0.14), value: focused)
    }
}

private struct ThemedDetailCircle: View {
    let icon: String
    let label: String
    let accent: Color
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 24))
                if focused { Text(label).font(.system(size: 22, weight: .semibold)) }
            }
            .foregroundStyle(focused ? .black : .white)
            .frame(height: 64).padding(.horizontal, focused ? 24 : 0).frame(minWidth: 64)
            .background(focused ? AnyShapeStyle(Color.white)
                        : AnyShapeStyle(Color.white.opacity(0.14)))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(accent, lineWidth: focused ? 3 : 0))
        }
        .buttonStyle(.huluFlat)
        .focused($focused)
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}

private struct ThemedEpisodeCard: View {
    let episode: MetaVideo
    let fallback: String?
    let accent: Color
    var isWatched: Bool = false
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                RemoteImage(url: episode.thumbnail ?? fallback, maxDimension: 420)
                    .frame(width: 420, height: 236)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // Dim watched episodes and badge them with a tick.
                    .overlay {
                        if isWatched {
                            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.45))
                        }
                    }
                    .overlay(alignment: .topTrailing) { if isWatched { WatchedTickBadge() } }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: focused ? 5 : 0))
                Text("\(episode.episode ?? 0). \(episode.title ?? "Episode")")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(focused ? .white : .white.opacity(isWatched ? 0.5 : 0.7))
                    .lineLimit(1).frame(width: 420, alignment: .leading)
            }
        }
        .buttonStyle(.huluFlat)
        .focused($focused)
        .scaleEffect(focused ? 1.04 : 1)
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}

private struct ThemedPoster: View {
    let item: MetaItem
    let accent: Color
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            RemoteImage(url: item.poster ?? item.background, maxDimension: 315)
                .frame(width: 210, height: 315)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: focused ? 5 : 0))
        }
        .buttonStyle(.huluFlat)
        .focused($focused)
        .scaleEffect(focused ? 1.06 : 1)
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}
