import Foundation

enum DisplayMode: String {
    case text
    case ring
}

final class SettingsStore {
    private let defaults = UserDefaults.standard

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .text }
        set { defaults.set(newValue.rawValue, forKey: "displayMode") }
    }

    var showRemaining: Bool {
        get { defaults.object(forKey: "showRemaining") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showRemaining") }
    }

    var refreshInterval: TimeInterval {
        let v = defaults.double(forKey: "refreshInterval")
        return v > 0 ? v : 60
    }

    var showClaude: Bool {
        get { defaults.object(forKey: "showClaude") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showClaude") }
    }

    var showCodex: Bool {
        get { defaults.object(forKey: "showCodex") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showCodex") }
    }

    // Custom data paths (nil = use default)
    var claudeProjectsPath: String? {
        get { defaults.string(forKey: "claudeProjectsPath") }
        set {
            if let v = newValue, !v.isEmpty { defaults.set(v, forKey: "claudeProjectsPath") }
            else { defaults.removeObject(forKey: "claudeProjectsPath") }
        }
    }

    var codexSessionsPath: String? {
        get { defaults.string(forKey: "codexSessionsPath") }
        set {
            if let v = newValue, !v.isEmpty { defaults.set(v, forKey: "codexSessionsPath") }
            else { defaults.removeObject(forKey: "codexSessionsPath") }
        }
    }

    // Token budget for Claude's 5-hour rolling window
    var claudeTokenLimit: Int {
        get {
            let v = defaults.integer(forKey: "claudeTokenLimit")
            return v > 0 ? v : 100_000
        }
        set { defaults.set(newValue, forKey: "claudeTokenLimit") }
    }
}
