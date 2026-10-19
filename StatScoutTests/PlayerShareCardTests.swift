import XCTest
@testable import Hockey_StatScout

@MainActor
final class PlayerShareCardTests: XCTestCase {
    private func metric(_ label: String, _ value: String, _ pct: Int) -> Metric {
        Metric(id: label, label: label, value: value, percentile: pct, category: .scoring)
    }

    private var card: PlayerShareCard {
        let first = [metric("Goals/60", "1.42", 97), metric("Points/60", "3.31", 95), metric("xG/60", "1.18", 92)]
        let second = [metric("CF%", "55.4%", 84), metric("xGF%", "56.1%", 88)]
        let player = Player(playerId: 1, name: "Matty Beniers", team: "SEA", position: "C", handedness: "",
            updatedAt: Date(), season: StatScoutSeason.current, playerType: "skater",
            metrics: first + second, standardStats: [], games: [])
        return PlayerShareCard(
            player: player,
            groups: [("Scoring", first), ("Play", second)],
            seasonLabel: String(StatScoutSeason.current),
            isCurrentSeason: true
        )
    }

    func testRendersPNGAtThreeTimesCardWidth() throws {
        let image = try XCTUnwrap(PlayerShareImage.render(card))
        let rendered = try XCTUnwrap(UIImage(data: image.png))
        XCTAssertEqual(rendered.size.width * rendered.scale, PlayerShareCard.width * 3, accuracy: 1)
        XCTAssertEqual(image.fileName, "Matty-Beniers-\(StatScoutSeason.current).png")

        let attachment = XCTAttachment(data: image.png, uniformTypeIdentifier: "public.png")
        attachment.name = "share-card"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShareMessageLinksTheAppStoreListing() {
        let message = StatScoutShare.message(for: card.player, seasonLabel: "2026")
        XCTAssertTrue(message.contains("https://apps.apple.com/app/id\(AppStoreReviewLinks.appStoreID)"))
        XCTAssertTrue(message.hasPrefix("Matty Beniers, 2026 percentiles"))
    }
}
