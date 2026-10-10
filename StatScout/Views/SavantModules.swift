import SwiftUI

private func positionAndHandedness(_ player: Player) -> String {
    let pos = player.displayPosition.trimmingCharacters(in: .whitespaces)
    let hand = player.handedness.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
    if pos.isEmpty && hand.isEmpty { return "" }
    if hand.isEmpty { return pos }
    if pos.isEmpty { return hand }
    return "\(pos) · \(hand)"
}

private func displayTeamFullName(_ abbr: String) -> String {
    let trimmed = abbr.trimmingCharacters(in: .whitespaces).uppercased()
    if trimmed.isEmpty || trimmed == "TBD" || trimmed == "\u{2014}" || trimmed == "-" {
        return "Free Agent"
    }
    return teamFullName(abbr)
}

// MARK: - Module 1: Player Identity Strip

struct PlayerIdentityStrip: View {
    let player: Player
    var showOverallBadge: Bool = false
    /// Bio from `player_profiles`; nil keeps the strip to team and position.
    var profile: PlayerProfile? = nil

    /// `#97 · C · 28 yrs · 6'1", 196 lb`.
    private var bioLine: String {
        guard let profile else { return positionAndHandedness(player) }
        return [
            profile.jersey.map { "#\($0)" },
            player.displayPosition,
            profile.age().map { "\($0) yrs" },
            profile.sizeLabel,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// "Richmond Hill, ON, CAN · 2015 R1 #1".
    private var originLine: String? {
        guard let profile else { return nil }
        let parts = [profile.birthplace, profile.draftLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PlayerHeadshot(team: player.team, initials: player.initials, size: 72)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(RinkType.playerName)
                    .foregroundStyle(RinkPalette.inkOnDark)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(displayTeamFullName(player.team))
                    .font(RinkType.bodyBold)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(bioLine)
                    .font(RinkType.small)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let originLine {
                    Text(originLine)
                        .font(RinkType.small)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 8)
            if showOverallBadge {
                OverallPercentileBadge(percentile: player.overallPercentile)
            }
        }
        .padding(.horizontal, RinkGeo.padPage)
        .padding(.vertical, RinkGeo.padPage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RinkPalette.midnight)
    }
}

struct TeamIdentityStrip: View {
    let team: String
    var season: Int? = nil

    private var normalizedTeam: String {
        normalizedTeamAbbreviation(team)
    }

    private var seasonLabel: String {
        SeasonLabel.display(season ?? StatScoutSeason.current) + " Season"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(TeamColor.color(normalizedTeam))
                    .frame(width: 56, height: 56)
                Text(normalizedTeam)
                    .font(RinkType.pageTitle)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(teamFullName(normalizedTeam))
                    .font(RinkType.playerName)
                    .foregroundStyle(RinkPalette.inkOnDark)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(seasonLabel)
                    .font(RinkType.small)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, RinkGeo.padPage)
        .padding(.vertical, RinkGeo.padPage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RinkPalette.midnight)
    }
}

// MARK: - Module 3: Section Bar

struct RinkSectionBar: View {
    let title: String
    var trailing: AnyView? = nil

    /// Capitals, except the stat's own spelling: "xG RACE", not "XG RACE".
    static func caps(_ title: String) -> String {
        title.uppercased().replacingOccurrences(of: #"\bXG\b"#, with: "xG", options: .regularExpression)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(Self.caps(title))
                .font(RinkType.sectionTitle)
                .foregroundStyle(RinkPalette.ink)
                .padding(.leading, RinkGeo.padCard)
            Spacer()
            if let trailing { trailing.padding(.trailing, 12) }
        }
        .frame(height: RinkGeo.rowHeightHeader)
        .background(RinkPalette.surfaceSunk)
    }
}

struct RinkSubSectionBar: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = RinkPalette.inkSecondary

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(RinkType.micro)
                .foregroundStyle(RinkPalette.inkSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(RinkType.statSmall)
                    .foregroundStyle(trailingColor)
            }
        }
        .frame(height: 26)
        .padding(.horizontal, RinkGeo.padCard)
        .background(RinkPalette.surfaceAlt)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: 0.5), alignment: .bottom)
    }
}

// MARK: - Module 5: Tab Bar

struct RinkTabs: View {
    let tabs: [String]
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button(action: {
                    selected = tab
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    VStack(spacing: 0) {
                        Text(tab.uppercased())
                            .font(RinkType.smallBold)
                            .foregroundStyle(selected == tab ? RinkPalette.ink : RinkPalette.inkTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                        Rectangle()
                            .fill(selected == tab ? RinkPalette.turf : Color.clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(RinkPalette.surface)
        .overlay(Rectangle().fill(RinkPalette.hairline).frame(height: RinkGeo.hairline), alignment: .bottom)
    }
}

/// The three cohort tabs, equal width: Forwards, Defensemen, Goalies.
struct PositionTabs: View {
    @Binding var selection: PlayerPositionGroup

    var body: some View {
        RinkTabs(
            tabs: PlayerPositionGroup.allCases.map(\.displayName),
            selected: Binding(
                get: { selection.displayName },
                set: { name in
                    guard let position = PlayerPositionGroup.allCases.first(where: { $0.displayName == name }) else { return }
                    selection = position
                }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Position")
    }
}
