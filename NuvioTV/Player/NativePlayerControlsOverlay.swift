import SwiftUI

/// The "HBO" player layout — a minimal, Apple-TV-native-STYLE transport, chosen
/// via Settings → Themes → Player Layout. Modelled on tvOS's own system player
/// chrome: a slim white scrubber with elapsed / remaining at the ends, a compact
/// title above it, and a row of plain glyph controls that simply brighten on
/// focus (no accent-filled circles). It drives the same `PlayerViewModel` as the
/// Classic overlay, so seeking, sources, subtitles and engine switching all work
/// identically — only the chrome is stripped back to feel like the built-in
/// player. (Orivio's engine is a custom KSPlayer renderer, so this is a native
/// LOOK rather than a literal `AVPlayerViewController`.)
struct NativePlayerControlsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    @FocusState private var focusedControl: Control?

    enum Control: Hashable {
        case timeline, skipBack, playPause, skipForward, nextEpisode
        case subtitles, audio, sources, episodes, speed, aspect, engine
    }

    private var skip: Double { Double(viewModel.settings.skipSeconds) }

    var body: some View {
        ZStack {
            gradient
            if viewModel.scanPreview != nil { scanBadge }
            VStack(alignment: .leading, spacing: NuvioSpacing.md) {
                Spacer()
                titleBlock
                buttonRow
                NativeScrubber(
                    viewModel: viewModel,
                    isFocused: focusedControl == .timeline,
                    onFocusButtons: { focusedControl = .playPause }
                )
                .focused($focusedControl, equals: .timeline)
            }
            .padding(.horizontal, NuvioSpacing.huge)
            .padding(.bottom, NuvioSpacing.xxl)
        }
        // Land focus on the transport row so the Rewind / Play / Fast-Forward
        // buttons are the immediate, obvious controls (left/right steps between
        // them, click acts); the scrubber — which also seeks with left/right —
        // is one press Down. Focus is set exactly once, on first appearance:
        // re-asserting it every re-render makes focus oscillate, which both
        // restarts the hide timer forever (controls never auto-hide) and steals
        // presses away from whatever's focused.
        .onAppear { focusedControl = .playPause }
        .onChange(of: focusedControl) { _, _ in
            viewModel.restartHideTimer()
        }
    }

    // A single soft bottom scrim, like the system player — the video stays clear.
    private var gradient: some View {
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .frame(height: 360)
        }
        .ignoresSafeArea()
    }

    /// Big centred read-out while a fast-forward / rewind preview is active — the
    /// previewed time, plus the sweep speed while continuously scanning. Reminds
    /// the user that playback resumes there only when they press Play.
    private var scanBadge: some View {
        let forward = viewModel.scanRate >= 0
        return VStack {
            HStack(spacing: 14) {
                Image(systemName: forward ? "forward.fill" : "backward.fill")
                    .font(.system(size: 30, weight: .bold))
                if let p = viewModel.scanPreview {
                    Text(TimeFormat.clock(p))
                        .font(.system(size: 40, weight: .heavy).monospacedDigit())
                }
                if viewModel.scanRate != 0 {
                    Text("\(abs(viewModel.scanRate))x")
                        .font(.system(size: 26, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 34).padding(.vertical, 18)
            .background(.black.opacity(0.55), in: Capsule())
            Text("Press Play to resume here")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 12)
            Spacer()
        }
        .padding(.top, 70)
        .transition(.opacity)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.displayTitle)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let episodeLine = viewModel.episodeLine {
                Text(episodeLine)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }

    private var buttonRow: some View {
        HStack(spacing: NuvioSpacing.lg) {
            // Tap = jump ±skip; hold = start/stop a continuous scan; tapping the
            // active-direction button while scanning bumps 2x → 3x.
            NativeScanButton(systemName: "backward.fill",
                             label: viewModel.scanRate < 0 ? "Rewind \(abs(viewModel.scanRate))x" : "Rewind",
                             active: viewModel.scanRate < 0,
                             onTap: { viewModel.scanTap(forward: false); viewModel.restartHideTimer() },
                             onHold: { viewModel.scanHold(forward: false) })
                .focused($focusedControl, equals: .skipBack)

            NativeIconButton(systemName: (viewModel.scanPreview == nil && viewModel.isPlaying) ? "pause.fill" : "play.fill",
                             label: viewModel.scanPreview != nil ? "Play Here"
                                    : (viewModel.isPlaying ? "Pause" : "Play")) {
                // With a preview up, Play commits it (seek + resume); this is the
                // only point the video loads. Otherwise it's a normal toggle.
                viewModel.togglePlayPause(); viewModel.restartHideTimer()
            }
            .focused($focusedControl, equals: .playPause)

            NativeScanButton(systemName: "forward.fill",
                             label: viewModel.scanRate > 0 ? "Fast Forward \(viewModel.scanRate)x" : "Fast Forward",
                             active: viewModel.scanRate > 0,
                             onTap: { viewModel.scanTap(forward: true); viewModel.restartHideTimer() },
                             onHold: { viewModel.scanHold(forward: true) })
                .focused($focusedControl, equals: .skipForward)

            if viewModel.nextEpisode != nil {
                NativeIconButton(systemName: "forward.end.fill", label: "Next Episode") {
                    if let next = viewModel.nextEpisode { viewModel.play(episode: next) }
                }
                .focused($focusedControl, equals: .nextEpisode)
            }
            if !viewModel.subtitleOptions.isEmpty {
                NativeIconButton(systemName: "captions.bubble", label: "Subtitles") { viewModel.overlay = .subtitles }
                    .focused($focusedControl, equals: .subtitles)
            }
            if !viewModel.audioOptions.isEmpty {
                NativeIconButton(systemName: "waveform", label: "Audio") { viewModel.overlay = .audio }
                    .focused($focusedControl, equals: .audio)
            }
            NativeIconButton(systemName: "arrow.left.arrow.right", label: "Sources") { viewModel.overlay = .sources }
                .focused($focusedControl, equals: .sources)
            if viewModel.currentVideo != nil {
                NativeIconButton(systemName: "list.bullet", label: "Episodes") { viewModel.overlay = .episodes }
                    .focused($focusedControl, equals: .episodes)
            }
            NativeIconButton(systemName: "speedometer", label: "Speed") { viewModel.overlay = .speed }
                .focused($focusedControl, equals: .speed)
            NativeIconButton(systemName: "aspectratio", label: "Aspect") {
                viewModel.cycleAspect(); viewModel.restartHideTimer()
            }
            .focused($focusedControl, equals: .aspect)
            NativeIconButton(systemName: "cpu", label: "Engine") { viewModel.overlay = .engine }
                .focused($focusedControl, equals: .engine)

            Spacer()
        }
    }
}

/// A plain transport glyph — no chrome; it just brightens and lifts slightly on
/// focus, with the label captioned underneath (matching the system player).
private struct NativeIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { NativeIconGlyph(systemName: systemName, label: label) }
            .buttonStyle(PlainCardButtonStyle())
            .accessibilityLabel(label)
    }
}

/// Fast-forward / rewind control that distinguishes a quick PRESS (tap → jump or
/// speed-bump) from a HOLD (long-press → start/stop the continuous scan).
private struct NativeScanButton: View {
    let systemName: String
    let label: String
    let active: Bool
    let onTap: () -> Void
    let onHold: () -> Void
    var body: some View {
        NativeIconGlyph(systemName: systemName, label: label, active: active)
            .focusable()
            .onLongPressGesture(minimumDuration: 0.45, perform: onHold)
            .onTapGesture(perform: onTap)
            .accessibilityLabel(label)
    }
}

private struct NativeIconGlyph: View {
    @Environment(\.isFocused) private var isFocused
    let systemName: String
    let label: String
    var active: Bool = false
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(isFocused || active ? 1 : 0.6))
                .frame(width: 54, height: 54)
                .scaleEffect(isFocused ? 1.18 : (active ? 1.08 : 1))
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .opacity(isFocused || active ? 1 : 0)
                .lineLimit(1).fixedSize()
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.85), value: isFocused)
        .animation(.easeOut(duration: 0.16), value: active)
    }
}

/// The system-style scrubber. The `.focusable()` container is intentionally
/// STABLE — it does NOT observe the clock, so it isn't rebuilt on every playback
/// tick (rebuilding a focusable can make the focus engine churn, which restarts
/// the auto-hide timer forever and steals presses). The moving fill/thumb and
/// time read-outs live in a child that observes the clock and repaints alone.
private struct NativeScrubber: View {
    let viewModel: PlayerViewModel
    let isFocused: Bool
    let onFocusButtons: () -> Void

    var body: some View {
        NativeScrubberBar(viewModel: viewModel, clock: viewModel.clock, isFocused: isFocused)
            .focusable()
            // Click = play/pause (native behaviour). Seeking is left/right; we
            // never drop into the separate scrub HUD from here.
            .onTapGesture { viewModel.togglePlayPause(); viewModel.restartHideTimer() }
            .onMoveCommand { direction in
                switch direction {
                case .left: viewModel.nudgeSeek(-Double(viewModel.settings.skipSeconds))
                case .right: viewModel.nudgeSeek(Double(viewModel.settings.skipSeconds))
                case .up: onFocusButtons()
                case .down: viewModel.restartHideTimer()
                @unknown default: break
                }
            }
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

private struct NativeScrubberBar: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject var clock: PlaybackClock
    let isFocused: Bool

    var body: some View {
        let duration = max(clock.duration, 1)
        // While a fast-forward/rewind preview is active the playhead follows the
        // previewed position (the bar moves without the video seeking).
        let rawPosition = viewModel.scanPreview ?? (clock.position + viewModel.pendingSeekDelta)
        let previewPosition = min(max(rawPosition, 0), duration)
        let played = previewPosition / duration
        let buffered = min(clock.buffered / duration, 1)
        let remaining = max(duration - previewPosition, 0)

        VStack(spacing: NuvioSpacing.xs) {
            GeometryReader { geo in
                let w = geo.size.width
                let h: CGFloat = isFocused ? 8 : 5
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    if buffered > played {
                        Capsule().fill(.white.opacity(0.35)).frame(width: w * CGFloat(buffered))
                    }
                    Capsule().fill(.white).frame(width: max(w * CGFloat(played), h))
                    Circle().fill(.white)
                        .frame(width: isFocused ? 22 : 15, height: isFocused ? 22 : 15)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .offset(x: min(max(w * CGFloat(played) - (isFocused ? 11 : 7.5), 0),
                                       w - (isFocused ? 22 : 15)))
                }
                .frame(height: h)
                .frame(maxHeight: .infinity)
            }
            .frame(height: isFocused ? 22 : 15)

            HStack(spacing: NuvioSpacing.sm) {
                Text(TimeFormat.clock(previewPosition))
                    .foregroundStyle(.white.opacity(isFocused ? 1 : 0.85))
                if viewModel.pendingSeekDelta != 0 {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.pendingSeekDelta > 0 ? "forward.fill" : "backward.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(TimeFormat.signedDelta(viewModel.pendingSeekDelta))
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                Text("-\(TimeFormat.clock(remaining))")
                    .foregroundStyle(.white.opacity(isFocused ? 0.85 : 0.6))
            }
            .font(.system(size: 20, weight: .medium).monospacedDigit())
        }
    }
}
