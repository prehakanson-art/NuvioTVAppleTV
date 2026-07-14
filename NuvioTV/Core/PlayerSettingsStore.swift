import Foundation

/// How the "next episode" threshold is measured, matching the Android
/// `NextEpisodeThresholdMode`.
enum NextEpisodeThresholdMode: String, Codable, CaseIterable {
    case percentage        // fire when position ≥ percent of duration
    case minutesBeforeEnd  // fire when (duration - position) ≤ minutes
}

/// Which playback engine opens a stream first.
/// - auto: route by container — Apple's hardware AVPlayer for native formats
///   (MP4/HLS), FFmpeg (VideoToolbox-accelerated) for MKV & friends. The
///   other engine remains the automatic fallback either way.
/// - native / ffmpeg: force that engine first for every stream.
enum PlayerEngine: String, Codable, CaseIterable {
    case auto, native, ffmpeg, vlc, external

    var label: String {
        switch self {
        case .auto: return "Auto (recommended)"
        case .native: return "Native (AVPlayer)"
        case .ffmpeg: return "FFmpeg (KSPlayer)"
        case .vlc: return "VLC"
        case .external: return "External app"
        }
    }

    var footnote: String {
        switch self {
        case .vlc:
            return "VLC buffers internally (no cache bar) and renders its own subtitles. Try it when a file is choppy on the other engines."
        case .external:
            return "Send every stream to another player app installed on this Apple TV (Infuse, VLC, …) instead of playing in Nuvio. Pick the app below."
        default:
            return "Auto picks the hardware AVPlayer for MP4/HLS and FFmpeg for MKV & friends; the other engine stays as automatic fallback."
        }
    }
}

/// How the FFmpeg engine outputs audio.
/// - auto: use the enhanced renderer (AVSampleBufferAudioRenderer — Dolby
///   Atmos/spatial rendering and cheaper lossless TrueHD/DTS-HD decode) when
///   the connected TV/receiver route reports spatial-audio support, classic
///   AVAudioEngine otherwise. Capability-gated: Atmos-capable setups get it,
///   plain stereo TVs keep the battle-tested path.
/// - renderer / engine: force one side regardless of the route.
enum AudioOutputMode: String, Codable, CaseIterable {
    case auto, renderer, engine

    var label: String {
        switch self {
        case .auto: return "Auto (Atmos when supported)"
        case .renderer: return "Enhanced renderer (always)"
        case .engine: return "Standard (AVAudioEngine)"
        }
    }
}

/// Post-play / auto-next settings, mirroring the Android `PlayerSettings`
/// (same field names + defaults) so behavior matches the APK. Persisted
/// locally; there's no server row for these in the sync schema.
struct PlayerSettings: Codable, Equatable {
    /// The Up Next card always appears near an episode's end; this only
    /// controls whether its countdown runs and auto-starts the next episode.
    var autoPlayNextEpisode: Bool = true
    var preferBingeGroupForNextEpisode: Bool = true
    var reuseBingeGroup: Bool = true
    /// Countdown before auto-advancing. 0 = instant; `timeoutUnlimited` = wait
    /// for the user (no auto-advance, Up Next stays until dismissed/confirmed).
    var autoPlayTimeoutSeconds: Int = 3
    var stillWatchingEnabled: Bool = false
    var stillWatchingEpisodeThreshold: Int = 3
    /// LEGACY (pre-upNextLeadSeconds): kept for save-file compatibility, not
    /// shown or used anymore — the Up Next timing is now credits-chapter
    /// first, then `upNextLeadSeconds` before the end.
    var nextEpisodeThresholdMode: NextEpisodeThresholdMode = .percentage
    var nextEpisodeThresholdPercent: Double = 99
    var nextEpisodeThresholdMinutesBeforeEnd: Double = 2
    /// Fallback for files WITHOUT an end-credits chapter: how many seconds
    /// before the end the Up Next card appears. Default 30.
    var upNextLeadSeconds: Int = 30
    /// Seconds a Detail screen must sit idle before its trailer auto-plays
    /// (muted) in the backdrop. 0 = off. On by default so hero previews work
    /// out of the box.
    var autoPlayTrailerSeconds: Int = 3
    /// Show the "Skip Intro" pill when playback sits inside an intro/recap
    /// chapter (⏯ then skips it).
    var skipIntroEnabled: Bool = true
    /// Automatically jump past intro/recap chapters without a button press.
    var autoSkipSegments: Bool = false
    /// Seconds a single left/right press seeks in the player. Rapid presses
    /// accumulate (2 presses = 2×), holding accelerates.
    var skipSeconds: Int = 10
    /// Seconds a left/right press jumps while in SCRUB mode (the trackpad
    /// zoom-through-the-movie state) — coarser hops than normal skips.
    var scrubJumpSeconds: Int = 60
    /// Diagnostics: show the last trackpad/remote event on-screen in the player
    /// (helps tune gestures on a real Apple TV — the Simulator has no remote).
    var showInputDebug: Bool = false
    /// Subtitle presentation: point size (KSPlayer stamps it onto every cue),
    /// optional dark plate behind lines, bold text.
    var subtitleSize: Int = 36
    var subtitleBackground: Bool = true
    var subtitleBold: Bool = false
    /// Turn subtitles on automatically when a stream loads. When a track in
    /// `preferredSubtitleLanguage` exists it's chosen; otherwise the first
    /// available subtitle.
    var subtitlesOnByDefault: Bool = false
    /// Preferred subtitle language (ISO 639-1 code); "" = first available.
    var preferredSubtitleLanguage: String = "en"
    /// Fallback subtitle language when the preferred one isn't present.
    var subtitleSecondaryLanguage: String = ""
    /// Prefer a "forced" subtitle track (foreign-dialogue only) when one exists.
    var subtitlePreferForced: Bool = false
    // --- Styling ---
    /// Caption text color (hex, no #).
    var subtitleTextColorHex: String = "FFFFFF"
    /// Draw an outline around the text for readability on any background.
    var subtitleOutlineEnabled: Bool = true
    var subtitleOutlineColorHex: String = "000000"
    /// Background plate opacity 0–100 (used when subtitleBackground is on).
    var subtitleBackgroundOpacity: Int = 45
    /// Raise (+) or lower (−) the caption from its default bottom margin, points.
    var subtitleVerticalOffset: Int = 0

    /// Preferred audio language (ISO 639-1 code); "" = stream default. When a
    /// stream carries a matching track it's selected automatically.
    var preferredAudioLanguage: String = ""
    /// Playback engine selection (see PlayerEngine).
    var playerEngine: PlayerEngine = .auto
    /// Which external player app receives streams when playerEngine is
    /// .external (id from ExternalPlayers.catalog).
    var externalPlayerID: String = "infuse"
    /// LEGACY (pre-audioOutputMode): the old force-renderer toggle. Kept only
    /// so existing saves migrate — read once in the decoder, never in the UI.
    var audioRendererEnabled: Bool = false
    /// FFmpeg-engine audio output (see AudioOutputMode). Auto = the enhanced
    /// renderer only when the route is spatial/Atmos-capable.
    var audioOutputMode: AudioOutputMode = .auto

    /// Master switch for the curated link filters. On = each addon's links
    /// are grouped into size tiers (250 MB–4 GB … 30 GB+), debrid-cached
    /// links first, capped per tier. Off = links exactly as each addon
    /// returned them (cached still first), capped per addon so a Torrentio
    /// flood can't drown the UI.
    var sourceFiltersEnabled: Bool = true
    /// LEGACY (pre-size-tier sort): the old per-resolution high/low counts.
    /// Kept only so existing saves decode; not used or shown anymore.
    var sourcesHighGBPerTier: Int = 5
    var sourcesLowGBPerTier: Int = 5
    /// Links shown per size tier (250 MB–4 GB / 4–10 / 10–20 / 20–30 / 30+).
    var sourcesPerSizeTier: Int = 6
    // --- Stream filters (applied before curation) ---
    /// Drop links below this resolution. "" = no minimum. (2160p/1080p/720p/480p)
    var streamMinResolution: String = ""
    /// Hide AV1 links (no hardware decode on the Apple TV A10X → slideshow).
    var streamExcludeAV1: Bool = false
    /// Only show HDR (HDR10/HLG/DV) links.
    var streamHDROnly: Bool = false
    /// Only show Dolby Vision links.
    var streamDolbyVisionOnly: Bool = false
    /// Only show links the debrid service already has cached (instant play).
    var streamCachedOnly: Bool = false
    /// OPT-IN HDR/frame-rate display-mode switching. Off (default) = the
    /// Apple TV stays in its home-screen format and tone-maps content into it
    /// (like the Android APK/Stremio). On = ask the TV to switch into the
    /// content's native mode — some TVs mis-handshake the switch back and
    /// wedge on a grey screen until power-cycled, hence the default.
    var matchContentDisplayMode: Bool = false
    /// Native Dolby Vision output (experimental). When a Dolby Vision file
    /// (profile 5/8) plays on a DV-capable TV, the stream is remuxed on-device
    /// into a DV-tagged fMP4 playlist and handed to Apple's video pipeline —
    /// true dynamic DV instead of the HDR10 tone-map. Any failure falls back
    /// to the standard engine automatically. Off = always use the standard
    /// HDR10 path.
    var nativeDolbyVision: Bool = true

    /// Selectable subtitle sizes.
    static let subtitleSizeValues: [Int] = [28, 32, 36, 42, 48, 56]
    /// Preferred-audio-language choices (code, label).
    static let audioLanguageOptions: [(String, String)] = [
        ("", "Stream default"), ("en", "English"), ("es", "Spanish"),
        ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh", "Chinese"), ("hi", "Hindi"), ("ru", "Russian"), ("ar", "Arabic")
    ]
    /// Preferred-subtitle-language choices (code, label). "" = first available.
    static let subtitleLanguageOptions: [(String, String)] = [
        ("", "First available"), ("en", "English"), ("es", "Spanish"),
        ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh", "Chinese"), ("hi", "Hindi"), ("ru", "Russian"), ("ar", "Arabic")
    ]

    static let timeoutUnlimited = Int.max
    /// Selectable countdown values, matching STREAM_AUTOPLAY_TIMEOUT_VALUES.
    static let timeoutValues: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 25, 30, timeoutUnlimited]
    /// Selectable auto-play-trailer delays (seconds).
    static let trailerDelayValues: [Int] = [0, 1, 2, 3, 5]
    /// Selectable Up Next lead times (seconds before end) for chapter-less files.
    static let upNextLeadValues: [Int] = [10, 15, 20, 30, 45, 60, 90, 120, 180]
    /// Subtitle color presets (hex, display name) — no color picker on tvOS.
    static let subtitleColorOptions: [(String, String)] = [
        ("FFFFFF", "White"), ("F5F5F5", "Off-White"), ("FFEB3B", "Yellow"),
        ("00E5FF", "Cyan"), ("69F0AE", "Green"), ("BDBDBD", "Grey"), ("000000", "Black"),
    ]
    /// Selectable subtitle vertical offsets (points; + raises).
    static let subtitleOffsetValues: [Int] = [-40, -20, 0, 20, 40, 80, 120, 160]
    static let subtitleBackgroundOpacityValues: [Int] = [0, 15, 30, 45, 60, 80, 100]
    /// Selectable per-press skip amounts (seconds).
    static let skipValues: [Int] = [5, 10, 15, 30]
    /// Selectable scrub-mode jump amounts (seconds).
    static let scrubJumpValues: [Int] = [30, 60, 120, 300]
    /// Selectable per-tier link counts (for both the high-GB and low-GB halves).
    static let sourcesPerTierValues: [Int] = [0, 1, 2, 3, 4, 5, 6, 8, 10, 15]
    /// Max links shown per addon when the curated filters are OFF — enough to
    /// dig through, small enough that the tvOS list stays scrollable.
    static let unfilteredPerAddonCap = 40

    /// The user's stream filters as a value for SourceSelection.filter.
    var streamFilterOptions: StreamFilterOptions {
        StreamFilterOptions(
            minResolution: streamMinResolution,
            excludeAV1: streamExcludeAV1,
            hdrOnly: streamHDROnly,
            dolbyVisionOnly: streamDolbyVisionOnly,
            cachedOnly: streamCachedOnly
        )
    }

    static let `default` = PlayerSettings()

    /// Resilient decoding: every missing key falls back to its default, so
    /// adding a setting in an update never wipes the user's saved settings
    /// (synthesized Codable throws on the first missing key).
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerSettings.default
        autoPlayNextEpisode = (try? c.decode(Bool.self, forKey: .autoPlayNextEpisode)) ?? d.autoPlayNextEpisode
        preferBingeGroupForNextEpisode = (try? c.decode(Bool.self, forKey: .preferBingeGroupForNextEpisode)) ?? d.preferBingeGroupForNextEpisode
        reuseBingeGroup = (try? c.decode(Bool.self, forKey: .reuseBingeGroup)) ?? d.reuseBingeGroup
        autoPlayTimeoutSeconds = (try? c.decode(Int.self, forKey: .autoPlayTimeoutSeconds)) ?? d.autoPlayTimeoutSeconds
        stillWatchingEnabled = (try? c.decode(Bool.self, forKey: .stillWatchingEnabled)) ?? d.stillWatchingEnabled
        stillWatchingEpisodeThreshold = (try? c.decode(Int.self, forKey: .stillWatchingEpisodeThreshold)) ?? d.stillWatchingEpisodeThreshold
        nextEpisodeThresholdMode = (try? c.decode(NextEpisodeThresholdMode.self, forKey: .nextEpisodeThresholdMode)) ?? d.nextEpisodeThresholdMode
        nextEpisodeThresholdPercent = (try? c.decode(Double.self, forKey: .nextEpisodeThresholdPercent)) ?? d.nextEpisodeThresholdPercent
        nextEpisodeThresholdMinutesBeforeEnd = (try? c.decode(Double.self, forKey: .nextEpisodeThresholdMinutesBeforeEnd)) ?? d.nextEpisodeThresholdMinutesBeforeEnd
        upNextLeadSeconds = (try? c.decode(Int.self, forKey: .upNextLeadSeconds)) ?? d.upNextLeadSeconds
        autoPlayTrailerSeconds = (try? c.decode(Int.self, forKey: .autoPlayTrailerSeconds)) ?? d.autoPlayTrailerSeconds
        skipIntroEnabled = (try? c.decode(Bool.self, forKey: .skipIntroEnabled)) ?? d.skipIntroEnabled
        autoSkipSegments = (try? c.decode(Bool.self, forKey: .autoSkipSegments)) ?? d.autoSkipSegments
        skipSeconds = (try? c.decode(Int.self, forKey: .skipSeconds)) ?? d.skipSeconds
        scrubJumpSeconds = (try? c.decode(Int.self, forKey: .scrubJumpSeconds)) ?? d.scrubJumpSeconds
        showInputDebug = (try? c.decode(Bool.self, forKey: .showInputDebug)) ?? d.showInputDebug
        subtitleSize = (try? c.decode(Int.self, forKey: .subtitleSize)) ?? d.subtitleSize
        subtitleBackground = (try? c.decode(Bool.self, forKey: .subtitleBackground)) ?? d.subtitleBackground
        subtitleBold = (try? c.decode(Bool.self, forKey: .subtitleBold)) ?? d.subtitleBold
        subtitlesOnByDefault = (try? c.decode(Bool.self, forKey: .subtitlesOnByDefault)) ?? d.subtitlesOnByDefault
        preferredSubtitleLanguage = (try? c.decode(String.self, forKey: .preferredSubtitleLanguage)) ?? d.preferredSubtitleLanguage
        subtitleSecondaryLanguage = (try? c.decode(String.self, forKey: .subtitleSecondaryLanguage)) ?? d.subtitleSecondaryLanguage
        subtitlePreferForced = (try? c.decode(Bool.self, forKey: .subtitlePreferForced)) ?? d.subtitlePreferForced
        subtitleTextColorHex = (try? c.decode(String.self, forKey: .subtitleTextColorHex)) ?? d.subtitleTextColorHex
        subtitleOutlineEnabled = (try? c.decode(Bool.self, forKey: .subtitleOutlineEnabled)) ?? d.subtitleOutlineEnabled
        subtitleOutlineColorHex = (try? c.decode(String.self, forKey: .subtitleOutlineColorHex)) ?? d.subtitleOutlineColorHex
        subtitleBackgroundOpacity = (try? c.decode(Int.self, forKey: .subtitleBackgroundOpacity)) ?? d.subtitleBackgroundOpacity
        subtitleVerticalOffset = (try? c.decode(Int.self, forKey: .subtitleVerticalOffset)) ?? d.subtitleVerticalOffset
        preferredAudioLanguage = (try? c.decode(String.self, forKey: .preferredAudioLanguage)) ?? d.preferredAudioLanguage
        playerEngine = (try? c.decode(PlayerEngine.self, forKey: .playerEngine)) ?? d.playerEngine
        externalPlayerID = (try? c.decode(String.self, forKey: .externalPlayerID)) ?? d.externalPlayerID
        audioRendererEnabled = (try? c.decode(Bool.self, forKey: .audioRendererEnabled)) ?? d.audioRendererEnabled
        // Migration: saves from before audioOutputMode existed carry only the
        // old force-renderer bool — honor it as an explicit "renderer".
        audioOutputMode = (try? c.decode(AudioOutputMode.self, forKey: .audioOutputMode))
            ?? (audioRendererEnabled ? .renderer : d.audioOutputMode)
        sourceFiltersEnabled = (try? c.decode(Bool.self, forKey: .sourceFiltersEnabled)) ?? d.sourceFiltersEnabled
        sourcesHighGBPerTier = (try? c.decode(Int.self, forKey: .sourcesHighGBPerTier)) ?? d.sourcesHighGBPerTier
        sourcesLowGBPerTier = (try? c.decode(Int.self, forKey: .sourcesLowGBPerTier)) ?? d.sourcesLowGBPerTier
        sourcesPerSizeTier = (try? c.decode(Int.self, forKey: .sourcesPerSizeTier)) ?? d.sourcesPerSizeTier
        streamMinResolution = (try? c.decode(String.self, forKey: .streamMinResolution)) ?? d.streamMinResolution
        streamExcludeAV1 = (try? c.decode(Bool.self, forKey: .streamExcludeAV1)) ?? d.streamExcludeAV1
        streamHDROnly = (try? c.decode(Bool.self, forKey: .streamHDROnly)) ?? d.streamHDROnly
        streamDolbyVisionOnly = (try? c.decode(Bool.self, forKey: .streamDolbyVisionOnly)) ?? d.streamDolbyVisionOnly
        streamCachedOnly = (try? c.decode(Bool.self, forKey: .streamCachedOnly)) ?? d.streamCachedOnly
        matchContentDisplayMode = (try? c.decode(Bool.self, forKey: .matchContentDisplayMode)) ?? d.matchContentDisplayMode
        nativeDolbyVision = (try? c.decode(Bool.self, forKey: .nativeDolbyVision)) ?? d.nativeDolbyVision
    }
}

@MainActor
final class PlayerSettingsStore: ObservableObject {
    @Published var settings: PlayerSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }

    private static let key = "nuvio.player.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(PlayerSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
