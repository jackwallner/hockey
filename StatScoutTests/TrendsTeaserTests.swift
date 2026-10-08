import XCTest
@testable import Gridiron_StatScout

/// The blurred board behind the Trends paywall has to redraw when the controls
/// move.
///
/// Row one of that board is real: the genuine league leader for the selected
/// metric, direction and window. Everything under it is invented, seeded so it
/// looks like a plausible continuation. When the seed fails to reshuffle, the
/// user changes the window, watches the real name at the top change, and sees
/// eighteen identical rows underneath, which advertises that they are fake.
///
/// That is exactly what shipped: `stableSeed` was a rolling `h * 31 + c`, and
/// the seed sat at the end of the hashed string, so switching the window from 3
/// games to 5 added the same +2 to every player's hash and the sort order came
/// out untouched. These pin both halves of the fix, the seed's position and the
/// hash's avalanche, because either one silently reverting brings the tell back.
final class TrendsTeaserTests: XCTestCase {

    /// Stand-ins for the roster the teaser draws from. nflverse ids are close to
    /// sequential within a draft class, which is what made the old affine hash
    /// look plausible in isolation and fail on real data.
    private let playerIds = (0..<60).map { "00-00\(34000 + $0 * 37)" }

    private func teaserOrder(seed: String, count: Int = 18) -> [String] {
        playerIds
            .map { ($0, HotColdView.stableSeed("\(seed)-\($0)")) }
            .sorted { $0.1 < $1.1 }
            .prefix(count)
            .map { $0.0 }
    }

    /// The window is the last component of the seed and the one that reproduced
    /// the bug: 3 / 5 / 8 differ by a single digit in the final position.
    func testChangingTheWindowRedrawsTheBoardUnderTheBlur() {
        let orders = ["3", "5", "8"].map {
            teaserOrder(seed: "epa_per_play-false-\($0)-2025-REG")
        }
        for (a, b) in [(0, 1), (1, 2), (0, 2)] {
            XCTAssertNotEqual(orders[a], orders[b], "The window changed and the teaser did not")
            let shared = Set(orders[a].prefix(5)).intersection(orders[b].prefix(5))
            XCTAssertLessThanOrEqual(
                shared.count, 2,
                "The top of the teaser barely moved between windows: \(shared)"
            )
        }
    }

    /// Every other control on the screen feeds the same seed.
    func testEveryTrendsControlRedrawsTheBoard() {
        let base = "epa_per_play-false-3-2025-REG"
        let variants = [
            "cpoe-false-3-2025-REG",          // metric
            "epa_per_play-true-3-2025-REG",   // cooling off
            "epa_per_play-false-3-2024-REG",  // season
            "epa_per_play-false-3-2025-POST",     // phase
        ]
        let baseline = teaserOrder(seed: base)
        for variant in variants {
            XCTAssertNotEqual(teaserOrder(seed: variant), baseline, "\(variant) left the teaser unchanged")
        }
    }

    /// A one-character change anywhere in the string has to move the hash, not
    /// nudge it. This is the property the old `h * 31 + c` lacked at the tail.
    func testOneCharacterChangesTheWholeSeed() {
        let a = HotColdView.stableSeed("epa_per_play-false-3-2025-REG-00-0034796")
        let b = HotColdView.stableSeed("epa_per_play-false-5-2025-REG-00-0034796")
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThan(
            abs(a - b), 1_000,
            "Seeds \(a) and \(b) are adjacent, so sorting by them preserves the old order"
        )
    }

    /// Deterministic across launches: the teaser must not reshuffle on a redraw,
    /// which is why this is not `hashValue`.
    func testTheSameSeedAlwaysProducesTheSameBoard() {
        let seed = "epa_per_play-false-3-2025-REG"
        XCTAssertEqual(teaserOrder(seed: seed), teaserOrder(seed: seed))
        XCTAssertEqual(HotColdView.stableSeed("00-0034796"), HotColdView.stableSeed("00-0034796"))
    }

    /// Used as an array index and a modulus, so it can never be negative.
    func testSeedsAreAlwaysUsableAsAnIndex() {
        for id in playerIds {
            let seed = HotColdView.stableSeed("epa_per_play-false-3-2025-REG-\(id)")
            XCTAssertGreaterThanOrEqual(seed, 0)
            XCTAssertLessThan(seed, 100_003)
        }
    }
}
