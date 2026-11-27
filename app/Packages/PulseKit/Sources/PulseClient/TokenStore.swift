import Foundation

/// Stores the agent token in the app's sandbox container with 0600
/// permissions. The login Keychain is avoided on purpose: ad-hoc signed builds
/// (no Developer ID) change their code signature on every update, and the
/// Keychain would then ask for permission each time.
public enum TokenStore {
    public static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Pulse", directoryHint: .isDirectory).appending(path: "token")
    }

    public static func save(_ token: String, at url: URL = url) throws {
        let fm = FileManager.default
        if token.isEmpty {
            try? fm.removeItem(at: url)
            return
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try Data(token.utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func load(at url: URL = url) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
