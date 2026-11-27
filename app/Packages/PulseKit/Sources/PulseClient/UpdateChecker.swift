import Foundation
import PulseCore

/// A published GitHub release of Pulse.
public struct ReleaseInfo: Sendable, Equatable {
    public let version: AppVersion
    public let tag: String
    public let pageURL: URL
    /// The macOS disk image, when the release has one.
    public let downloadURL: URL?
}

public enum UpdateError: Error, Equatable {
    case noRelease
    case http(Int)
    case malformed
}

/// Asks GitHub for the latest release. No account, no token: the public API
/// allows 60 requests an hour per address and Pulse makes one a day.
public enum UpdateChecker {
    public static let latestURL = URL(string: "https://api.github.com/repos/kutluhangil/Pulse/releases/latest")!

    public static func latest(session: URLSession = .shared) async throws -> ReleaseInfo {
        var req = URLRequest(url: latestURL, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Pulse-macOS", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: return try parse(data)
        case 404: throw UpdateError.noRelease
        default: throw UpdateError.http(code)
        }
    }

    public static func parse(_ data: Data) throws -> ReleaseInfo {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
        struct Release: Decodable {
            let tagName: String
            let htmlUrl: URL
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let r = try? decoder.decode(Release.self, from: data), let version = AppVersion(r.tagName) else {
            throw UpdateError.malformed
        }
        let dmg = r.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return ReleaseInfo(version: version, tag: r.tagName, pageURL: r.htmlUrl, downloadURL: dmg?.browserDownloadUrl)
    }
}
