import Foundation

enum AppSettingsKeys {
    static let showStatusText = "showStatusText"
    static let maxVisibleModels = "maxVisibleModels"
    static let refreshCadenceMinutes = "refreshCadenceMinutes"

    static let hiddenModelIdsJSON = "hiddenModelIdsJSON"
    static let knownModelsJSON = "knownModelsJSON"

    static let showDebugSettings = "showDebugSettings"
    static let settingsSelectedTab = "settingsSelectedTab"
    static let debugLogsEnabled = "debugLogsEnabled"

    // Status bar display preference
    static let statusBarProvider = "statusBarProvider"

    // Antigravity sign-in state for settings UI
    static let antigravitySignedIn = "antigravitySignedIn"

    // Antigravity monitoring enabled
    static let antigravityEnabled = "antigravityEnabled"
}

enum SettingsTab: String {
    case general
    case codex
    case advanced
    case about
}

enum RefreshCadence: Int, CaseIterable, Identifiable {
    case manual = 0
    case oneMinute = 1
    case twoMinutes = 2
    case fiveMinutes = 5
    case fifteenMinutes = 15

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "1 min"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

struct KnownModel: Codable, Identifiable, Hashable {
    var id: String { modelId }

    let modelId: String
    let label: String
}

enum AppSettings {
    static var showStatusText: Bool {
        getBool(key: AppSettingsKeys.showStatusText, defaultValue: true)
    }

    static var maxVisibleModels: Int {
        let key = AppSettingsKeys.maxVisibleModels
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return 5
        }
        let value = defaults.integer(forKey: key)
        return max(1, min(12, value))
    }

    static var refreshCadence: RefreshCadence {
        let key = AppSettingsKeys.refreshCadenceMinutes
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return .fiveMinutes
        }
        return RefreshCadence(rawValue: defaults.integer(forKey: key)) ?? .fiveMinutes
    }

    static var selectedSettingsTab: SettingsTab {
        let raw = UserDefaults.standard.string(forKey: AppSettingsKeys.settingsSelectedTab)
        return SettingsTab(rawValue: raw ?? "") ?? .general
    }

    static func setSelectedSettingsTab(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: AppSettingsKeys.settingsSelectedTab)
    }

    static func hiddenModelIds() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: AppSettingsKeys.hiddenModelIdsJSON) else {
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([String].self, from: data)
            return Set(decoded)
        } catch {
            return []
        }
    }

    static func setHiddenModelIds(_ hidden: Set<String>) {
        do {
            let data = try JSONEncoder().encode(Array(hidden).sorted())
            UserDefaults.standard.set(data, forKey: AppSettingsKeys.hiddenModelIdsJSON)
        } catch {
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.hiddenModelIdsJSON)
        }
    }

    static func setModelHidden(_ modelId: String, hidden: Bool) {
        var set = hiddenModelIds()
        if hidden {
            set.insert(modelId)
        } else {
            set.remove(modelId)
        }
        setHiddenModelIds(set)
    }

    static func isModelHidden(_ modelId: String) -> Bool {
        hiddenModelIds().contains(modelId)
    }

    static func saveKnownModels(_ models: [KnownModel]) {
        do {
            let data = try JSONEncoder().encode(models)
            UserDefaults.standard.set(data, forKey: AppSettingsKeys.knownModelsJSON)
        } catch {
            UserDefaults.standard.removeObject(forKey: AppSettingsKeys.knownModelsJSON)
        }
    }

    static func loadKnownModels() -> [KnownModel] {
        guard let data = UserDefaults.standard.data(forKey: AppSettingsKeys.knownModelsJSON) else {
            return []
        }
        do {
            return try JSONDecoder().decode([KnownModel].self, from: data)
        } catch {
            return []
        }
    }

    private static func getBool(key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
    
    // MARK: - Status Bar Provider
    
    static var statusBarProvider: StatusBarProvider {
        let raw = UserDefaults.standard.string(forKey: AppSettingsKeys.statusBarProvider)
        return StatusBarProvider(rawValue: raw ?? "") ?? .antigravity
    }
    
    static func setStatusBarProvider(_ provider: StatusBarProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: AppSettingsKeys.statusBarProvider)
    }

    static var antigravityEnabled: Bool {
        getBool(key: AppSettingsKeys.antigravityEnabled, defaultValue: true)
    }

    static func setAntigravityEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: AppSettingsKeys.antigravityEnabled)
    }
}

/// Which provider to show in the menu bar status text.
enum StatusBarProvider: String, CaseIterable, Identifiable {
    case antigravity = "antigravity"
    case codex = "codex"
    case both = "both"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .antigravity: "Antigravity"
        case .codex: "Codex"
        case .both: "Both"
        }
    }
}

extension Notification.Name {
    static let codexOpenSession = Notification.Name("CodexOpenSession")
    static let antigravitySwitchAccount = Notification.Name("AntigravitySwitchAccount")
    static let antigravitySignOut = Notification.Name("AntigravitySignOut")
    static let antigravitySignIn = Notification.Name("AntigravitySignIn")
}
