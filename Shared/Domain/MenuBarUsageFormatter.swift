import Foundation

enum MenuBarUsageFormatter {
    struct Item: Identifiable {
        let id: String
        let name: String
        let detail: String
    }

    static func label(
        snapshot: ClaudeUsageSnapshot?,
        codexSession: CodexActiveSession?,
        visibleSources: Set<UsageDisplaySource>
    ) -> String {
        let items = values(snapshot: snapshot, codexSession: codexSession, visibleSources: visibleSources)
        guard !items.isEmpty else { return "Usage —" }
        return items.map { "\($0.shortName) \($0.detail)" }.joined(separator: " · ")
    }

    static func values(
        snapshot: ClaudeUsageSnapshot?,
        codexSession: CodexActiveSession?,
        visibleSources: Set<UsageDisplaySource>
    ) -> [Item] {
        var items: [Item] = []

        if visibleSources.contains(.claudeCode), let percent = snapshot?.session?.percent {
            items.append(Item(
                id: "claude",
                name: "Claude Code",
                detail: "Session \(UsageDisplayFormatting.shortPercentText(percent)) used"
            ))
        }

        if visibleSources.contains(.codex), let codexSession {
            if let totalTokens = codexSession.totalTokens,
               let contextWindow = codexSession.contextWindow,
               contextWindow > 0 {
                let percent = codexSession.contextUsagePercent ?? 0
                items.append(Item(
                    id: "codex",
                    name: "Codex",
                    detail: "\(UsageDisplayFormatting.compactTokenText(totalTokens))/\(UsageDisplayFormatting.compactTokenText(contextWindow)) (\(UsageDisplayFormatting.shortPercentText(percent)))"
                ))
            } else if let quota = snapshot?.codex.first {
                items.append(Item(
                    id: "codex",
                    name: "Codex",
                    detail: "Quota \(UsageDisplayFormatting.shortPercentText(quota.percent)) used"
                ))
            }
        }

        return items
    }
}

private extension MenuBarUsageFormatter.Item {
    var shortName: String { id == "claude" ? "Cl" : "Cx" }
}
