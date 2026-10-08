import SwiftUI

/// A visually rich preview of the Year Comparison feature, shown to free users.
/// Uses mock data that mimics the real YearComparisonView layout with a blur overlay + CTA.
struct YearComparePreview: View {
    @EnvironmentObject private var store: StoreService
    let playerName: String
    let onUnlock: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Mock comparison content stays visible (blurred) as the hook.
            mockContent
                .blur(radius: 5)
                .clipped()

            BlurGateUnlock(
                headline: "See how \(playerName) evolved season to season",
                trigger: .yearCompare
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - Mock Content (looks like the real YearComparisonView)

    private var mockContent: some View {
        VStack(spacing: 12) {
            // Mock year picker
            mockYearPicker

            // Mock aggregate comparison
            mockCategoryCard
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var mockYearPicker: some View {
        HStack(spacing: 12) {
            mockYearButton(label: "2026", subtitle: "Recent")
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GridironPalette.inkTertiary)
            mockYearButton(label: "2025", subtitle: "Prior")
        }
        .padding(16)
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private func mockYearButton(label: String, subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(GridironType.statLarge)
                .foregroundStyle(GridironPalette.ink)
            Text(subtitle)
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(GridironPalette.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
    }

    private var mockCategoryCard: some View {
        VStack(spacing: 0) {
            GridironSubSectionBar(title: "SEASON TOTALS")
            mockHeader

            mockRow(label: "Cmp/Att", priorVal: "348/530", recentVal: "385/566")
            mockRow(label: "Pass Yds", priorVal: "3,650", recentVal: "4,180")
            mockRow(label: "Pass TD", priorVal: "24", recentVal: "34")
            mockRow(label: "Rush Yds", priorVal: "285", recentVal: "412")
        }
        .background(GridironPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: GridironGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: GridironGeo.radiusCard)
                .stroke(GridironPalette.hairline, lineWidth: 0.5)
        )
    }

    private var mockHeader: some View {
        HStack(spacing: 0) {
            Text("STAT")
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("2025")
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkSecondary)
                .frame(width: 72)
            Text("2026")
                .font(GridironType.micro)
                .foregroundStyle(GridironPalette.inkSecondary)
                .frame(width: 72)
        }
        .padding(.horizontal, GridironGeo.padInline)
        .frame(height: 28)
        .background(GridironPalette.surfaceAlt)
    }

    private func mockRow(
        label: String,
        priorVal: String,
        recentVal: String
    ) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(GridironType.body)
                .foregroundStyle(GridironPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            mockYearValue(value: priorVal, isFaded: true)
                .frame(width: 72)

            mockYearValue(value: recentVal, isFaded: false)
                .frame(width: 72)
        }
        .frame(height: 48)
        .padding(.horizontal, GridironGeo.padInline)
        .background(GridironPalette.surface)
        .overlay(
            Rectangle()
                .fill(GridironPalette.divider)
                .frame(height: GridironGeo.hairline),
            alignment: .bottom
        )
    }

    private func mockYearValue(value: String, isFaded: Bool) -> some View {
        Text(value)
            .font(GridironType.statSmall)
            .foregroundStyle(isFaded ? GridironPalette.inkTertiary : GridironPalette.turf)
            .lineLimit(1)
    }
}

#Preview {
    YearComparePreview(playerName: "Shohei Ohtani", onUnlock: {})
        .environmentObject(StoreService.shared)
}
