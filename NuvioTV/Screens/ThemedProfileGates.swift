import SwiftUI

// Alternate "Who's watching?" profile screens, selectable via Settings → Themes →
// Profile Screen. Faithful ports of MaxTV's and HuluTV's profile gates, but using
// Orivio's real profiles + `ProfileAvatarView` avatars, and the real select / PIN
// / add flow. Orivio keeps the default `ProfileGateView`.
//   • Marquee   = MaxTV: centered row of circular avatars, white focus ring.
//   • Streamline = HuluTV: left-aligned vertical list (avatar + name), accent
//     rounded-outline focus.
struct ThemedProfileGate: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    let variant: ThemeVariant
    let onSelected: () -> Void

    @State private var pinProfile: UserProfile?
    @FocusState private var focusedProfile: Int?

    var body: some View {
        ZStack {
            if let locked = pinProfile {
                background
                PinEntryView(
                    title: "Enter PIN", subtitle: locked.name,
                    onSubmit: { pin in
                        let outcome = await profiles.verifyPin(id: locked.id, pin: pin)
                        if outcome.unlocked {
                            pinProfile = nil; profiles.setActive(locked.id); onSelected(); return nil
                        }
                        if outcome.retryAfterSeconds > 0 {
                            return "Too many attempts. Try again in \(outcome.retryAfterSeconds)s."
                        }
                        return outcome.message ?? "Incorrect PIN"
                    },
                    onCancel: { pinProfile = nil }
                )
            } else if variant == .streamline {
                streamlineGate
            } else {
                marqueeGate
            }
        }
        .onExitCommand {}
        .task { await profiles.loadAvatarCatalog() }
    }

    // Use the CURRENT theme's stage so the profile screen matches the rest of
    // the app (home/detail/etc.), regardless of which profile design is chosen.
    private var background: some View {
        theme.palette.background.ignoresSafeArea()
    }

    // MARK: Marquee (MaxTV) — centered circular avatars

    private var marqueeGate: some View {
        ZStack {
            background
            VStack(spacing: 90) {
                Text("Who's Watching?")
                    .font(.system(size: 56, weight: .bold)).foregroundStyle(.white)

                HStack(alignment: .top, spacing: 60) {
                    ForEach(profiles.profiles) { p in
                        Button { select(p) } label: {
                            MarqueeAvatarTile(profile: p)
                        }
                        .buttonStyle(.huluFlat)
                        .focused($focusedProfile, equals: p.id)
                    }
                    if profiles.canAddProfile {
                        Button { addProfile() } label: { MarqueeAddTile() }
                            .buttonStyle(.huluFlat)
                    }
                }
                .defaultFocus($focusedProfile, profiles.active.id)
            }
        }
    }

    // MARK: Streamline (HuluTV) — left-aligned vertical list

    private var streamlineGate: some View {
        ZStack(alignment: .topLeading) {
            background
            HuluWordmark(size: 44).padding(.trailing, 60).padding(.top, 40)
                .frame(maxWidth: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 22) {
                Text("Who's Watching?")
                    .font(.system(size: 52, weight: .bold)).foregroundStyle(.white)
                    .padding(.bottom, 24)

                ForEach(profiles.profiles) { p in
                    Button { select(p) } label: { StreamlineProfileRow(profile: p) }
                        .buttonStyle(.huluFlat)
                        .focused($focusedProfile, equals: p.id)
                }
                if profiles.canAddProfile {
                    Button { addProfile() } label: { StreamlineNewRow() }
                        .buttonStyle(.huluFlat)
                }
            }
            .padding(.leading, 90).padding(.top, 200)
            .defaultFocus($focusedProfile, profiles.active.id)
        }
    }

    // MARK: Actions

    private func select(_ profile: UserProfile) {
        if profile.pinEnabled { pinProfile = profile }
        else { profiles.setActive(profile.id); onSelected() }
    }
    private func addProfile() {
        if let created = profiles.addProfile(name: "") { profiles.setActive(created.id); onSelected() }
    }
}

// MARK: - Marquee tiles (MaxTV)

private struct MarqueeAvatarTile: View {
    @Environment(\.isFocused) private var isFocused
    let profile: UserProfile
    var body: some View {
        VStack(spacing: 22) {
            ProfileAvatarView(profile: profile, size: 200)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: isFocused ? 6 : 0))
                .overlay(alignment: .bottomTrailing) {
                    if profile.pinEnabled {
                        Image(systemName: "lock.fill").font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white).padding(12)
                            .background(Circle().fill(.black.opacity(0.65)))
                    }
                }
            Text(profile.name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(isFocused ? .white : .white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: 220)
        .scaleEffect(isFocused ? 1.08 : 1)
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

private struct MarqueeAddTile: View {
    @Environment(\.isFocused) private var isFocused
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "plus")
                .font(.system(size: 70, weight: .regular)).foregroundStyle(.white.opacity(0.6))
                .frame(width: 200, height: 200)
                .background(Circle().fill(Color(hex: 0x1A1A1D)))
                .overlay(Circle().stroke(.white, lineWidth: isFocused ? 6 : 0))
            Text("Add").font(.system(size: 30, weight: .bold))
                .foregroundStyle(isFocused ? .white : .white.opacity(0.6))
        }
        .frame(width: 220)
        .scaleEffect(isFocused ? 1.08 : 1)
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

// MARK: - Streamline rows (HuluTV) — avatar + name with accent outline

private struct StreamlineProfileRow: View {
    @Environment(\.isFocused) private var isFocused
    let profile: UserProfile
    var body: some View {
        HStack(spacing: 26) {
            ProfileAvatarView(profile: profile, size: 72)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    if profile.pinEnabled {
                        Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white).padding(6)
                            .background(Circle().fill(.black.opacity(0.65)))
                    }
                }
            Text(profile.name).font(.system(size: 44, weight: .regular)).foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .huluFocusRing(isFocused, cornerRadius: 14, lineWidth: 4)
    }
}

private struct StreamlineNewRow: View {
    @Environment(\.isFocused) private var isFocused
    var body: some View {
        HStack(spacing: 26) {
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .regular)).foregroundStyle(.white.opacity(0.7))
                .frame(width: 72, height: 72)
                .background(Circle().strokeBorder(.white.opacity(0.3),
                            style: StrokeStyle(lineWidth: 3, dash: [7, 7])))
            Text("New Profile").font(.system(size: 44, weight: .regular)).foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .huluFocusRing(isFocused, cornerRadius: 14, lineWidth: 4)
    }
}
