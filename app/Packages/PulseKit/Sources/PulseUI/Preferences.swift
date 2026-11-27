import Foundation
import Observation
import PulseClient
import PulseCore

/// Metrics that can appear in the menu bar.
public enum MenuField: String, CaseIterable, Codable, Sendable, Identifiable {
    case temp, cpu, mem, disk, net, containers
    public var id: String { rawValue }

    /// Label drawn above the value (Mole style).
    public var label: String {
        switch self {
        case .temp: "TMP"
        case .cpu: "CPU"
        case .mem: "MEM"
        case .disk: "DSK"
        case .net: "NET"
        case .containers: "CTR"
        }
    }
}

/// What the status item shows.
public enum MenuContent: String, CaseIterable, Codable, Sendable {
    case icon, data, both
}

/// Animated character next to the menu bar numbers.
public enum MenuAnimation: String, CaseIterable, Codable, Sendable, Identifiable {
    case server, cat, pulse, none
    public var id: String { rawValue }
}

public enum MenuLayout: String, CaseIterable, Codable, Sendable {
    case columns, line
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system, en, tr
}

/// User preferences in UserDefaults; the token lives in TokenStore.
@MainActor @Observable
public final class Preferences {
    private let defaults: UserDefaults

    public var address: String { didSet { defaults.set(address, forKey: Keys.address) } }
    public var token: String { didSet { try? TokenStore.save(token) } }
    /// Up to three menu bar metrics, in slot order.
    public var menuFields: [MenuField] { didSet { save(menuFields, Keys.menuFields) } }
    public var menuContent: MenuContent { didSet { defaults.set(menuContent.rawValue, forKey: Keys.menuContent) } }
    public var menuAnimation: MenuAnimation { didSet { defaults.set(menuAnimation.rawValue, forKey: Keys.menuAnimation) } }
    public var animationFollowsLoad: Bool { didSet { defaults.set(animationFollowsLoad, forKey: Keys.followsLoad) } }
    public var menuLayout: MenuLayout { didSet { defaults.set(menuLayout.rawValue, forKey: Keys.menuLayout) } }
    public var showNetworkSpeed: Bool { didSet { defaults.set(showNetworkSpeed, forKey: Keys.netSpeed) } }
    public var swapClicks: Bool { didSet { defaults.set(swapClicks, forKey: Keys.swapClicks) } }
    public var panelShortcut: Bool { didSet { defaults.set(panelShortcut, forKey: Keys.shortcut) } }
    public var alerts: AlertSettings { didSet { save(alerts, Keys.alerts) } }
    public var notificationsPausedUntil: Date? { didSet { defaults.set(notificationsPausedUntil, forKey: Keys.pausedUntil) } }
    public var sshTarget: String { didSet { defaults.set(sshTarget, forKey: Keys.ssh) } }
    public var portainerURL: String { didSet { defaults.set(portainerURL, forKey: Keys.portainer) } }
    public var cockpitURL: String { didSet { defaults.set(cockpitURL, forKey: Keys.cockpit) } }
    public var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            if language == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([language.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    enum Keys {
        static let address = "serverAddress"
        static let menuFields = "menuFields"
        static let menuContent = "menuContent"
        static let menuAnimation = "menuAnimation"
        static let followsLoad = "animationFollowsLoad"
        static let menuLayout = "menuLayout"
        static let netSpeed = "showNetworkSpeed"
        static let swapClicks = "swapClicks"
        static let shortcut = "panelShortcut"
        static let alerts = "alerts"
        static let pausedUntil = "notificationsPausedUntil"
        static let ssh = "sshTarget"
        static let portainer = "portainerURL"
        static let cockpit = "cockpitURL"
        static let language = "language"
    }

    public static let maxMenuFields = 3

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        address = defaults.string(forKey: Keys.address) ?? ""
        token = TokenStore.load() ?? ""
        menuFields = Array((Self.load([MenuField].self, defaults, Keys.menuFields) ?? [.temp, .cpu, .mem]).prefix(Self.maxMenuFields))
        menuContent = defaults.string(forKey: Keys.menuContent).flatMap(MenuContent.init) ?? .both
        menuAnimation = defaults.string(forKey: Keys.menuAnimation).flatMap(MenuAnimation.init) ?? .server
        animationFollowsLoad = defaults.object(forKey: Keys.followsLoad) as? Bool ?? true
        menuLayout = defaults.string(forKey: Keys.menuLayout).flatMap(MenuLayout.init) ?? .columns
        showNetworkSpeed = defaults.bool(forKey: Keys.netSpeed)
        swapClicks = defaults.bool(forKey: Keys.swapClicks)
        panelShortcut = defaults.object(forKey: Keys.shortcut) as? Bool ?? true
        alerts = Self.load(AlertSettings.self, defaults, Keys.alerts) ?? AlertSettings()
        notificationsPausedUntil = defaults.object(forKey: Keys.pausedUntil) as? Date
        sshTarget = defaults.string(forKey: Keys.ssh) ?? ""
        portainerURL = defaults.string(forKey: Keys.portainer) ?? ""
        cockpitURL = defaults.string(forKey: Keys.cockpit) ?? ""
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init) ?? .system
    }

    public var serverConfig: ServerConfig? {
        let c = ServerConfig(address: address, token: token)
        return c.baseURL == nil || token.isEmpty ? nil : c
    }

    /// Host part of the agent address, used to derive shortcut defaults.
    public var host: String? { ServerConfig(address: address, token: "").baseURL?.host() }

    public var resolvedSSH: URL? {
        let target = sshTarget.isEmpty ? (host ?? "") : sshTarget
        return target.isEmpty ? nil : URL(string: "ssh://" + target)
    }

    public var resolvedPortainer: URL? {
        URL(string: portainerURL.isEmpty ? host.map { "https://\($0):9443" } ?? "" : portainerURL)
    }

    public var resolvedCockpit: URL? {
        URL(string: cockpitURL.isEmpty ? host.map { "https://\($0):9090" } ?? "" : cockpitURL)
    }

    public var notificationsPaused: Bool {
        guard let until = notificationsPausedUntil else { return false }
        return until > Date()
    }

    /// Metrics actually drawn: the chosen slots plus network speed when enabled.
    public var effectiveMenuFields: [MenuField] {
        var fields = menuFields
        if showNetworkSpeed, !fields.contains(.net) { fields.append(.net) }
        return fields
    }

    /// Set slot `index` (0-based) to a field, or nil to hide it.
    public func setMenuField(_ field: MenuField?, at index: Int) {
        var slots: [MenuField?] = (0..<Self.maxMenuFields).map { $0 < menuFields.count ? menuFields[$0] : nil }
        if let field, let existing = slots.firstIndex(of: field) { slots[existing] = nil }
        slots[index] = field
        menuFields = slots.compactMap { $0 }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_: T.Type, _ defaults: UserDefaults, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
