import Foundation
import Observation

/// Favorited players and team, persisted in `UserDefaults`.
///
/// Deliberately free, favoriting is what makes the app feel like yours, and
/// gating it would suppress the very signal the Trends tab and the review
/// funnel read from. What's paid is the *payoff*: recent-form deltas and alerts
/// on the players you follow.
@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()

    private static let playersKey = "favorites.playerIds"
    private static let teamKey = "favoriteTeam"

    private let defaults: UserDefaults

    /// Insertion-ordered so "Your players" reads in the order they were added
    /// rather than reshuffling on every launch the way a Set would.
    private(set) var playerIds: [Int]
    private(set) var team: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.playerIds = defaults.array(forKey: Self.playersKey) as? [Int] ?? []
        // Same key the Teams tab has always used, so existing favorites survive.
        self.team = defaults.string(forKey: Self.teamKey)
    }

    // MARK: - Players

    func isFavorite(playerId: Int) -> Bool {
        playerIds.contains(playerId)
    }

    func toggleFavorite(playerId: Int) {
        if let index = playerIds.firstIndex(of: playerId) {
            playerIds.remove(at: index)
        } else {
            playerIds.append(playerId)
        }
        defaults.set(playerIds, forKey: Self.playersKey)
    }

    // MARK: - Team

    func isFavorite(team abbr: String) -> Bool {
        team == abbr
    }

    func setFavorite(team abbr: String?) {
        team = abbr
        if let abbr {
            defaults.set(abbr, forKey: Self.teamKey)
        } else {
            defaults.removeObject(forKey: Self.teamKey)
        }
    }

    /// Anything followed at all. Used as a review-funnel eligibility signal:
    /// someone who has curated a list has told us they're invested, which is a
    /// different (and better) thing than having opened a few pages.
    var hasAnyFavorite: Bool {
        !playerIds.isEmpty || team != nil
    }
}
