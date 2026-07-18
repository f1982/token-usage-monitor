import XCTest

final class CodexAppServerUsageProviderTests: XCTestCase {
    func testParsesCurrentAccountRateLimitResponse() {
        let response = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1784954930},"secondary":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1784954930},"secondary":null}}}}
        """

        let limits = CodexAppServerUsageProvider.limits(fromResponseLine: response)

        XCTAssertEqual(limits.count, 1)
        guard let limit = limits.first else { return }
        XCTAssertEqual(limit.label, "Codex weekly")
        XCTAssertEqual(limit.percent, 1)
        XCTAssertEqual(limit.resetsAt, Date(timeIntervalSince1970: 1_784_954_930))
    }

    func testPrefersMultiBucketResponseAndLabelsScopedLimits() {
        let response = """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":10,"windowDurationMins":10080}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":10,"windowDurationMins":10080}},"spark":{"limitId":"spark","limitName":"Codex Spark","primary":{"usedPercent":25,"windowDurationMins":300}}}}}
        """

        let limits = CodexAppServerUsageProvider.limits(fromResponseLine: response)

        XCTAssertEqual(limits.map(\.label), ["Codex weekly", "Codex Spark 5h"])
        XCTAssertEqual(limits.map(\.percent), [10, 25])
    }

    func testIgnoresUnrelatedAppServerMessage() {
        let response = #"{"id":1,"result":{"userAgent":"codex_cli_rs"}}"#

        XCTAssertTrue(CodexAppServerUsageProvider.limits(fromResponseLine: response).isEmpty)
    }

    func testFetchesThroughAppServerProcess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAppServerUsageProviderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        try """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *rateLimits*read*)
              echo '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1784954930},"secondary":null},"rateLimitsByLimitId":null}}'
              ;;
          esac
        done
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let provider = CodexAppServerUsageProvider(executableURL: { executable }, timeout: 2)

        let limits = await provider.fetchCodexLimits()

        XCTAssertEqual(limits.map(\.percent), [2])
    }
}
