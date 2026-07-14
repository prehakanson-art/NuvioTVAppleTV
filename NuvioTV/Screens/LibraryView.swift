import SwiftUI

private enum LibraryTab: String, CaseIterable { case saved = "Saved", cloud = "Cloud" }

struct LibraryView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var posterLayout: HomeCatalogSettingsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progressStore: ProgressStore

    let onSelect: (MetaItem) -> Void
    /// Opens the full Cloud Library screen (debrid cloud files).
    var onOpenCloud: () -> Void = {}

    @State private var tab: LibraryTab = .saved
    @State private var typeFilter = "All"          // All / Movies / Series
    @State private var sort = "Added"              // Added / Name / Recently Watched

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: posterLayout.posterSize.posterWidth, maximum: posterLayout.posterSize.posterWidth), spacing: NuvioSpacing.lg, alignment: .top)] }

    private var filtered: [SavedLibraryItem] {
        var items = library.sorted
        switch typeFilter {
        case "Movies": items = items.filter { $0.metaItem.type == "movie" }
        case "Series": items = items.filter { $0.metaItem.isSeries }
        default: break
        }
        switch sort {
        case "Name":
            items = items.sorted { $0.metaItem.name.lowercased() < $1.metaItem.name.lowercased() }
        case "Recently Watched":
            // Latest Continue Watching activity per title; unwatched titles
            // keep their added order at the bottom.
            let lastWatched = Dictionary(
                progressStore.allForSync().map { ($0.metaID, $0.updatedAt) },
                uniquingKeysWith: max
            )
            items = items.sorted {
                let a = lastWatched[$0.id] ?? .distantPast
                let b = lastWatched[$1.id] ?? .distantPast
                return a > b
            }
        default:
            break
        }
        return items
    }

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: NuvioSpacing.lg) {
                    header
                    tabs
                    filters
                    if tab == .cloud {
                        VStack(spacing: NuvioSpacing.lg) {
                            NuvioEmptyState(icon: "externaldrive.connected.to.line.below",
                                            title: "Debrid cloud files",
                                            message: "Browse and play the files already in your Real-Debrid / Premiumize / TorBox / AllDebrid cloud.")
                            Button(action: onOpenCloud) {
                                SeeAllLabel(text: "Open Cloud Library")
                            }
                            .buttonStyle(PlainCardButtonStyle())
                        }
                        .frame(maxWidth: .infinity, minHeight: 460)
                    } else if filtered.isEmpty {
                        NuvioEmptyState(icon: "bookmark",
                                        title: typeFilter == "All" ? "Nothing saved yet" : "No \(typeFilter.lowercased()) yet",
                                        message: "Start saving your favorites to see them here")
                            .frame(height: 460)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: NuvioSpacing.xl) {
                            ForEach(filtered) { item in
                                Button { onSelect(item.metaItem) } label: {
                                    PosterCard(item: item.metaItem)
                                }
                                .buttonStyle(PlainCardButtonStyle())
                            }
                        }
                        .padding(.horizontal, NuvioSpacing.huge)
                        .padding(.bottom, NuvioSpacing.huge)
                    }
                }
                .padding(.top, NuvioSpacing.xl)
            }
            .scrollClipDisabled()
        }
    }

    private var header: some View {
        HStack {
            Text("Library")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(theme.palette.textPrimary)
            Spacer()
            Text("NUVIO")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(theme.palette.textTertiary)
                .tracking(2)
        }
        .padding(.horizontal, NuvioSpacing.huge)
    }

    private var tabs: some View {
        HStack(spacing: NuvioSpacing.md) {
            ForEach(LibraryTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    LibrarySegment(title: t.rawValue, selected: tab == t)
                }
                .buttonStyle(PlainCardButtonStyle())
            }
        }
        .padding(.horizontal, NuvioSpacing.huge)
    }

    private var filters: some View {
        HStack(spacing: NuvioSpacing.lg) {
            NuvioDropdown(
                title: "Type",
                selection: typeFilter,
                options: [NuvioDropdownOption("All"), NuvioDropdownOption("Movies"), NuvioDropdownOption("Series")],
                triggerWidth: 460
            ) { typeFilter = $0 }
            NuvioDropdown(
                title: "Sort",
                selection: sort,
                options: [
                    NuvioDropdownOption("Added"),
                    NuvioDropdownOption("Name"),
                    NuvioDropdownOption("Recently Watched")
                ],
                triggerWidth: 460
            ) { sort = $0 }
        }
        .padding(.horizontal, NuvioSpacing.huge)
    }
}

/// A Saved/Cloud style tab pill.
private struct LibrarySegment: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(selected ? theme.palette.onSecondary : theme.palette.textSecondary)
            .padding(.horizontal, NuvioSpacing.lg)
            .padding(.vertical, NuvioSpacing.sm)
            .background(
                Capsule().fill(selected ? theme.palette.secondary
                               : (isFocused ? theme.palette.focusBackground : Color.white.opacity(0.08)))
            )
            .overlay(Capsule().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3))
            .scaleEffect(isFocused ? 1.04 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
    }
}

