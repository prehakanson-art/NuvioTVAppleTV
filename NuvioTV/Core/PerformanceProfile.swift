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
///   a 2 GB box). Newer/4K devices are left at full resolution — no change.
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
    static let isLowPower: Bool = {
        if machine.hasPrefix("AppleTV5") { return true }
        return ProcessInfo.processInfo.physicalMemory < 2_500_000_000
    }()

    /// Longest decoded image dimension. On the 1080p HD, cap at 1920 (the
    /// display's own width — imperceptible) instead of decoding full 4K-ish
    /// TMDB "original" art. `nil` = no downsampling (full res, unchanged).
    static var maxImagePixelSize: CGFloat? { isLowPower ? 1920 : nil }

    /// Decoded-pixel memory-cache budget. Smaller on the 2 GB HD so the app
    /// isn't jetsammed; larger everywhere else. Invisible — evicted images just
    /// re-decode from the disk cache.
    static var imageCacheBytes: Int { isLowPower ? 96 << 20 : 256 << 20 }
    static var imageCacheCount: Int { isLowPower ? 200 : 400 }
}
