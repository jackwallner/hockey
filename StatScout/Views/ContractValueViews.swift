import SwiftUI

extension ContractValue {
    /// Green for outplaying the deal, rust for under it, ink in between.
    var tint: Color {
        switch verdict {
        case .bargain, .outplaying: return RinkPalette.performanceHigh
        case .fair: return RinkPalette.inkSecondary
        case .under, .overpaid: return RinkPalette.performanceLow
        }
    }
}

/// The Stats tab's Contract Value board: every qualified player at a position
/// ranked by production against pay. StatScout+, with the real leader shown
/// above the blur for everyone.
struct ContractValueBoard: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    let bindings: StatsBoardBindings
    @State private var showingBargains = true

    private var positions: [PlayerPositionGroup] { [.qb, .rb, .wr, .te] }

    private var rows: [(player: Player, value: ContractValue)] {
        viewModel.contractValueBoard(descending: showingBargains)
    }

    var body: some View {
        VStack(spacing: 0) {
            RinkTabs(
                tabs: positions.map(\.rawValue),
                selected: Binding(
                    get: { viewModel.selectedPosition.rawValue },
                    set: { raw in
                        if let next = positions.first(where: { $0.rawValue == raw }) {
                            viewModel.selectedPosition = next
                        }
                    }
                )
            )
            .padding(.top, 8)

            HStack(spacing: 8) {
                RinkSegmented(
                    segments: [
                        .init(value: true, label: "Bargains"),
                        .init(value: false, label: "Overpaid"),
                    ],
                    selection: $showingBargains
                )
                StatsViewMenu(viewModel: viewModel, board: bindings.$board)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, RinkGeo.controlRowGap)

            ScrollView {
                VStack(spacing: 0) {
                    board
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    footnote
                    Color.clear.frame(height: 88)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await viewModel.load() }
        }
        .onAppear {
            // The board has no defense yet (see `ContractValue.positions`).
            if !positions.contains(viewModel.selectedPosition) { viewModel.selectedPosition = .qb }
        }
    }

    @ViewBuilder
    private var board: some View {
        if viewModel.selectedSeason != viewModel.freeSeason || viewModel.selectedPhase != .regular {
            emptyState(
                title: "Current season only",
                detail: "Contract Value ranks this season's production against the contracts players are on now. Switch the season pill back to \(SeasonLabel.text(viewModel.freeSeason))."
            )
        } else if rows.isEmpty {
            emptyState(
                title: viewModel.profiles.isEmpty ? "Contracts loading" : "Not enough qualified players yet",
                detail: viewModel.profiles.isEmpty
                    ? "Contract data arrives with the next update. Pull to refresh."
                    : "Each position needs five qualified players with a contract before the board can rank them."
            )
        } else {
            VStack(spacing: 0) {
                header
                if let first = rows.first {
                    row(rank: 1, entry: first)
                }
                if store.isPro {
                    ForEach(Array(rows.dropFirst().enumerated()), id: \.element.player.id) { index, entry in
                        row(rank: index + 2, entry: entry)
                    }
                } else {
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.dropFirst().prefix(8).enumerated()), id: \.element.player.id) { index, entry in
                                row(rank: index + 2, entry: entry)
                            }
                        }
                        .blur(radius: 8)
                        .allowsHitTesting(false)
                        BlurGateUnlock(
                            headline: "See every bargain and overpay at every position",
                            trigger: .contractValue
                        )
                    }
                }
            }
            .background(RinkPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                    .stroke(RinkPalette.hairline, lineWidth: 0.5)
            )
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("RANK")
                .frame(width: 36, alignment: .leading)
            Text("PLAYER")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PAY / PLAY")
                .frame(width: 72, alignment: .trailing)
            Text("VALUE")
                .frame(width: 52, alignment: .trailing)
        }
        .font(RinkType.micro)
        .foregroundStyle(RinkPalette.inkTertiary)
        .frame(height: RinkGeo.rowHeightHeader)
        .padding(.horizontal, RinkGeo.padInline)
        .background(RinkPalette.surfaceAlt)
        .overlay(Rectangle().fill(RinkPalette.divider).frame(height: RinkGeo.hairline), alignment: .bottom)
    }

    private func row(rank: Int, entry: (player: Player, value: ContractValue)) -> some View {
        let contract = viewModel.profile(for: entry.player)?.contractLabel
        return NavigationLink(value: entry.player) {
            HStack(spacing: 0) {
                Text("\(rank)")
                    .font(RinkType.statSmall)
                    .foregroundStyle(RinkPalette.inkSecondary)
                    .frame(width: 36, alignment: .leading)
                    .monospacedDigit()
                HStack(spacing: 10) {
                    PlayerHeadshot(team: entry.player.team, initials: entry.player.initials, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.player.name)
                            .font(RinkType.bodyBold)
                            .foregroundStyle(RinkPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text([displayTeamAbbr(entry.player.team), contract].compactMap { $0 }.joined(separator: " · "))
                            .font(RinkType.micro)
                            .foregroundStyle(RinkPalette.inkTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(entry.value.payPercentile) / \(entry.value.productionPercentile)")
                    .font(RinkType.statSmall)
                    .foregroundStyle(RinkPalette.inkSecondary)
                    .monospacedDigit()
                    .frame(width: 72, alignment: .trailing)
                Text(entry.value.scoreLabel)
                    .font(RinkType.statMed)
                    .foregroundStyle(entry.value.tint)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(height: RinkGeo.rowHeight)
            .padding(.horizontal, RinkGeo.padInline)
            .background(rank % 2 == 1 ? RinkPalette.surface : RinkPalette.surfaceAlt)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(rank). \(entry.player.name), paid like the \(entry.value.payPercentile.ordinalString) percentile, producing like the \(entry.value.productionPercentile.ordinalString). Value \(entry.value.scoreLabel), \(entry.value.verdict.rawValue)"
            )
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        Text("Pay is each deal's yearly average as a share of the cap when it was signed; play is the player's average percentile on the stats he qualifies for. Both are ranked among qualified \(viewModel.selectedPosition.rawValue)s with a contract, and value is play minus pay. Contracts: OverTheCap via nflverse.")
            .font(RinkType.micro)
            .foregroundStyle(RinkPalette.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    private func emptyState(title: String, detail: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "dollarsign.circle")
        } description: {
            Text(detail)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
    }
}

/// The profile's Contract Value card: what he is paid, where that ranks, where
/// his production ranks, and the gap. Free.
struct ContractValueCard: View {
    let player: Player
    let profile: PlayerProfile
    let value: ContractValue?
    /// "Through Week 3", so an early verdict reads as provisional.
    var coverage: String?

    var body: some View {
        VStack(spacing: 0) {
            RinkSectionBar(
                title: "CONTRACT VALUE",
                trailing: value.map { value in
                    AnyView(
                        Text("\(value.scoreLabel) · \(value.verdict.rawValue)")
                            .font(RinkType.smallBold)
                            .foregroundStyle(value.tint)
                    )
                }
            )
            VStack(alignment: .leading, spacing: 10) {
                if let contract = contractLine {
                    Text(contract)
                        .font(RinkType.body)
                        .foregroundStyle(RinkPalette.ink)
                }
                if let value {
                    bar(label: "Pay", percentile: value.payPercentile, neutral: true)
                    bar(label: "Play", percentile: value.productionPercentile, neutral: false)
                    Text(explanation(value))
                        .font(RinkType.micro)
                        .foregroundStyle(RinkPalette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(unavailableReason)
                        .font(RinkType.small)
                        .foregroundStyle(RinkPalette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(RinkGeo.padCard)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RinkPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: RinkGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: RinkGeo.radiusCard)
                .stroke(RinkPalette.hairline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    /// "$42.2M/yr · 14.0% of cap · 4 yrs, signed 2026".
    private var contractLine: String? {
        guard let apy = profile.contractLabel else { return nil }
        var parts = [apy]
        if let share = profile.contractCapShare, share > 0 {
            parts.append(String(format: "%.1f%% of cap", share * 100))
        }
        if let years = profile.contractYears, let signed = profile.contractYearSigned {
            parts.append("\(years) yr\(years == 1 ? "" : "s"), signed \(signed)")
        }
        return parts.joined(separator: " · ")
    }

    private var unavailableReason: String {
        if profile.contractLabel == nil {
            return "No active contract on file."
        }
        if !ContractValue.positions.contains(player.positionGroup) {
            return "Value rankings cover offense for now. Defenders join once advanced defensive stats publish for the season."
        }
        return "Ranks once \(player.name) clears the playing-time minimum at his position."
    }

    private func explanation(_ value: ContractValue) -> String {
        let group = player.positionGroup.rawValue
        let through = coverage.map { " \($0)." } ?? "."
        return "Paid like the \(value.payPercentile.ordinalString) percentile \(group), producing like the \(value.productionPercentile.ordinalString), among \(value.poolSize) qualified \(group)s with a contract\(through) Contracts: OverTheCap via nflverse."
    }

    private func bar(label: String, percentile: Int, neutral: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(RinkType.smallBold)
                .foregroundStyle(RinkPalette.inkSecondary)
                .frame(width: 34, alignment: .leading)
            // Pay is drawn in ink: a high pay rank is a cost, not a strength.
            PercentileBarMini(percentile: percentile, height: 8, tint: neutral ? RinkPalette.inkTertiary : nil)
            Text(percentile.ordinal)
                .font(RinkType.statSmall)
                .foregroundStyle(neutral ? RinkPalette.inkSecondary : RinkPalette.textColor(forPercentile: percentile))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}
