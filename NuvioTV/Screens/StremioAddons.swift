import SwiftUI

// Stremio's Addons — reconstructed from the IPA's AddonsBoardVC: the list of
// installed addons (logo, name, version, description) with an enable toggle
// and Uninstall. Grouped like Stremio's "Installed Addons".

struct StremioAddonsView: View {
    @EnvironmentObject private var addonManager: AddonManager
    var onBackAtRoot: () -> Void = {}

    private var installed: [InstalledAddon] { addonManager.addons }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Addons")
                    .font(StremioFont.bold(48))
                    .foregroundStyle(StremioSurfaces.textPrimary)
                    .padding(.top, 40)
                    .padding(.bottom, 4)

                Text("INSTALLED ADDONS")
                    .font(StremioFont.bold(20))
                    .tracking(1.2)
                    .foregroundStyle(StremioSurfaces.accentBright)

                if installed.isEmpty {
                    StremioEmptyState(icon: "square.stack", title: "No addons installed",
                                      message: "Install addons to add catalogs and streams.")
                } else {
                    VStack(spacing: 14) {
                        ForEach(installed) { addon in
                            StremioAddonRow(
                                addon: addon,
                                enabled: addon.enabled,
                                onToggle: { addonManager.setEnabled(addon, !addon.enabled) },
                                onRemove: { addonManager.remove(addon) }
                            )
                        }
                    }
                    .focusSection()
                }
            }
            .frame(maxWidth: 1400, alignment: .leading)
            .padding(.leading, 60)
            .padding(.trailing, 70)
            .padding(.bottom, 90)
        }
        .scrollClipDisabled()
        .background(StremioSurfaces.background.ignoresSafeArea())
        .onExitCommand(perform: onBackAtRoot)
    }
}

private struct StremioAddonRow: View {
    @Environment(\.isFocused) private var isFocused
    let addon: InstalledAddon
    let enabled: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 22) {
                // Addon logo (or a placeholder diamond).
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(StremioSurfaces.field)
                        .frame(width: 78, height: 78)
                    if let logo = addon.manifest.logo {
                        RemoteImage(url: logo, contentMode: .fit)
                            .frame(width: 54, height: 54)
                    } else {
                        OrivioMark().frame(width: 42, height: 42)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(addon.manifest.name)
                            .font(StremioFont.bold(26))
                            .foregroundStyle(isFocused ? .white : StremioSurfaces.textPrimary)
                            .lineLimit(1)
                        if let v = addon.manifest.version {
                            Text("v\(v)")
                                .font(StremioFont.regular(19))
                                .foregroundStyle(isFocused ? .white.opacity(0.8) : StremioSurfaces.textTertiary)
                        }
                    }
                    if let d = addon.manifest.description {
                        Text(d)
                            .font(StremioFont.regular(20))
                            .foregroundStyle(isFocused ? .white.opacity(0.85) : StremioSurfaces.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 12)

                // Enabled state chip.
                Text(enabled ? "ON" : "OFF")
                    .font(StremioFont.bold(19))
                    .tracking(1)
                    .foregroundStyle(enabled ? .white : StremioSurfaces.textTertiary)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(
                        Capsule().fill(enabled ? StremioSurfaces.green.opacity(isFocused ? 1 : 0.85)
                                       : StremioSurfaces.field)
                    )
            }
            .padding(.horizontal, 24)
            .frame(height: 116)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? StremioSurfaces.accent : StremioSurfaces.card)
            )
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 16, y: 6)
            .scaleEffect(isFocused ? 1.01 : 1)
            .animation(StremioFocus.entry, value: isFocused)
        }
        .buttonStyle(PlainCardButtonStyle())
        .contextMenu {
            Button(enabled ? "Disable" : "Enable", action: onToggle)
            Button("Uninstall", role: .destructive, action: onRemove)
        }
    }
}
