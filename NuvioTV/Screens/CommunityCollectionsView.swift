import SwiftUI

/// Ready-made "collections" — one-tap groupings that bundle the catalogs you
/// already have installed (by type) into a single Home collection row. Reached
/// from Add-ons → Community Collections, mirroring Community Catalogs.
struct CommunityCollectionsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var collections: CollectionsStore
    let onDone: () -> Void

    @FocusState private var focusedID: String?
    @State private var addedIDs: Set<String> = []

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
                subtitle: "Ready-made collections built from the catalogs you have installed"
            ) {
                LazyVStack(alignment: .leading, spacing: NuvioSpacing.sm) {
                    ForEach(Self.presets) { preset in
                        let count = sources(for: preset).count
                        let added = addedIDs.contains(preset.id) || collectionExists(preset)
                        Button {
                            if count > 0 && !added { add(preset) }
                        } label: {
                            CommunityCollectionRow(preset: preset, catalogCount: count, added: added)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        .focused($focusedID, equals: preset.id)
                    }

                    Text("Collections group several catalogs into a single Home row. Install more catalog add-ons from Community Catalogs to fill these out.")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.palette.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.top, NuvioSpacing.md)
                }
            }
        }
        .onExitCommand { onDone() }
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if focusedID == nil { focusedID = Self.presets.first?.id }
        }
    }

    private func sources(for preset: Preset) -> [CollectionSourceDTO] {
        var out: [CollectionSourceDTO] = []
        for addon in addonManager.catalogAddons {
            for catalog in (addon.manifest.catalogs ?? [])
            where preset.types.contains(catalog.type) && !catalog.requiresExtra {
                out.append(CollectionSourceDTO(
                    addonId: addon.manifest.id, type: catalog.type, catalogId: catalog.id
                ))
            }
        }
        return out
    }

    private func collectionExists(_ preset: Preset) -> Bool {
        collections.collections.contains { $0.title == preset.title }
    }

    private func add(_ preset: Preset) {
        let srcs = sources(for: preset)
        guard !srcs.isEmpty else { return }
        var folder = NuvioCollectionFolder(id: UUID().uuidString, title: preset.title, sources: srcs)
        folder.coverEmoji = preset.emoji
        let collection = NuvioCollection(id: UUID().uuidString, title: preset.title, folders: [folder])
        collections.add(collection)
        addedIDs.insert(preset.id)
    }
}

private struct CommunityCollectionRow: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let preset: CommunityCollectionsView.Preset
    let catalogCount: Int
    let added: Bool

    var body: some View {
        HStack(alignment: .top, spacing: NuvioSpacing.md) {
            SettingsIconTile(symbol: preset.icon)
            VStack(alignment: .leading, spacing: 5) {
                Text(preset.title)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(catalogCount == 0
                     ? "\(preset.subtitle) — no matching catalogs installed yet"
                     : "\(preset.subtitle) · \(catalogCount) catalog\(catalogCount == 1 ? "" : "s")")
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
    private var accessory: some View {
        if added {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Added")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(NuvioPrimitives.success)
        } else if catalogCount == 0 {
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
