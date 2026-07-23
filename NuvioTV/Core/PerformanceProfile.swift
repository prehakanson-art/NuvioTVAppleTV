import Foundation
import UIKit

/// Hardware-tier detection used ONLY for optimizations that are visually and
/// behaviorally identical — the UI must look and act exactly the same on every
/// device; older Apple TVs just do less wasted work under the hood.
///
/// - **low power** — Apple TV HD (AppleTV5,3 · A8 · 2 GB · 1080p output). On a
///   1080p framebuffer, decoding a 3840px source image is pure waste: the panel
///   can't show more than 1920px, so downsampling there is pixel-identical yet
///   cuts image memory ~75% (the memory pressure that causes jetsam/stutter on
///   a 2 GB box).
/// - **mid power** — Apple TV 4K 1st gen (AppleTV6,2 · A10X · 3 GB), and any
///   unknown device under 3.5 GB. Full 4K rendering, but a tighter decoded-
///   pixel budget: 3 GB shared with tvOS + the player leaves much less
///   headroom than the 4 GB boxes, and an oversized cache there turns into
///   jetsam kills instead of speed.
enum PerformanceProfile {
    /// Machine identifier, e.g. "AppleTV5,3" (HD), "AppleTV6,2" (4K 1st gen).
    static let machine: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()

    /// True on the Apple TV HD (A8 / 2 GB / 1080p) — and any unknown device
    /// reporting <2.5 GB RAM, as a safe fallback.
    ///
    /// Dev override: `-lowPower` forces this tier. The SIMULATOR reports the
    /// host Mac's machine id and RAM, so it always resolves to the high-power
    /// tier and none of the A8 gates ever run there — this argument is the only
    /// way to exercise the Apple TV HD code path without the physical box.
    static let isLowPower: Bool = {
        if ProcessInfo.processInfo.arguments.contains("-lowPower") { return true }
        if machine.hasPrefix("AppleTV5") { return true }
        return ProcessInfo.processInfo.physicalMemory < 2_500_000_000
    }()

    /// 4K devices with constrained RAM (the 3 GB first-gen 4K).
    static let isMidPower: Bool = {
        if isLowPower { return false }
        if machine.hasPrefix("AppleTV6") { return true }   // 4K 1st gen (3 GB)
        return ProcessInfo.processInfo.physicalMemory < 3_500_000_000
    }()

    /// Friendly hardware-tier name for the "Reset to recommended" affordance.
    static var tierLabel: String {
        if machine.hasPrefix("AppleTV5") { return "Apple TV HD" }
        if machine.hasPrefix("AppleTV6") { return "Apple TV 4K (1st gen)" }
        if isLowPower { return "this Apple TV" }
        if isMidPower { return "this Apple TV 4K" }
        return "Apple TV 4K"
    }

    /// Longest decoded image dimension. 1080p HD caps at 1920 (its own panel
    /// width); 4K devices cap at 3840 (the framebuffer — art beyond that cannot
    /// render more detail, so the cap is pixel-identical). Individual views
    /// pass tighter per-image budgets when they know their rendered size.
    static var maxImagePixelSize: CGFloat { isLowPower ? 1920 : 3840 }

    /// Decoded-pixel memory-cache budget, sized to what the box can spare.
    /// Invisible — evicted images just re-decode from the disk cache.
    static var imageCacheBytes: Int {
        if isLowPower { return 96 << 20 }
        if isMidPower { return 160 << 20 }
        return 256 << 20
    }

    static var imageCacheCount: Int {
        if isLowPower { return 200 }
        if isMidPower { return 300 }
        return 400
    }

    /// Hard ceiling on the video read-ahead cache (compressed packets held in
    /// RAM by KSPlayer). tvOS has no working disk cache (FFmpeg's cache:
    /// protocol can't open a temp file in the sandbox), so the buffer lives in
    /// memory and an oversized one jetsams the app. These are the most a box
    /// can safely spare on top of decode + Metal render + the rest of the app.
    /// Apple TV HD (2 GB), 4K gen-1 (3 GB), 4K gen-2/3 (4 GB+).
    static var maxBufferBytes: Int {
        if isLowPower { return 220 << 20 }   // ~220 MB (Apple TV HD, 2 GB)
        if isMidPower { return 400 << 20 }   // ~400 MB (4K gen 1/2, 3 GB)
        return 1000 << 20                    // ~1 GB (4K gen 3, 4 GB+)
    }

    /// Whether native Dolby Vision **Profile 7** (the dual-layer → 8.1 remux)
    /// should default ON here. Unlike profiles 5/8 (cheap, tag-only), the DV7
    /// path re-reads and RPU-rewrites the *entire* file with libdovi while
    /// playback streams in parallel — a heavy CPU + memory + network load that
    /// the 3 GB gen-1/2 4K (and the 2 GB HD) can't sustain, so it hangs the app
    /// mid-play. Only the 4 GB+ boxes (gen-3) get it on by default. This gates
    /// only the DEFAULT; the toggle stays user-flippable on every device, so an
    /// older box can still opt in (at the risk of the freeze).
    static var recommendsDolbyVisionProfile7: Bool { !isLowPower && !isMidPower }
}
