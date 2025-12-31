import Combine
import SwiftUI

struct SettingsRootView: View {
    @AppStorage(AppSettingsKeys.settingsSelectedTab) private var selectedTabRaw = SettingsTab.general.rawValue

    private var selectionBinding: Binding<SettingsTab> {
        Binding(
            get: { SettingsTab(rawValue: selectedTabRaw) ?? .general },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectionBinding) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            CodexSettingsView()
                .tabItem { Label("OpenAI", systemImage: "brain") }
                .tag(SettingsTab.codex)

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(16)
        .frame(width: 540, height: 480)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(AppSettingsKeys.showStatusText) private var showStatusText = true
    @AppStorage(AppSettingsKeys.statusBarProvider) private var statusBarProviderRaw = StatusBarProvider.antigravity.rawValue

    private var statusBarProviderBinding: Binding<StatusBarProvider> {
        Binding(
            get: { StatusBarProvider(rawValue: statusBarProviderRaw) ?? .antigravity },
            set: { statusBarProviderRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Toggle("Show usage in menu bar", isOn: $showStatusText)

            if showStatusText {
                Picker("Status bar provider", selection: statusBarProviderBinding) {
                    ForEach(StatusBarProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                
                Text("Choose which provider's usage to show in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Antigravity quotas are fetched from the local Antigravity language server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CodexSettingsView: View {
    @AppStorage(CodexSettingsKeys.enabled) private var codexEnabled = true
    @AppStorage(CodexSettingsKeys.binaryPath) private var binaryPath = ""
    @AppStorage(CodexSettingsKeys.refreshCadenceMinutes) private var refreshCadenceMinutes = CodexRefreshCadence.oneMinute.rawValue

    @State private var detectedPath: String?

    private var cadenceBinding: Binding<CodexRefreshCadence> {
        Binding(
            get: { CodexRefreshCadence(rawValue: refreshCadenceMinutes) ?? .oneMinute },
            set: { refreshCadenceMinutes = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("OpenAI / Codex CLI") {
                Toggle("Enable Codex usage monitoring", isOn: $codexEnabled)

                Text("Monitor your ChatGPT plan usage limits via the Codex CLI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if codexEnabled {
                Section("Refresh Cadence") {
                    Picker("Refresh cadence", selection: cadenceBinding) {
                        ForEach(CodexRefreshCadence.allCases) { cadence in
                            Text(cadence.label).tag(cadence)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("How often to fetch usage from Codex CLI. Use the Refresh button for on-demand updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Codex Binary") {
                    TextField("Path to codex", text: $binaryPath, prompt: Text("Auto-detect"))

                    if let detected = detectedPath {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Found: \(detected)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if binaryPath.isEmpty {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            Text("Will search in /opt/homebrew/bin, /usr/local/bin, etc.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Detect Codex") {
                        detectCodexBinary()
                    }
                }

                Section {
                    Text("Requires Codex CLI to be installed and logged in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Link("Install Codex CLI", destination: URL(string: "https://github.com/openai/codex")!)
                        .font(.caption)
                }
            }
        }
        .onAppear {
            detectCodexBinary()
        }
    }

    private func detectCodexBinary() {
        let searchPaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
            "\(NSHomeDirectory())/bin/codex"
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                detectedPath = path
                return
            }
        }

        // Try PATH
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/codex"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                detectedPath = candidate
                return
            }
        }

        detectedPath = nil
    }
}

private struct AdvancedSettingsView: View {
    @AppStorage(AppSettingsKeys.refreshCadenceMinutes) private var refreshCadenceMinutes = RefreshCadence.fiveMinutes.rawValue
    @AppStorage(AppSettingsKeys.maxVisibleModels) private var maxVisibleModels = 5

    @State private var knownModels: [KnownModel] = []
    @State private var hiddenModelIds: Set<String> = []
    @State private var modelSearchText = ""
    @State private var showHiddenOnly = false

    @AppStorage(AppSettingsKeys.showDebugSettings) private var showDebugSettings = false
    @AppStorage(AppSettingsKeys.debugLogsEnabled) private var debugLogsEnabled = false

    private var cadenceBinding: Binding<RefreshCadence> {
        Binding(
            get: { RefreshCadence(rawValue: refreshCadenceMinutes) ?? .fiveMinutes },
            set: { refreshCadenceMinutes = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Refresh cadence") {
                Picker("Refresh cadence", selection: cadenceBinding) {
                    ForEach(RefreshCadence.allCases) { cadence in
                        Text(cadence.label).tag(cadence)
                    }
                }
                .pickerStyle(.segmented)

                Text("When set to Manual, refresh only happens on demand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu") {
                Stepper(value: $maxVisibleModels, in: 1...12) {
                    Text("Max visible models: \(maxVisibleModels)")
                }
            }

            Section("Models") {
                if knownModels.isEmpty {
                    Text("No models detected yet.")
                        .foregroundStyle(.secondary)
                    Text("Open the menu bar app and refresh once to populate this list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Search models", text: $modelSearchText)

                    Toggle("Show hidden models", isOn: $showHiddenOnly)

                    HStack {
                        Button("Show All") {
                            hiddenModelIds.removeAll()
                            AppSettings.setHiddenModelIds(hiddenModelIds)
                        }

                        Button("Hide All") {
                            hiddenModelIds = Set(knownModels.map { $0.modelId })
                            AppSettings.setHiddenModelIds(hiddenModelIds)
                        }

                        Spacer()
                    }

                    ForEach(filteredKnownModels) { known in
                        Toggle(isOn: isModelVisibleBinding(known)) {
                            Text(known.label)
                        }
                    }

                    Text("Pinned models are always shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Show Debug Settings", isOn: $showDebugSettings)

                if showDebugSettings {
                    Toggle("Enable debug logs (Release builds)", isOn: $debugLogsEnabled)
                    Text("Debug logs may include network error details but should never include tokens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { reloadModelsFromDefaults() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            reloadModelsFromDefaults()
        }
    }

    private var filteredKnownModels: [KnownModel] {
        var base = knownModels

        if !modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            base = base.filter { $0.label.lowercased().contains(query) }
        }

        if showHiddenOnly {
            base = base.filter { hiddenModelIds.contains($0.modelId) }
        }

        return base
    }

    private func reloadModelsFromDefaults() {
        knownModels = AppSettings.loadKnownModels()
        hiddenModelIds = AppSettings.hiddenModelIds()
    }

    private func isModelVisibleBinding(_ known: KnownModel) -> Binding<Bool> {
        Binding(
            get: { !hiddenModelIds.contains(known.modelId) },
            set: { isVisible in
                if isVisible {
                    hiddenModelIds.remove(known.modelId)
                } else {
                    hiddenModelIds.insert(known.modelId)
                }
                AppSettings.setHiddenModelIds(hiddenModelIds)
            }
        )
    }
}

private struct AboutSettingsView: View {
    @AppStorage("checkUpdatesAutomatically") private var checkUpdatesAutomatically = true

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text("AntigravityUsageWatcher")
                .font(.title3)
                .bold()

            Text(versionString)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/shekohex/AntigravityUsageWatcher")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .padding(.top, 8)

            Divider()

            Toggle("Check for updates automatically", isOn: $checkUpdatesAutomatically)

            Button("Check for Updates…") {}
                .disabled(true)

            Spacer()

            Text("© \(Calendar.current.component(.year, from: Date()))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
