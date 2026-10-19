import SwiftUI
import UniformTypeIdentifiers

/// The image a player's percentile board is shared as.
///
/// Built from the same `MetricBar` rows as the profile, so a card dropped in a
/// group chat reads exactly like the screen it came from, with the app named
/// in the footer as the place to look the rest up.
struct PlayerShareCard: View {
    let player: Player
    let groups: [(title: String, metrics: [Metric])]
    let seasonLabel: String
    let isCurrentSeason: Bool

    static let width: CGFloat = 390

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(groups, id: \.title) { group in
                RinkSubSectionBar(title: group.title)
                ForEach(Array(group.metrics.enumerated()), id: \.element.id) { index, metric in
                    MetricBar(metric: metric)
                        .padding(.horizontal, RinkGeo.padCard)
                        .padding(.vertical, 7)
                        .background(index % 2 == 0 ? RinkPalette.surface : RinkPalette.surfaceAlt)
                }
            }
            footer
        }
        .frame(width: Self.width)
        .background(RinkPalette.surface)
        // An image has one size; the reader's text setting must not decide it.
        .environment(\.dynamicTypeSize, .large)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PlayerHeadshot(team: player.team, initials: player.initials, size: 52)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(RinkType.playerName)
                    .foregroundStyle(RinkPalette.inkOnDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(identityLine)
                    .font(RinkType.small)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(seasonLabel)
                    .font(RinkType.statLarge)
                    .foregroundStyle(RinkPalette.inkOnDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("PERCENTILES")
                    .font(RinkType.micro)
                    .tracking(0.6)
                    .foregroundStyle(RinkPalette.gold)
            }
        }
        .padding(RinkGeo.padPage)
        .background(RinkPalette.midnight)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("StatScout")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(RinkPalette.midnight)
            Spacer(minLength: 8)
            Text(footnote)
                .font(RinkType.small)
                .foregroundStyle(RinkPalette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, RinkGeo.padCard)
        .padding(.vertical, 12)
        .background(RinkPalette.surfaceAlt)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .top)
    }

    private var identityLine: String {
        [displayTeamFullName(player.team), positionAndHandedness(player)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// A current-season board moves through the season, so it carries its date. A past
    /// season is settled and just says what it is ranked against.
    private var footnote: String {
        guard isCurrentSeason else { return "Ranked against NHL qualifiers" }
        return "Through \(player.updatedAt.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

/// A rendered share card, handed to the share sheet as a PNG.
struct PlayerShareImage: Transferable {
    let png: Data
    let fileName: String

    var preview: Image {
        UIImage(data: png).map(Image.init(uiImage:)) ?? Image(systemName: "photo")
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.fileName }
    }

    @MainActor
    static func render(_ card: PlayerShareCard) -> PlayerShareImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let png = renderer.uiImage?.pngData() else { return nil }
        let slug = card.player.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return PlayerShareImage(png: png, fileName: "\(slug)-\(card.seasonLabel.replacingOccurrences(of: " ", with: "-")).png")
    }
}

enum StatScoutShare {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id\(AppStoreReviewLinks.appStoreID)")!

    static func message(for player: Player, seasonLabel: String) -> String {
        "\(player.name), \(seasonLabel) percentiles on StatScout \(appStoreURL.absoluteString)"
    }
}
