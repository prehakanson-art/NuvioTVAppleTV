import SwiftUI

/// Ready-made collections. Two kinds: streaming-service collections (Netflix,
/// Apple TV+, Hulu…) that pull that service's movies & shows via TMDB, and
/// type bundles built from the catalogs you already have installed. Reached
/// from Add-ons → Community Collections.
struct CommunityCollectionsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var collections: CollectionsStore
    let onDone: () -> Void

    @FocusState private var focusedID: String?
    @State private var addedIDs: Set<String> = []
    @State private var providerLogos: [String: String] = [:]

    // MARK: Streaming services (TMDB watch-provider ids)
    struct Service: Identifiable {
        let id: String
        let name: String
        let providerID: String
    }
    static let services: [Service] = [
        .init(id: "netflix",  name: "Netflix",      providerID: "8"),
        .init(id: "appletv",  name: "Apple TV+",    providerID: "350"),
        .init(id: "disney",   name: "Disney+",      providerID: "337"),
        .init(id: "hulu",     name: "Hulu",         providerID: "15"),
        .init(id: "max",      name: "Max",          providerID: "1899"),
        .init(id: "paramount",name: "Paramount+",   providerID: "531"),
        .init(id: "prime",    name: "Prime Video",  providerID: "9"),
        .init(id: "peacock",  name: "Peacock",      providerID: "386"),
    ]

    // MARK: Type bundles (from installed catalogs)
    struct Preset: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let emoji: String
        let types: Set<String>
    }
    static let presets: [Preset] = [
        .init(id: "movies", title: "Movies Hub", subtitle: "Every installed movie catalog in one row",
              icon: "film.fill", emoji: "🎬", types: ["movie"]),
        .init(id: "series", title: "Series Hub", subtitle: "All your installed series catalogs together",
              icon: "tv.fill", emoji: "📺", types: ["series"]),
        .init(id: "anime", title: "Anime Hub", subtitle: "Anime catalogs from your add-ons",
              icon: "sparkles", emoji: "🌸", types: ["anime"]),
        .init(id: "livetv", title: "Live TV", subtitle: "Group your IPTV / Live TV catalogs",
              icon: "antenna.radiowaves.left.and.right", emoji: "📡", types: ["tv"]),
    ]

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            DetailScaffold(
                title: "Community Collections",
                subtitle: "Streaming-service rows and bundles built from your catalogs"
            ) {
                LazyVStack(alignment: .leading, spacing: NuvioSpacing.xl) {
                    servicesSection
                    catalogSection
                    Text("Streaming-service collections use TMDB to list what's on each service (needs the TMDB integration, which is on by default). Type bundles group the catalog add-ons you already have installed.")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.palette.textTertiary)
                        .padding(.horizontal, 8)
                }
            }
        }
        .onExitCommand { onDone() }
        .task { providerLogos = await TMDBService.watchProviderLogos() }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if focusedID == nil { focusedID = Self.services.first?.id }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            sectionHeader("Streaming Services")
            ForEach(Self.services) { service in
                let added = addedIDs.contains(service.id) || collectionExists(service.name)
                Button {
                    if !added { addService(service) }
                } label: {
                    CollectionPresetRow(
                        title: service.name,
                        subtitle: "Movies & shows on \(service.name)",
                        logoURL: providerLogos[service.providerID],
                        fallbackIcon: "play.tv.fill",
                        added: added, disabled: false
                    )
                }
                .buttonStyle(PlainCardButtonStyle())
                .focused($focusedID, equals: service.id)
            }
        }
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: NuvioSpacing.sm) {
            sectionHeader("From Your Catalogs")
            ForEach(Self.presets) { preset in
                let count = sources(for: preset).count
                let added = addedIDs.contains(preset.id) || collectionExists(preset.title)
                Button {
                    if count > 0 && !added { addPreset(preset) }
                } label: {
                    CollectionPresetRow(
                        title: preset.title,
                        subtitle: count == 0
                            ? "\(preset.subtitle) — no matching catalogs installed"
                            : "\(preset.subtitle) · \(count) catalog\(count == 1 ? "" : "s")",
                        logoURL: nil, fallbackIcon: preset.icon,
                        added: added, disabled: count == 0
                    )
                }
                .buttonStyle(PlainCardButtonStyle())
                .focused($focusedID, equals: preset.id)
            }
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 18, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(theme.palette.secondary)
            .padding(.horizontal, 8)
    }

    // MARK: Actions

    private func tmdbSource(providerID: String, media: String) -> CollectionSourceDTO {
        var s = CollectionSourceDTO(addonId: "", type: "", catalogId: "")
        s.provider = "tmdb"
        s.tmdbSourceType = "DISCOVER"
        s.mediaType = media
        var f = TmdbFiltersDTO()
        f.withWatchProviders = providerID
        f.watchRegion = "US"
        s.filters = f
        return s
    }

    private func addService(_ service: Service) {
        let logo = providerLogos[service.providerID]
        var folder = NuvioCollectionFolder(
            id: UUID().uuidString, title: service.name,
            sources: [tmdbSource(providerID: service.providerID, media: "movie"),
                      tmdbSource(providerID: service.providerID, media: "tv")]
        )
        folder.tileShape = "SQUARE"    // editable to Landscape in the folder editor
        folder.coverImageUrl = logo    // HQ (original-size) service logo
        folder.hideTitle = true
        var collection = NuvioCollection(id: UUID().uuidString, title: service.name, folders: [folder])
        // Same HQ picture as the collection's background when opened.
        collection.backdropImageUrl = logo
        collections.add(collection)
        addedIDs.insert(service.id)
    }

    private func sources(for preset: Preset) -> [CollectionSourceDTO] {
        var out: [CollectionSourceDTO] = []
        for addon in addonManager.catalogAddons {
            for catalog in (addon.manifest.catalogs ?? [])
            where preset.types.contains(catalog.type) && !catalog.requiresExtra {
                out.append(CollectionSourceDTO(addonId: addon.manifest.id, type: catalog.type, catalogId: catalog.id))
            }
        }
        return out
    }

    private func addPreset(_ preset: Preset) {
        let srcs = sources(for: preset)
        guard !srcs.isEmpty else { return }
        var folder = NuvioCollectionFolder(id: UUID().uuidString, title: preset.title, sources: srcs)
        folder.coverEmoji = preset.emoji
        let collection = NuvioCollection(id: UUID().uuidString, title: preset.title, folders: [folder])
        collections.add(collection)
        addedIDs.insert(preset.id)
    }

    private func collectionExists(_ title: String) -> Bool {
        collections.collections.contains { $0.title == title }
    }
}

private struct CollectionPresetRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    let subtitle: String
    let logoURL: String?
    let fallbackIcon: String
    let added: Bool
    let disabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: NuvioSpacing.md) {
            tile
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 1000, alignment: .leading)
            }
            Spacer(minLength: NuvioSpacing.lg)
            accessory.padding(.top, 2)
        }
        .padding(.horizontal, NuvioSpacing.md)
        .padding(.vertical, NuvioSpacing.md)
        .frame(minHeight: 76)
        .frame(maxWidth: .infinity)
        .background(SettingsRowBackground(isFocused: isFocused))
    }

    @ViewBuilder
    private var tile: some View {
        if let logoURL {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .frame(width: 48, height: 48)
                .overlay(
                    RemoteImage(url: logoURL, contentMode: .fit)
                        .padding(5)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
        } else {
            SettingsIconTile(symbol: fallbackIcon)
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if added {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Added")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(NuvioPrimitives.success)
        } else if disabled {
            Text("Needs catalogs")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.palette.textTertiary)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Add")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isFocused ? theme.palette.onSecondary : theme.palette.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(isFocused ? theme.palette.secondary : theme.palette.secondary.opacity(0.16)))
        }
    }
}
