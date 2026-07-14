import SwiftUI

/// Settings → Playback: post-play / auto-next controls, mirroring the Android
/// autoplay settings section (next episode, still-watching gate, threshold
/// mode/value, countdown timeout, binge-group preference). Every row here is
/// wired to `PlayerSettingsStore` and actually changes player behavior.
struct PlaybackSettingsDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var store: PlayerSettingsStore

    private var s: Binding<PlayerSettings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    var body: some View {
        DetailScaffold(title: SettingsCategory.playback.title, subtitle: SettingsCategory.playback.subtitle) {
            SettingsGroupCard(title: "Auto-play", subtitle: "What happens when an episode finishes") {
                autoPlayControls
            }
            SettingsGroupCard(title: "Seeking", subtitle: "How far a single skip jumps") {
                NuvioDropdown(
                    title: "Skip amount",
                    subtitle: "Each left/right press; rapid presses add up, holding accelerates",
                    icon: "goforward",
                    selection: String(store.settings.skipSeconds),
                    options: PlayerSettings.skipValues.map { NuvioDropdownOption(String($0), "\($0) seconds") }
                ) { store.settings.skipSeconds = Int($0) ?? 10 }

                NuvioDropdown(
                    title: "Scrubber jump",
                    subtitle: "Left/right press while scrubbing with the trackpad",
                    icon: "forward.frame.fill",
                    selection: String(store.settings.scrubJumpSeconds),
                    options: PlayerSettings.scrubJumpValues.map {
                        NuvioDropdownOption(String($0), $0 < 60 ? "\($0) seconds" : "\($0 / 60) minute\($0 >= 120 ? "s" : "")")
                    }
                ) { store.settings.scrubJumpSeconds = Int($0) ?? 60 }

                PlaybackToggleRow(
                    icon: "ladybug.fill",
                    title: "Show input debug",
                    subtitle: "Overlay the last trackpad/remote event in the player (for tuning gestures on a real Apple TV)",
                    isOn: s.showInputDebug
                )
            }

            SettingsGroupCard(title: "Sources", subtitle: "Which links the source lists show") {
                PlaybackToggleRow(
                    icon: "line.3.horizontal.decrease.circle.fill",
                    title: "Link filters",
                    subtitle: "Smart-rank links: Top Picks (best link per resolution across all addons) up top, then each addon by resolution — scored by cached status, release quality (REMUX > Blu-ray > WEB-DL), codec, HDR/DV, audio, seeders and bitrate. Off = show links exactly as each addon returns them (cached still first), up to \(PlayerSettings.unfilteredPerAddonCap) per addon",
                    isOn: s.sourceFiltersEnabled
                )

                if store.settings.sourceFiltersEnabled {
                    NuvioDropdown(
                        title: "Links per resolution",
                        subtitle: "Best-scored links kept in each of 2160p / 1080p / 720p / 480p per addon",
                        icon: "square.stack.3d.up.fill",
                        selection: String(store.settings.sourcesPerSizeTier),
                        options: PlayerSettings.sourcesPerTierValues.filter { $0 > 0 }.map {
                            NuvioDropdownOption(String($0), "\($0) links")
                        }
                    ) { store.settings.sourcesPerSizeTier = Int($0) ?? 6 }
                }
            }

            SettingsGroupCard(title: "Player", subtitle: "Which engine opens streams") {
                NuvioDropdown(
                    title: "Playback engine",
                    subtitle: store.settings.playerEngine.footnote,
                    icon: "play.rectangle.on.rectangle.fill",
                    selection: store.settings.playerEngine.rawValue,
                    options: PlayerEngine.allCases.map { NuvioDropdownOption($0.rawValue, $0.label) }
                ) { store.settings.playerEngine = PlayerEngine(rawValue: $0) ?? .auto }

                // External engine: pick WHICH installed app receives streams.
                // canOpenURL only sees apps actually on this Apple TV, so the
                // list is exactly what's installed — and when nothing is, the
                // section stays blank.
                if store.settings.playerEngine == .external {
                    let installed = ExternalPlayers.installed
                    if !installed.isEmpty {
                        NuvioDropdown(
                            title: "External player",
                            subtitle: "Streams open in this app; playback, resume and history then live there",
                            icon: "arrow.up.forward.app.fill",
                            selection: store.settings.externalPlayerID,
                            options: installed.map { NuvioDropdownOption($0.id, $0.name) }
                        ) { store.settings.externalPlayerID = $0 }
                    }
                }

                PlaybackToggleRow(
                    icon: "sparkles.tv.fill",
                    title: "Native Dolby Vision",
                    subtitle: "Play Dolby Vision files (profile 5/8) through Apple's video pipeline for true dynamic DV on DV-capable TVs. Remuxes on-device; falls back to the standard HDR10 engine automatically if anything fails. Off = always use the standard engine.",
                    isOn: s.nativeDolbyVision
                )

                PlaybackToggleRow(
                    icon: "tv.fill",
                    title: "Match content display mode",
                    subtitle: "Switch the TV into the video's HDR mode for native Dolby Vision/HDR. Uses the gentlest switch possible (dynamic range only, no refresh-rate change) to reduce grey-screen risk — but some TVs still mis-handshake and stick on grey until power-cycled, so leave off if that happens. Off = tone-map into the home screen's format (like Stremio).",
                    isOn: s.matchContentDisplayMode
                )
            }

            SettingsGroupCard(title: "Audio", subtitle: "Track selection and output") {
                NuvioDropdown(
                    title: "Preferred language",
                    subtitle: "Automatically pick a matching audio track when the stream has one",
                    icon: "waveform",
                    selection: store.settings.preferredAudioLanguage,
                    options: PlayerSettings.audioLanguageOptions.map { NuvioDropdownOption($0.0, $0.1) }
                ) { store.settings.preferredAudioLanguage = $0 }

                NuvioDropdown(
                    title: "Surround & Dolby Atmos",
                    subtitle: "Auto uses the enhanced renderer (Atmos/spatial + lighter TrueHD/DTS-HD decode) only when your TV or receiver reports spatial-audio support. Takes effect on next playback.",
                    icon: "hifispeaker.2.fill",
                    selection: store.settings.audioOutputMode.rawValue,
                    options: AudioOutputMode.allCases.map { NuvioDropdownOption($0.rawValue, $0.label) }
                ) { store.settings.audioOutputMode = AudioOutputMode(rawValue: $0) ?? .auto }
            }

            SettingsGroupCard(title: "Subtitles", subtitle: "How captions look and when they turn on") {
                PlaybackToggleRow(
                    icon: "captions.bubble.fill",
                    title: "Subtitles on by default",
                    subtitle: "Automatically enable subtitles when a stream loads, picking your preferred language when it's available",
                    isOn: s.subtitlesOnByDefault
                )

                if store.settings.subtitlesOnByDefault {
                    NuvioDropdown(
                        title: "Preferred language",
                        subtitle: "Chosen automatically when the stream has a matching subtitle; otherwise the first available is used",
                        icon: "globe",
                        selection: store.settings.preferredSubtitleLanguage,
                        options: PlayerSettings.subtitleLanguageOptions.map { NuvioDropdownOption($0.0, $0.1) }
                    ) { store.settings.preferredSubtitleLanguage = $0 }
                }

                NuvioDropdown(
                    title: "Text size",
                    icon: "textformat.size",
                    selection: String(store.settings.subtitleSize),
                    options: PlayerSettings.subtitleSizeValues.map {
                        NuvioDropdownOption(String($0), sizeLabel($0))
                    }
                ) { store.settings.subtitleSize = Int($0) ?? 36 }

                PlaybackToggleRow(
                    icon: "rectangle.fill.on.rectangle.fill",
                    title: "Background plate",
                    subtitle: "Dark panel behind captions for readability on bright scenes",
                    isOn: s.subtitleBackground
                )

                PlaybackToggleRow(
                    icon: "bold",
                    title: "Bold text",
                    subtitle: "Heavier caption weight",
                    isOn: s.subtitleBold
                )
            }

            SettingsGroupCard(title: "Trailers", subtitle: "Preview a title's trailer while browsing") {
                NuvioDropdown(
                    title: "Auto-play trailer",
                    subtitle: "Play the trailer in the backdrop after sitting on a title",
                    icon: "play.tv.fill",
                    selection: String(store.settings.autoPlayTrailerSeconds),
                    options: PlayerSettings.trailerDelayValues.map {
                        NuvioDropdownOption(String($0), $0 == 0 ? "Off" : "After \($0)s")
                    }
                ) { store.settings.autoPlayTrailerSeconds = Int($0) ?? 0 }
            }
        }
    }

    @ViewBuilder
    private var autoPlayControls: some View {
        PlaybackToggleRow(
            icon: "forward.end.fill",
            title: "Auto-play next episode",
            subtitle: "Run a countdown on the Up Next card and start the next episode automatically. Off = the card still appears, but waits for you to press Play",
            isOn: s.autoPlayNextEpisode
        )

        if store.settings.autoPlayNextEpisode {
            PlaybackToggleRow(
                icon: "eye.fill",
                title: "Still watching?",
                subtitle: "Pause auto-play after several episodes to check you're still there",
                isOn: s.stillWatchingEnabled
            )

            if store.settings.stillWatchingEnabled {
                NuvioDropdown(
                    title: "Ask after",
                    icon: "repeat",
                    selection: String(store.settings.stillWatchingEpisodeThreshold),
                    options: (2...6).map { NuvioDropdownOption(String($0), "\($0) episodes") }
                ) { store.settings.stillWatchingEpisodeThreshold = Int($0) ?? 3 }
            }

            NuvioDropdown(
                title: "Auto-play countdown",
                icon: "timer",
                selection: String(store.settings.autoPlayTimeoutSeconds),
                options: PlayerSettings.timeoutValues.map { NuvioDropdownOption(String($0), timeoutLabel($0)) }
            ) { store.settings.autoPlayTimeoutSeconds = Int($0) ?? 3 }

            NuvioDropdown(
                title: "Trigger point",
                icon: "slider.horizontal.3",
                selection: store.settings.nextEpisodeThresholdMode == .percentage ? "percentage" : "minutes",
                options: [
                    NuvioDropdownOption("percentage", "% watched"),
                    NuvioDropdownOption("minutes", "Minutes before end")
                ]
            ) { store.settings.nextEpisodeThresholdMode = $0 == "percentage" ? .percentage : .minutesBeforeEnd }

            if store.settings.nextEpisodeThresholdMode == .percentage {
                NuvioDropdown(
                    title: "At percent watched",
                    icon: "chart.bar.fill",
                    selection: formatHalf(store.settings.nextEpisodeThresholdPercent),
                    options: stride(from: 97.0, through: 100.0, by: 0.5).map {
                        NuvioDropdownOption(formatHalf($0), "\(formatHalf($0))%")
                    }
                ) { store.settings.nextEpisodeThresholdPercent = Double($0) ?? 99 }
            } else {
                NuvioDropdown(
                    title: "Minutes before end",
                    icon: "clock.fill",
                    selection: formatHalf(store.settings.nextEpisodeThresholdMinutesBeforeEnd),
                    options: stride(from: 0.0, through: 3.5, by: 0.5).map {
                        NuvioDropdownOption(formatHalf($0), "\(formatHalf($0)) min")
                    }
                ) { store.settings.nextEpisodeThresholdMinutesBeforeEnd = Double($0) ?? 2 }
            }

            PlaybackToggleRow(
                icon: "square.stack.3d.up.fill",
                title: "Prefer same source group",
                subtitle: "Pick the next episode from the same release group when possible",
                isOn: s.preferBingeGroupForNextEpisode
            )

            if store.settings.preferBingeGroupForNextEpisode {
                PlaybackToggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Reuse the same stream",
                    subtitle: "Skip re-fetching sources when the group matches",
                    isOn: s.reuseBingeGroup
                )
            }
        }
    }

    private func sizeLabel(_ size: Int) -> String {
        switch size {
        case ..<32: return "Small (\(size)pt)"
        case ..<40: return "Standard (\(size)pt)"
        case ..<50: return "Large (\(size)pt)"
        default: return "Huge (\(size)pt)"
        }
    }

    private func timeoutLabel(_ seconds: Int) -> String {
        if seconds == 0 { return "Instant" }
        if seconds == PlayerSettings.timeoutUnlimited { return "Wait for me" }
        return "\(seconds)s"
    }

    private func formatHalf(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

// MARK: - Rows

/// A toggle row with a leading icon and Nuvio pill switch (focus = fill + ring,
/// same treatment as every other settings row).
private struct PlaybackToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            PlaybackToggleLabel(icon: icon, title: title, subtitle: subtitle, isOn: isOn)
        }
        .buttonStyle(PlainCardButtonStyle())
    }
}

private struct PlaybackToggleLabel: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let icon: String
    let title: String
    let subtitle: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: NuvioSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(theme.palette.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 19))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            NuvioSwitch(isOn: isOn)
        }
        .padding(.horizontal, NuvioSpacing.lg)
        .frame(minHeight: 74)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .fill(isFocused ? theme.palette.focusBackground : theme.palette.backgroundCard.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NuvioRadius.md, style: .continuous)
                .strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 4)
        )
    }
}

