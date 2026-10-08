import SwiftUI

struct YearComparisonView: View {
    let history: [Player]
    @State private var yearA: Int = 0
    @State private var yearB: Int = 0

    // yearA is the later (more recent) year, yearB is the earlier year
    private var recentYear: Int { max(yearA, yearB) }
    private var priorYear: Int { min(yearA, yearB) }

    private var availableYears: [Int] {
        history.compactMap(\.season).uniqued().sorted(by: >)
    }

    private var playerYearA: Player? {
        history.first { $0.season == recentYear }
    }

    private var playerYearB: Player? {
        history.first { $0.season == priorYear }
    }

    var body: some View {
        VStack(spacing: 12) {
            yearPickerCard

            if let p1 = playerYearA, let p2 = playerYearB {
                comparisonContent(p1: p1, p2: p2)
            } else {
                noDataView
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .onAppear(perform: snapSelections)
    }

    private func snapSelections() {
        let years = availableYears
        guard !years.isEmpty else { return }
        if !years.contains(yearA) { yearA = years.first ?? 0 }
        if !years.contains(yearB) || yearB == yearA {
            yearB = years.first(where: { $0 != yearA }) ?? yearB
        }
    }

    private var noDataView: some View {
        ContentUnavailableView {
            Label("No Data Available", systemImage: "calendar.badge.clock")
        } description: {
            Text(availableYears.isEmpty
                 ? "No historical data is available for this player."
                 : "Data for \(String(recentYear)) or \(String(priorYear)) is not available.")
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Year Picker Card

    private var yearPickerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                yearButton(year: $yearB, otherYear: yearA, label: yearB > 0 ? String(yearB) : "Select")
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GridironPalette.inkTertiary)
                yearButton(year: $yearA, otherYear: yearB, label: yearA > 0 ? String(yearA) : "Select")
            }
        }
        .padding(16)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private func yearButton(year: Binding<Int>, otherYear: Int, label: String) -> some View {
        Menu {
            ForEach(availableYears.filter { $0 != otherYear }, id: \.self) { y in
                Button {
                    year.wrappedValue = y
                } label: {
                    HStack {
                        Text(String(y))
                        if year.wrappedValue == y {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(GridironType.statLarge)
                    .foregroundStyle(GridironPalette.ink)
                Text(year.wrappedValue == recentYear ? "Recent" : "Prior")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(GridironPalette.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
            .overlay(
                HStack {
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GridironPalette.inkTertiary)
                        .padding(.trailing, 8)
                },
                alignment: .trailing
            )
        }
    }

    // MARK: - Comparison Content

    private func comparisonContent(p1: Player, p2: Player) -> some View {
        let comparisons = buildComparisons(p1: p1, p2: p2)
        let grouped = Dictionary(grouping: comparisons) { $0.category }
        let standard = buildStandardComparisons(p1: p1, p2: p2)

        if comparisons.isEmpty && standard.isEmpty {
            return AnyView(noMetricsView)
        }

        return AnyView(
            LazyVStack(spacing: 12) {
                if !standard.isEmpty {
                    standardStatsCard(items: standard)
                }
                ForEach(MetricCategory.allCases, id: \.self) { category in
                    if let items = grouped[category], !items.isEmpty {
                        categoryCard(category: category, items: items)
                    }
                }
            }
        )
    }

    private var noMetricsView: some View {
        ContentUnavailableView {
            Label("No Comparable Metrics", systemImage: "chart.bar.xaxis")
        } description: {
            Text("These seasons don't have overlapping standard or advanced stats.")
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Category Card

    private func categoryCard(category: MetricCategory, items: [MetricComparison]) -> some View {
        VStack(spacing: 0) {
            GridironSubSectionBar(title: "ADVANCED · " + category.rawValue.uppercased())

            columnHeader

            ForEach(Array(items.enumerated()), id: \.element.metricLabel) { idx, item in
                comparisonRow(item: item, isAlt: idx % 2 == 1)
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("STAT")
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(priorYear))
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkSecondary)
                .frame(width: 72)

            Text(String(recentYear))
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkSecondary)
                .frame(width: 72)

        }
        .padding(.horizontal, GridironGeo.padInline)
        .frame(height: 28)
        .background(GridironPalette.surfaceAlt)
    }

    private func comparisonRow(item: MetricComparison, isAlt: Bool) -> some View {
        return HStack(spacing: 0) {
            // Metric label
            Text(item.metricLabel)
                .font(GridironType.body)
                .foregroundStyle(GridironPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            // Prior year (earlier)
            yearValueColumn(
                percentile: item.percentileB,
                value: item.valueB,
                isWinner: item.percentileB > item.percentileA
            )
            .frame(width: 72)

            // Recent year (later) - emphasized with color
            yearValueColumn(
                percentile: item.percentileA,
                value: item.valueA,
                isWinner: item.percentileA > item.percentileB
            )
            .frame(width: 72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.metricLabel): \(priorYear) \(item.percentileB.ordinalString) percentile, "
                + "\(recentYear) \(item.percentileA.ordinalString) percentile"
        )
        .frame(height: 48)
        .padding(.horizontal, GridironGeo.padInline)
        .background(isAlt ? GridironPalette.surfaceAlt : GridironPalette.surface)
        .overlay(
            Rectangle()
                .fill(GridironPalette.divider)
                .frame(height: GridironGeo.hairline),
            alignment: .bottom
        )
    }

    private func yearValueColumn(percentile: Int, value: String, isWinner: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if isWinner {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.yellow)
                        .accessibilityHidden(true)
                }
                Text(value.isEmpty ? String(percentile) : value)
                    .font(GridironType.statSmall)
                    .foregroundStyle(isWinner ? GridironPalette.turf : GridironPalette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if value.isEmpty {
                Text("PCTL")
                    .font(GridironType.micro)
                    .foregroundStyle(GridironPalette.inkTertiary)
            }
        }
    }

    private func standardStatsCard(
        items: [(label: String, prior: String?, recent: String?)]
    ) -> some View {
        VStack(spacing: 0) {
            GridironSubSectionBar(title: "SEASON TOTALS")
            columnHeader
            ForEach(Array(items.enumerated()), id: \.element.label) { index, item in
                let winner = StandardStatSemantics.winner(
                    label: item.label,
                    left: item.prior,
                    right: item.recent
                )
                HStack(spacing: 0) {
                    Text(item.label)
                        .font(GridironType.body)
                        .foregroundStyle(GridironPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    rawValue(item.prior, isWinner: winner == .left)
                        .frame(width: 72)
                    rawValue(item.recent, isWinner: winner == .right)
                        .frame(width: 72)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    seasonRowAccessibilityLabel(
                        label: item.label,
                        prior: item.prior,
                        recent: item.recent,
                        winner: winner
                    )
                )
                .frame(height: 48)
                .padding(.horizontal, GridironGeo.padInline)
                .background(index.isMultiple(of: 2) ? GridironPalette.surface : GridironPalette.surfaceAlt)
                .overlay(
                    Rectangle()
                        .fill(GridironPalette.divider)
                        .frame(height: GridironGeo.hairline),
                    alignment: .bottom
                )
            }
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    /// Spoken form of one season-totals row. The trophy is decoration, so the
    /// better year is named here instead.
    private func seasonRowAccessibilityLabel(
        label: String,
        prior: String?,
        recent: String?,
        winner: StandardStatSemantics.Winner?
    ) -> String {
        var parts = [
            "\(label): \(priorYear) \(prior ?? "no data"), \(recentYear) \(recent ?? "no data")"
        ]
        switch winner {
        case .left: parts.append("\(priorYear) better")
        case .right: parts.append("\(recentYear) better")
        case nil: break
        }
        return parts.joined(separator: ", ")
    }

    private func rawValue(_ value: String?, isWinner: Bool) -> some View {
        HStack(spacing: 3) {
            if isWinner {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .accessibilityHidden(true)
            }
            Text(value ?? "-")
                .font(GridironType.statSmall)
                .foregroundStyle(
                    value == nil
                        ? GridironPalette.inkTertiary
                        : (isWinner ? GridironPalette.turf : GridironPalette.inkSecondary)
                )
                .monospacedDigit()
        }
    }

    // MARK: - Comparisons Builder

    private func buildComparisons(p1: Player, p2: Player) -> [MetricComparison] {
        let metrics1 = Dictionary(grouping: p1.metrics) { $0.label }
        let metrics2 = Dictionary(grouping: p2.metrics) { $0.label }
        let allLabels = Set(metrics1.keys).union(metrics2.keys)

        return allLabels.compactMap { label in
            guard let m1 = metrics1[label]?.first, let m2 = metrics2[label]?.first else { return nil }
            return MetricComparison(
                metricLabel: label,
                category: m1.category,
                percentileA: m1.percentile,
                percentileB: m2.percentile,
                valueA: m1.value,
                valueB: m2.value
            )
        }.sorted { a, b in
            a.category == b.category
                ? a.category.sortMetrics(a.metricLabel, b.metricLabel)
                : MetricCategory.allCases.firstIndex(of: a.category)! < MetricCategory.allCases.firstIndex(of: b.category)!
        }
    }

    private func buildStandardComparisons(
        p1: Player,
        p2: Player
    ) -> [(label: String, prior: String?, recent: String?)] {
        let recent = Dictionary(
            uniqueKeysWithValues: (p1.standardStats ?? []).map { ($0.label, $0.value) }
        )
        let prior = Dictionary(
            uniqueKeysWithValues: (p2.standardStats ?? []).map { ($0.label, $0.value) }
        )
        let preferredOrder = [
            "G", "Cmp/Att", "Pass Yds", "Pass TD", "INT",
            "Car", "Rush Yds", "Rush TD", "Rec/Tgt", "Rec Yds", "Rec TD",
            "Tackles", "Sacks", "Def INT",
        ]
        return Set(recent.keys).union(prior.keys)
            .sorted {
                let first = preferredOrder.firstIndex(of: $0) ?? preferredOrder.count
                let second = preferredOrder.firstIndex(of: $1) ?? preferredOrder.count
                return first == second ? $0 < $1 : first < second
            }
            .map {
                (label: $0, prior: prior[$0], recent: recent[$0])
            }
    }
}

private struct MetricComparison {
    let metricLabel: String
    let category: MetricCategory
    let percentileA: Int
    let percentileB: Int
    let valueA: String
    let valueB: String
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
