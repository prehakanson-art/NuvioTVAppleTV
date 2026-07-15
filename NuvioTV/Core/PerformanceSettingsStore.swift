import Foundation
import SwiftUI

/// User-tunable performance switches (Settings → Performance). On 4K gen-2+
/// hardware everything defaults ON — the app's full look. Older boxes start
/// with the costly effects OFF (see `tierDefaults()`); every switch remains
/// user-tunable either way, so the tier default is a starting point, not a cap.
///
/// Persisted per-device in UserDefaults and deliberately NOT synced to the
/// account: a setting tuned for the living-room 4K gen 1 shouldn't downgrade
/// a newer box on the same account.
@MainActor
final class PerformanceSettingsStore: ObservableObject {
    static let shared = PerformanceSettingsStore()

    struct Settings: Codable, Equatable {
        /// Full-screen artwork behind Home that changes as you browse.
        var heroBackdrop = true
        /// Dissolve animation when the hero artwork/info changes.
        var heroCrossfade = true
        /// Soft drop shadows under posters and cards.
        var cardShadows = true
        /// Cards spring slightly larger when focused.
        var focusZoom = true
        /// Animated pin of the focused row under the billboard.
        var rowPinAnimation = true
        /// Background download of below-the-fold row artwork.
        var artworkPrefetch = true
        /// Fade posters in as they finish loading.
        var artworkFadeIn = true
        /// The sidebar's expand/collapse spring + the dim over the content.
        var sidebarAnimation = true
        /// Scale/spring on small controls (See All, tab pills, presses).
        var buttonAnimations = true

        init() {}

        private enum CodingKeys: String, CodingKey {
            case heroBackdrop, heroCrossfade, cardShadows, focusZoom
            case rowPinAnimation, artworkPrefetch, artworkFadeIn
            case sidebarAnimation, buttonAnimations
        }

        /// Lenient decode: a key missing from an older save keeps its default
        /// instead of failing the whole decode (which would reset every
        /// switch each time a new one ships).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            heroBackdrop = (try? c.decode(Bool.self, forKey: .heroBackdrop)) ?? true
            heroCrossfade = (try? c.decode(Bool.self, forKey: .heroCrossfade)) ?? true
            cardShadows = (try? c.decode(Bool.self, forKey: .cardShadows)) ?? true
            focusZoom = (try? c.decode(Bool.self, forKey: .focusZoom)) ?? true
            rowPinAnimation = (try? c.decode(Bool.self, forKey: .rowPinAnimation)) ?? true
            artworkPrefetch = (try? c.decode(Bool.self, forKey: .artworkPrefetch)) ?? true
            artworkFadeIn = (try? c.decode(Bool.self, forKey: .artworkFadeIn)) ?? true
            sidebarAnimation = (try? c.decode(Bool.self, forKey: .sidebarAnimation)) ?? true
            buttonAnimations = (try? c.decode(Bool.self, forKey: .buttonAnimations)) ?? true
        }
    }

    @Published var settings: Settings { didSet { save() } }

    private static let key = "nuvio.performance.v1"

    /// First-run defaults tuned to the hardware tier. Users who never open
    /// Settings → Performance shouldn't pay full-eye-candy jank on an A8/A10X:
    /// the costly effects start OFF there and can be re-enabled per switch.
    /// Anything the user has ever saved wins over these (see init).
    static func tierDefaults() -> Settings {
        var s = Settings()
        if PerformanceProfile.isLowPower {
            // Apple TV HD (A8 / 2 GB): keep the core feel (hero backdrop,
            // focus zoom) but drop every recurring animation/composite cost.
            s.cardShadows = false
            s.heroCrossfade = false
            s.artworkFadeIn = false
            s.rowPinAnimation = false
            s.sidebarAnimation = false
            s.buttonAnimations = false
        } else if PerformanceProfile.isMidPower {
            // 4K gen 1 (A10X / 3 GB): shadows and per-cell fades are the two
            // that visibly cost during row scrolls; the rest it handles fine.
            s.cardShadows = false
            s.artworkFadeIn = false
        }
        return s
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Self.tierDefaults()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
