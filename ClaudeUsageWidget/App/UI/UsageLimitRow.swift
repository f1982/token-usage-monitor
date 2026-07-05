import SwiftUI

struct UsageLimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label)
                    .font(.headline)
                Spacer()
                Text(UsageDisplayFormatting.percentText(limit.percent))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: UsageDisplayFormatting.clampedPercent(limit.percent), total: 100)
            if let resetText = UsageDisplayFormatting.resetText(for: limit.resetsAt) {
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
