import SwiftUI
import UIKit

extension Color {
    /// Parses a "#RRGGBB" profile color, falling back to blue.
    init(profileHex: String) {
        var s = profileHex
        if s.hasPrefix("#") { s.removeFirst() }
        self.init(hex: UInt32(s, radix: 16) ?? 0x1E88E5)
    }
}

// MARK: - Avatar

/// A profile's avatar: catalog image if it has one, otherwise a colored circle
/// with the name's initial.
struct ProfileAvatarView: View {
    @EnvironmentObject private var profiles: ProfileStore
    let profile: UserProfile
    var size: CGFloat = 140

    @State private var image: UIImage?

    private var avatarURLString: String? { profiles.avatarURL(for: profile) }

    var body: some View {
        ZStack {
            Circle().fill(Color(profileHex: profile.avatarColorHex))
            if let image {
                // Chosen avatar fully REPLACES the initial (drawn over the
                // colored circle, clipped to it).
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else if avatarURLString == nil {
                // No avatar chosen → colored initial. When an avatar IS chosen
                // but still loading, we deliberately show ONLY the circle (no
                // initial) so the "P" never flashes before the icon.
                initial
            }
        }
        .frame(width: size, height: size)
        .task(id: avatarURLString) { await loadAvatar() }
    }

    /// Cached avatar load (via the shared ImageCache) so a decoded avatar shows
    /// instantly on every re-appearance instead of re-downloading and flashing.
    private func loadAvatar() async {
        guard let urlString = avatarURLString, let url = URL(string: urlString) else {
            image = nil
            return
        }
        if let cached = ImageCache.shared.image(for: urlString) {
            image = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              !Task.isCancelled,
              let decoded = UIImage(data: data) else { return }
        ImageCache.shared.insert(decoded, for: urlString)
        image = decoded
    }

    private var initial: some View {
        Text(profile.initial)
            .font(.system(size: size * 0.42, weight: .heavy))
            .foregroundStyle(.white)
    }
}

// MARK: - "Who's watching?" gate

struct ProfileGateView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    let onSelected: () -> Void

    @State private var pinProfile: UserProfile?
    // Open with focus on the profile you last used, so the trackpad starts on a
    // sensible tile rather than an arbitrary one.
    @FocusState private var focusedProfile: Int?

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            VStack(spacing: NuvioSpacing.huge) {
                Text("Who's watching?")
                    .font(.system(size: 58, weight: .heavy))
                    .foregroundStyle(theme.palette.textPrimary)

                HStack(alignment: .top, spacing: NuvioSpacing.xl) {
                    ForEach(profiles.profiles) { profile in
                        Button { select(profile) } label: {
                            GateTile(title: profile.name, locked: profile.pinEnabled) {
                                ProfileAvatarView(profile: profile)
                            }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        .focused($focusedProfile, equals: profile.id)
                    }
                    if profiles.canAddProfile {
                        Button { addProfile() } label: {
                            GateTile(title: "Add") { DashedCircle(systemName: "plus") }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                    // Manage Profiles and Nuvio Account moved to Settings → Account.
                }
                .defaultFocus($focusedProfile, profiles.active.id)
            }
            .padding(NuvioSpacing.huge)
        }
        // This is the very first screen the app can show — there's nothing to
        // go back to, so Back is a no-op instead of falling through to the
        // system (which would otherwise exit the app).
        .onExitCommand {}
        .task { await profiles.loadAvatarCatalog() }
        .fullScreenCover(item: $pinProfile) { profile in
            PinUnlockView(
                profile: profile,
                onUnlocked: {
                    pinProfile = nil
                    profiles.setActive(profile.id)
                    onSelected()
                },
                onCancel: { pinProfile = nil }
            )
            .environmentObject(theme)
            .environmentObject(profiles)
        }
    }

    private func select(_ profile: UserProfile) {
        if profile.pinEnabled {
            pinProfile = profile
        } else {
            profiles.setActive(profile.id)
            onSelected()
        }
    }

    private func addProfile() {
        if let created = profiles.addProfile(name: "") {
            profiles.setActive(created.id)
            onSelected()
        }
    }
}

/// Avatar + caption tile with a focus ring, used across profile screens.
private struct GateTile<Content: View>: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let title: String
    var locked: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: NuvioSpacing.md) {
            ZStack(alignment: .bottomTrailing) {
                content
                    .overlay(
                        Circle().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 6)
                    )
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Circle().fill(.black.opacity(0.65)))
                }
            }
            .scaleEffect(isFocused ? 1.08 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)

            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isFocused ? theme.palette.textPrimary : theme.palette.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 160)
        }
    }
}

private struct DashedCircle: View {
    @EnvironmentObject private var theme: ThemeManager
    let systemName: String
    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 3, dash: [10]))
            .background(Circle().fill(.white.opacity(0.06)))
            .frame(width: 140, height: 140)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(theme.palette.textSecondary)
            )
    }
}

// MARK: - PIN entry

/// Reusable 4-digit PIN pad. `onSubmit` returns an error string to display, or
/// nil on success.
struct PinEntryView: View {
    @EnvironmentObject private var theme: ThemeManager
    let title: String
    var subtitle: String?
    let onSubmit: (String) async -> String?
    let onCancel: () -> Void

    @State private var digits = ""
    @State private var error: String?
    @State private var busy = false

    private let pinLength = 4

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            VStack(spacing: NuvioSpacing.xl) {
                Text(title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(theme.palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 24))
                        .foregroundStyle(theme.palette.textSecondary)
                }

                HStack(spacing: NuvioSpacing.lg) {
                    ForEach(0..<pinLength, id: \.self) { i in
                        Circle()
                            .fill(i < digits.count ? theme.palette.secondary : .white.opacity(0.2))
                            .frame(width: 28, height: 28)
                    }
                }
                .padding(.vertical, NuvioSpacing.md)

                if let error {
                    Text(error)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(NuvioPrimitives.error)
                }

                VStack(spacing: NuvioSpacing.md) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: NuvioSpacing.md) {
                            ForEach(1...3, id: \.self) { col in
                                digitButton("\(row * 3 + col)")
                            }
                        }
                    }
                    HStack(spacing: NuvioSpacing.md) {
                        actionButton(systemName: "delete.left") { if !digits.isEmpty { digits.removeLast() } }
                        digitButton("0")
                        actionButton(systemName: "xmark") { onCancel() }
                    }
                }
                .disabled(busy)
            }
            .padding(NuvioSpacing.huge)
        }
        // Back cancels (same as the on-screen xmark) instead of falling
        // through to the system, which would otherwise exit the app.
        .onExitCommand { onCancel() }
    }

    private func digitButton(_ digit: String) -> some View {
        Button { append(digit) } label: {
            Text(digit)
                .font(.system(size: 40, weight: .semibold))
        }
        .buttonStyle(PinKeyStyle())
    }

    private func actionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 34, weight: .semibold))
        }
        .buttonStyle(PinKeyStyle())
    }

    private func append(_ digit: String) {
        guard digits.count < pinLength, !busy else { return }
        error = nil
        digits += digit
        if digits.count == pinLength { submit() }
    }

    private func submit() {
        busy = true
        let entered = digits
        Task {
            let result = await onSubmit(entered)
            if let result {
                error = result
                digits = ""
            }
            busy = false
        }
    }
}

private struct PinKeyStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 90, height: 90)
            .background(Circle().fill(isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.12)))
            .foregroundStyle(isFocused ? .black : .white)
            .scaleEffect(isFocused ? 1.12 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
    }
}

/// PIN prompt shown when selecting a locked profile.
struct PinUnlockView: View {
    @EnvironmentObject private var profiles: ProfileStore
    let profile: UserProfile
    let onUnlocked: () -> Void
    let onCancel: () -> Void

    var body: some View {
        PinEntryView(
            title: "Enter PIN",
            subtitle: profile.name,
            onSubmit: { pin in
                let outcome = await profiles.verifyPin(id: profile.id, pin: pin)
                if outcome.unlocked {
                    onUnlocked()
                    return nil
                }
                if outcome.retryAfterSeconds > 0 {
                    return "Too many attempts. Try again in \(outcome.retryAfterSeconds)s."
                }
                return outcome.message ?? "Incorrect PIN"
            },
            onCancel: onCancel
        )
    }
}

// MARK: - Management

struct ProfileManageView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    let onDone: () -> Void

    @State private var editing: UserProfile?

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: NuvioSpacing.xl) {
                HStack {
                    Text("Manage Profiles")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(theme.palette.textPrimary)
                    Spacer()
                    Button("Done") { onDone() }
                }

                HStack(alignment: .top, spacing: NuvioSpacing.xl) {
                    ForEach(profiles.profiles) { profile in
                        Button { editing = profile } label: {
                            GateTile(title: profile.name, locked: profile.pinEnabled) {
                                ProfileAvatarView(profile: profile, size: 120)
                            }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                    if profiles.canAddProfile {
                        Button { profiles.addProfile(name: "") } label: {
                            GateTile(title: "Add") { DashedCircle(systemName: "plus") }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                }
                Spacer()
            }
            .padding(NuvioSpacing.huge)
        }
        .onExitCommand { onDone() }
        .task { await profiles.loadAvatarCatalog() }
        .fullScreenCover(item: $editing) { profile in
            ProfileEditView(profile: profile) { editing = nil }
                .environmentObject(theme)
                .environmentObject(profiles)
        }
    }
}

struct ProfileEditView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    let profile: UserProfile
    let onDone: () -> Void

    @State private var name = ""
    @State private var showSetPin = false
    @State private var pinError: String?
    @State private var confirmingDelete = false

    private var current: UserProfile {
        profiles.profiles.first { $0.id == profile.id } ?? profile
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: NuvioSpacing.md), count: 8)

    var body: some View {
        ZStack {
            theme.palette.background.ignoresSafeArea()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: NuvioSpacing.xl) {
                    HStack {
                        Text("Edit Profile").font(.system(size: 40, weight: .bold))
                            .foregroundStyle(theme.palette.textPrimary)
                        Spacer()
                        Button("Done") { commitName(); onDone() }
                    }

                    HStack(spacing: NuvioSpacing.lg) {
                        ProfileAvatarView(profile: current, size: 120)
                        TextField("Name", text: $name)
                            .font(.system(size: 28))
                            .padding(.horizontal, NuvioSpacing.lg)
                            .padding(.vertical, NuvioSpacing.md)
                            .background(theme.palette.field, in: RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous))
                            .frame(maxWidth: 560)
                            .onSubmit { commitName() }
                    }

                    sectionLabel("Color")
                    HStack(spacing: NuvioSpacing.md) {
                        ForEach(ProfileStore.avatarColors, id: \.self) { hex in
                            Button { profiles.setColor(id: profile.id, hex: hex) } label: {
                                Circle().fill(Color(profileHex: hex)).frame(width: 52, height: 52)
                                    .overlay(Circle().strokeBorder(current.avatarColorHex == hex ? .white : .clear, lineWidth: 3))
                            }
                            .buttonStyle(PlainCardButtonStyle())
                        }
                    }

                    if profiles.avatarCatalog.isEmpty && !profiles.accountAvailable {
                        sectionLabel("Avatar")
                        Text("Sign in to Nuvio to choose an avatar image. Colored initials are always available above.")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.palette.textSecondary)
                    }

                    if !profiles.avatarCatalog.isEmpty {
                        sectionLabel("Avatar")
                        LazyVGrid(columns: columns, spacing: NuvioSpacing.md) {
                            Button { profiles.setAvatar(id: profile.id, avatarID: nil) } label: {
                                Circle().fill(Color(profileHex: current.avatarColorHex))
                                    .overlay(Text(current.initial).font(.system(size: 30, weight: .heavy)).foregroundStyle(.white))
                                    .frame(width: 96, height: 96)
                            }
                            .buttonStyle(PlainCardButtonStyle())
                            ForEach(profiles.avatarCatalog) { item in
                                Button { profiles.setAvatar(id: profile.id, avatarID: item.id) } label: {
                                    AsyncImage(url: URL(string: item.imageURL)) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: {
                                        Circle().fill(.white.opacity(0.1))
                                    }
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(current.avatarID == item.id ? theme.palette.secondary : .clear, lineWidth: 4))
                                }
                                .buttonStyle(PlainCardButtonStyle())
                            }
                        }
                    }

                    sectionLabel("PIN Lock")
                    if let pinError {
                        Text(pinError).font(.system(size: 20)).foregroundStyle(NuvioPrimitives.error)
                    }
                    if profiles.accountAvailable {
                        HStack(spacing: NuvioSpacing.lg) {
                            if current.pinEnabled {
                                Button(role: .destructive) {
                                    Task { _ = await profiles.clearPin(id: profile.id, currentPin: nil) }
                                } label: { Label("Remove PIN", systemImage: "lock.open") }
                            } else {
                                Button { showSetPin = true } label: { Label("Set PIN", systemImage: "lock") }
                            }
                        }
                    } else {
                        Text(current.pinEnabled
                             ? "This profile is PIN-locked. Sign in to Nuvio to change or remove the PIN."
                             : "Sign in to Nuvio to set a PIN for this profile.")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.palette.textSecondary)
                    }

                    if profile.id != 1 {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete Profile", systemImage: "trash").font(.system(size: 24, weight: .semibold))
                        }
                        .padding(.top, NuvioSpacing.lg)
                    }
                }
                .padding(NuvioSpacing.huge)
            }
            .scrollClipDisabled()
        }
        .onAppear { name = current.name }
        // Same as pressing Done: commit the pending name edit, then dismiss.
        .onExitCommand { commitName(); onDone() }
        .fullScreenCover(isPresented: $showSetPin) {
            PinEntryView(
                title: "Set a 4-digit PIN",
                subtitle: profile.name,
                onSubmit: { pin in
                    let outcome = await profiles.setPin(id: profile.id, pin: pin, currentPin: nil)
                    switch outcome {
                    case .success:
                        showSetPin = false
                        return nil
                    case .currentPinRequired:
                        return "This profile already has a PIN."
                    case .failure(let message):
                        return message
                    }
                },
                onCancel: { showSetPin = false }
            )
            .environmentObject(theme)
            .environmentObject(profiles)
        }
        // Deleting also pushes to the Nuvio account (ProfileStore.delete →
        // onLocalChange → profile sync).
        .confirmationDialog(
            "Delete “\(current.name)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                profiles.delete(id: profile.id)
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the profile and its settings from this device and your Nuvio account. This can't be undone.")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(theme.palette.textTertiary)
            .kerning(2)
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { profiles.rename(id: profile.id, to: trimmed) }
    }
}
