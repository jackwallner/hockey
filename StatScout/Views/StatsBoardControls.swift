import SwiftUI

/// Which league-wide board the Stats tab is drawing.
enum StatsBoard: String, Hashable {
    case advanced
    case standard
    case bestWorst
}

/// Traditional production stats offered for each position group. The labels
/// are the `standard_stats` labels in the hockey contract.
enum StandardStatCatalog {
    static func stats(for position: PlayerPositionGroup) -> [String] {
        switch position {
        case .forward, .defense:
            return ["P", "G", "A", "+/-", "PIM", "PPG", "PPP", "SHG", "GWG", "SOG", "Sh%", "TOI/GP", "Hits", "Blk", "FO%", "GP"]
        case .goalie:
            return ["SV%", "GAA", "W", "L", "OT", "SO", "SV", "SA", "GS", "GP"]
        }
    }

    /// Stats where a lower number is the better one.
    private static let lowerIsBetter: Set<String> = ["GAA", "PIM", "L", "OT"]

    static func defaultDescending(for stat: String, position: PlayerPositionGroup) -> Bool {
        !lowerIsBetter.contains(stat)
    }

    static func defaultStat(for position: PlayerPositionGroup) -> String {
        stats(for: position).first ?? "GP"
    }

    /// The stat to show after the position tab changes.
    ///
    /// A stat the user picked on purpose follows them to any position that
    /// offers it. The previous position's own default does not: it is not a
    /// choice, and carrying it over would rank goalies by points after a walk
    /// through the tabs.
    static func stat(
        keeping current: String,
        from old: PlayerPositionGroup,
        to new: PlayerPositionGroup
    ) -> String {
        if current != defaultStat(for: old), stats(for: new).contains(current) {
            return current
        }
        return defaultStat(for: new)
    }
}

/// The one control used everywhere to choose which statistic a board ranks.
struct StatPickerMenu: View {
    struct Option: Identifiable {
        let id: String
        let label: String
        var isSelected = false
    }

    var advanced: [Option] = []
    var standard: [Option] = []
    let activeLabel: String
    var onSelectAdvanced: (Option) -> Void = { _ in }
    var onSelectStandard: (Option) -> Void = { _ in }

    var body: some View {
        Menu {
            if !advanced.isEmpty {
                Section("Advanced") {
                    rows(advanced, select: onSelectAdvanced)
                }
            }
            if !standard.isEmpty {
                Section("Standard") {
                    rows(standard, select: onSelectStandard)
                }
            }
        } label: {
            RinkInlinePill(systemImage: "chart.bar.fill", title: activeLabel)
        }
        .menuOrder(.fixed)
        .rinkMenuAppearance()
        .accessibilityLabel("Stat")
        .accessibilityValue(activeLabel)
    }

    private func rows(
        _ options: [Option],
        select: @escaping (Option) -> Void
    ) -> some View {
        ForEach(options) { option in
            Button {
                select(option)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if option.isSelected {
                    Label(option.label, systemImage: "checkmark")
                } else {
                    Text(option.label)
                }
            }
        }
    }
}

/// Compact direction toggle that sits beside the shared stat picker.
struct SortDirectionButton: View {
    let descending: Bool
    let statLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            RinkChip(trailing: .sortArrow(descending: descending))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort direction")
        .accessibilityValue("\(statLabel), \(descending ? "highest first" : "lowest first")")
        .accessibilityHint("Tap to flip sort direction")
    }
}

/// Shared state owned by `StatsView` and passed into either leaderboard.
struct StatsBoardBindings {
    @Binding var board: StatsBoard
    @Binding var standardStat: String
    @Binding var standardSortDescending: Bool
}

/// Picking a statistic also selects the vocabulary that owns it.
struct StatsBoardStatPicker: View {
    @Bindable var viewModel: DashboardViewModel
    let bindings: StatsBoardBindings

    private var position: PlayerPositionGroup { viewModel.selectedPosition }

    private var activeLabel: String {
        switch bindings.board {
        case .advanced:
            return viewModel.currentSortMetric ?? viewModel.sortLabel
        case .standard:
            return bindings.standardStat
        case .bestWorst:
            return "Best & Worst"
        }
    }

    var body: some View {
        StatPickerMenu(
            advanced: viewModel.availableAdvancedSortMetrics.map { metric in
                .init(
                    id: metric,
                    label: metric,
                    isSelected: bindings.board == .advanced
                        && metric == viewModel.currentSortMetric
                )
            },
            standard: StandardStatCatalog.stats(for: position).map { stat in
                .init(
                    id: stat,
                    label: stat,
                    isSelected: bindings.board == .standard
                        && stat == bindings.standardStat
                )
            },
            activeLabel: activeLabel,
            onSelectAdvanced: { option in
                bindings.board = .advanced
                viewModel.setUserSortMetric(option.id)
            },
            onSelectStandard: { option in
                bindings.board = .standard
                bindings.standardStat = option.id
                bindings.standardSortDescending = StandardStatCatalog.defaultDescending(
                    for: option.id,
                    position: position
                )
            }
        )
    }
}

/// Secondary board options. Position stays in the persistent tab row, while
/// qualification and Best & Worst live here.
struct StatsViewMenu: View {
    @EnvironmentObject private var store: StoreService
    @Bindable var viewModel: DashboardViewModel
    @Binding var board: StatsBoard

    private var isActive: Bool {
        viewModel.qualifierLevel != .all
            || viewModel.selectedConference != .all
            || board == .bestWorst
    }

    var body: some View {
        Menu {
            conferenceSection
            qualifierSection
            boardSection
        } label: {
            RinkChip(
                title: "View",
                systemImage: "slider.horizontal.3",
                trailing: .chevron,
                isActive: isActive
            )
        }
        .menuOrder(.fixed)
        .accessibilityLabel("View options")
    }

    private var conferenceSection: some View {
        Section("Conference") {
            ForEach(LeagueConference.allCases) { conference in
                Button {
                    viewModel.selectedConference = conference
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if conference == viewModel.selectedConference {
                        Label(conference.rawValue, systemImage: "checkmark")
                    } else {
                        Text(conference.rawValue)
                    }
                }
            }
        }
    }

    private var qualifierSection: some View {
        Section("Qualifier") {
            ForEach(DashboardViewModel.QualifierLevel.allCases) { level in
                Button {
                    viewModel.qualifierLevel = level
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    let title = "\(level.rawValue) · \(level.description)"
                    if level == viewModel.qualifierLevel {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        }
    }

    private var boardSection: some View {
        Section("Show") {
            Button {
                if board == .bestWorst { board = .advanced }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if board != .bestWorst {
                    Label("Leaderboard", systemImage: "checkmark")
                } else {
                    Text("Leaderboard")
                }
            }

            Button {
                board = .bestWorst
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                if board == .bestWorst {
                    Label("Best & Worst", systemImage: "checkmark")
                } else if store.isPro {
                    Text("Best & Worst")
                } else {
                    Label("Best & Worst (StatScout+)", systemImage: "crown.fill")
                }
            }
        }
    }
}
