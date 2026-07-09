import Combine
import Foundation

/// Polls the newest Codex session at a deliberately modest cadence.
@MainActor
final class CodexSessionMonitor: ObservableObject {
    static let pollInterval: TimeInterval = 10

    @Published private(set) var session: CodexActiveSession?

    private let provider: CodexActiveSessionProviding

    init(provider: CodexActiveSessionProviding) {
        self.provider = provider
    }

    func start() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: .seconds(Self.pollInterval))
            } catch {
                return
            }
        }
    }

    func refresh() async {
        session = await provider.fetchActiveSession()
    }
}
