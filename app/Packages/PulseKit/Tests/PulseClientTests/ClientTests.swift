import Foundation
import Testing
@testable import PulseClient

@Suite struct SSEParserTests {
    @Test func parsesEventsCommentsAndRetry() {
        var p = SSEParser()
        let lines = ["retry: 2000", "", ": ping", "", "event: snapshot", "data: {\"v\":1}", "", "data: a", "data: b", ""]
        let events = lines.compactMap { p.feed($0) }
        #expect(events == [.init(name: "snapshot", data: "{\"v\":1}"), .init(name: "message", data: "a\nb")])
        #expect(p.retry == 2000)
    }

    @Test func valueWithoutSpaceAndColonInData() {
        var p = SSEParser()
        _ = p.feed("data:http://x:1")
        #expect(p.feed("") == .init(name: "message", data: "http://x:1"))
    }
}

@Suite struct ServerConfigTests {
    @Test func normalizesAddress() {
        #expect(ServerConfig(address: "macmini-server.taild883a6.ts.net:9123", token: "").baseURL?.absoluteString
            == "https://macmini-server.taild883a6.ts.net:9123")
        #expect(ServerConfig(address: " https://host:9123/ ", token: "").baseURL?.absoluteString == "https://host:9123")
        #expect(ServerConfig(address: "http://127.0.0.1:9123", token: "").baseURL != nil)
        #expect(ServerConfig(address: "ftp://host", token: "").baseURL == nil)
        #expect(ServerConfig(address: "", token: "").baseURL == nil)
    }

    @Test func rejectsUnsupportedSchema() {
        #expect(throws: AgentError.unsupportedVersion(2)) {
            try AgentClient.decode(Data(#"{"v":2}"#.utf8))
        }
    }
}

@Suite struct TokenStoreTests {
    @Test func roundTripsWithPrivatePermissions() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pulse-\(UUID().uuidString)/token")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try TokenStore.save("secret-token\n", at: url)
        #expect(TokenStore.load(at: url) == "secret-token")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        try TokenStore.save("", at: url)
        #expect(TokenStore.load(at: url) == nil)
    }
}
