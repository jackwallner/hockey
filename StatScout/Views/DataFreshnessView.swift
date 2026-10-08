import SwiftUI

/// One quiet caption that says what the numbers on screen include and how old
/// they are, e.g. "Through Oct 7 · 33 games · Updated 2h ago".
///
/// It used to be a bordered card with a status icon, two or three lines of copy
/// and a Refresh button, repeated at the top of every board. That is a lot of
/// chrome for "your data is fine", which is the answer almost every time. The
/// caption stays one line; only a real problem (offline, a failed check, games
/// still missing) earns an icon and colour. Pull to refresh already exists on
/// every screen that shows it, and tapping the caption does the same.
struct DataFreshnessView: View {
    @Bindable var viewModel: DashboardViewModel
    /// The shared status currently describes the live regular-season dataset.
    /// Hide it for historical and playoff scopes rather than borrowing a
    /// coverage label from another set of numbers.
    var season: Int? = nil
    var phase: SeasonPhase? = nil
    /// Kept for call-site compatibility. The caption itself is the refresh
    /// control now, so there is no separate button to hide.
    var showRefreshButton = true

    private var freshness: DataFreshness? { viewModel.freshnessForDisplay }

    private var status: DataFreshnessStatus {
        let raw = viewModel.freshnessStatus
        // Every game is in and only optional enrichment (PFR or Next Gen) is
        // late. That is a normal mid-week state, not something to flag.
        if raw == .partial, !isWaitingOnGames { return .ready }
        return raw
    }

    private var isWaitingOnGames: Bool {
        guard let coverage = freshness?.coverage,
              let expected = coverage.expectedGames,
              let included = coverage.gamesIncluded else { return false }
        return included < expected
    }

    private var isCurrentScope: Bool {
        guard let season else { return true }
        guard season == viewModel.freeSeason else { return false }
        guard let phase else { return true }
        return phase == .regular
    }

    var body: some View {
        if isCurrentScope {
            // Re-render once a minute so "Updated 4m ago" does not freeze.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                caption(now: context.date)
            }
        }
    }

    private func caption(now: Date) -> some View {
        Button {
            Task { await viewModel.load() }
        } label: {
            HStack(spacing: 5) {
                if let problemIcon {
                    Image(systemName: problemIcon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(text(now: now))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer(minLength: 0)
            }
            .font(RinkType.micro)
            .foregroundStyle(problemIcon == nil ? RinkPalette.inkTertiary : RinkPalette.performanceLow)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRefreshing)
        .accessibilityLabel(accessibilityText(now: now))
        .accessibilityHint("Checks for new game data")
    }

    private var problemIcon: String? {
        switch status {
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        case .stale: "arrow.clockwise"
        case .ready, .checking, .pending, .partial: nil
        }
    }

    private func text(now: Date) -> String {
        switch status {
        case .offline:
            return "Offline · Showing saved stats"
        case .failed:
            return "Couldn't update · Showing saved stats"
        case .stale:
            return "Newer stats available · Tap to load"
        case .checking where coverageText == nil:
            return "Checking for new stats"
        case .ready, .checking, .pending, .partial:
            let parts = [coverageText, updatedText(now: now)].compactMap { $0 }
            return parts.isEmpty ? "Checking for new stats" : parts.joined(separator: " · ")
        }
    }

    /// "Through Oct 7 · 33 games", or "... · 12 of 14 games in" while a slate is
    /// still arriving.
    private var coverageText: String? {
        guard let coverage = freshness?.coverage ?? viewModel.dataCoverage else { return nil }
        var parts: [String] = []
        // "Through": the game count after it is cumulative, and "Oct 7 ·
        // 33 games" read as thirty-three games on Oct 7.
        parts.append("Through \(coverage.asOf.formatted(DataCoverage.gameDayStyle))")
        if let included = coverage.gamesIncluded {
            if let expected = coverage.expectedGames, included < expected {
                parts.append("\(included) of \(expected) games in")
            } else {
                parts.append(included == 1 ? "1 game" : "\(included) games")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// When the numbers last changed, which is what a fan means by "updated".
    /// Falls back to the last check before the first published revision.
    private func updatedText(now: Date) -> String? {
        guard let date = freshness?.publishedAt ?? viewModel.lastCheckedAt else { return nil }
        return "Updated \(Self.shortAge(of: date, now: now))"
    }

    static func shortAge(of date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3_600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3_600))h ago"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func accessibilityText(now: Date) -> String {
        text(now: now)
            .replacingOccurrences(of: " · ", with: ", ")
            .replacingOccurrences(of: "m ago", with: " minutes ago")
            .replacingOccurrences(of: "h ago", with: " hours ago")
    }
}

#if DEBUG
#Preview {
    DataFreshnessView(viewModel: DashboardViewModel())
        .padding()
        .background(RinkPalette.canvas)
}
#endif
