import Foundation

/// Reads the account-level quota snapshot exposed by Codex app-server. This is
/// preferred over session telemetry because it requests current account state
/// even when no Codex conversation is actively writing a JSONL file.
struct CodexAppServerUsageProvider: CodexUsageProviding {
    var executableURL: () -> URL?
    private let timeout: TimeInterval

    init(
        executableURL: @escaping () -> URL? = CodexExecutableLocator.locate,
        timeout: TimeInterval = 5
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func fetchCodexLimits() async -> [UsageLimit] {
        guard let executable = executableURL(),
              let response = await CodexAppServerClient(timeout: timeout)
                .fetchRateLimits(using: executable) else {
            return []
        }
        return Self.limits(fromResponseLine: response)
    }

    static func limits(fromResponseLine line: String) -> [UsageLimit] {
        guard let data = line.data(using: .utf8),
              let response = try? JSONDecoder().decode(AppServerResponse.self, from: data),
              response.id == CodexAppServerClient.rateLimitsRequestID,
              let result = response.result else {
            return []
        }

        if let buckets = result.rateLimitsByLimitID, !buckets.isEmpty {
            let snapshots = buckets.sorted(by: { $0.key < $1.key }).map { key, value in
                var snapshot = value
                if snapshot.limitID == nil { snapshot.limitID = key }
                return snapshot
            }
            let limits = CodexUsageLimitMapper.limits(from: snapshots)
            if !limits.isEmpty { return limits }
        }
        return CodexUsageLimitMapper.limits(from: [result.rateLimits])
    }
}

/// Tries providers in authority order and stops at the first usable snapshot.
struct FallbackCodexUsageProvider: CodexUsageProviding {
    var providers: [CodexUsageProviding]

    func fetchCodexLimits() async -> [UsageLimit] {
        for provider in providers {
            let limits = await provider.fetchCodexLimits()
            if !limits.isEmpty { return limits }
        }
        return []
    }
}

private struct AppServerResponse: Decodable {
    var id: Int
    var result: Result?

    struct Result: Decodable {
        var rateLimits: CodexRateLimitSnapshot
        var rateLimitsByLimitID: [String: CodexRateLimitSnapshot]?

        enum CodingKeys: String, CodingKey {
            case rateLimits
            case rateLimitsByLimitID = "rateLimitsByLimitId"
        }
    }
}

private enum CodexExecutableLocator {
    static func locate() -> URL? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []

        if let explicitPath = environment["CODEX_EXECUTABLE"] {
            candidates.append(URL(fileURLWithPath: explicitPath))
        }
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
            }
        }

        let home = fileManager.homeDirectoryForCurrentUser
        candidates += [
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]

        let nvmVersions = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fileManager.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates += versions
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin/codex") }
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

private final class CodexAppServerClient: @unchecked Sendable {
    static let rateLimitsRequestID = 2

    private let timeout: TimeInterval
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var buffer = Data()
    private var process: Process?
    private var outputPipe: Pipe?

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func fetchRateLimits(using executableURL: URL) async -> String? {
        return await withCheckedContinuation { continuation in
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = ["app-server"]
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            lock.lock()
            self.continuation = continuation
            self.process = process
            self.outputPipe = outputPipe
            buffer.removeAll(keepingCapacity: true)
            lock.unlock()

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.receive(handle.availableData)
            }
            process.terminationHandler = { [weak self] _ in
                self?.finish(with: nil)
            }

            do {
                try process.run()
                try inputPipe.fileHandleForWriting.write(contentsOf: Self.requestData())
            } catch {
                finish(with: nil)
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else {
            finish(with: nil)
            return
        }

        lock.lock()
        buffer.append(data)
        var response: String?
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any],
                  (object["id"] as? NSNumber)?.intValue == Self.rateLimitsRequestID else {
                continue
            }
            response = String(data: lineData, encoding: .utf8)
            break
        }
        lock.unlock()

        if let response { finish(with: response) }
    }

    private func finish(with response: String?) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let process = self.process
        let outputPipe = self.outputPipe
        self.process = nil
        self.outputPipe = nil
        lock.unlock()

        continuation.resume(returning: response)
        // `finish` may be called by the readability handler itself. Clean up
        // on another queue so removing that handler cannot wait on itself.
        DispatchQueue.global(qos: .utility).async {
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            if process?.isRunning == true { process?.terminate() }
        }
    }

    private static func requestData() -> Data {
        let requests: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "token_usage_monitor",
                        "title": "Token Usage Monitor",
                        "version": "1.0",
                    ],
                ],
            ],
            ["method": "initialized", "params": [:]],
            ["method": "account/rateLimits/read", "id": rateLimitsRequestID, "params": NSNull()],
        ]
        let lines = requests.compactMap { request -> String? in
            guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}
