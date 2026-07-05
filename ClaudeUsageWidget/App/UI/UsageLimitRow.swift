import SwiftUI

struct UsageLimitRow: View {
    let limit: UsageLimit
    var style: UsageChartStyle = .progressBar

    var body: some View {
        UsageMeterView(limit: limit, style: style, compact: false, showReset: true)
    }
}
