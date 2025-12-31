import Combine
import SwiftUI

struct SettingsRootView: View {
    @AppStorage(AppSettingsKeys.settingsSelectedTab) private var selectedTabRaw = SettingsTab.general.rawValue
    @AppStorage(AppSettingsKeys.antigravityEnabled) private var antigravityEnabled = true
    @AppStorage(CodexSettingsKeys.enabled) private var codexEnabled = true

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

            if codexEnabled {
                CodexSettingsView()
                    .tabItem { Label("Codex", systemImage: "brain") }
                    .tag(SettingsTab.codex)
            }

            if antigravityEnabled {
                AntigravitySettingsView()
                    .tabItem { Label("Antigravity", systemImage: "sparkles") }
                    .tag(SettingsTab.advanced)
            }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(16)
        .frame(width: 560, height: 520)
        .onChange(of: codexEnabled) { _, newValue in
            if !newValue, selectionBinding.wrappedValue == .codex {
                selectionBinding.wrappedValue = .general
            }
        }
        .onChange(of: antigravityEnabled) { _, newValue in
            if !newValue, selectionBinding.wrappedValue == .advanced {
                selectionBinding.wrappedValue = .general
            }
        }
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(AppSettingsKeys.showStatusText) private var showStatusText = true
    @AppStorage(AppSettingsKeys.statusBarProvider) private var statusBarProviderRaw = StatusBarProvider.antigravity.rawValue
    @AppStorage(AppSettingsKeys.antigravityEnabled) private var antigravityEnabled = true
    @AppStorage(CodexSettingsKeys.enabled) private var codexEnabled = true

    private var statusBarProviderBinding: Binding<StatusBarProvider> {
        Binding(
            get: {
                let value = StatusBarProvider(rawValue: statusBarProviderRaw) ?? .antigravity
                if availableProviders.contains(value) {
                    return value
                }
                return availableProviders.first ?? .antigravity
            },
            set: { statusBarProviderRaw = $0.rawValue }
        )
    }

    private var availableProviders: [StatusBarProvider] {
        var providers: [StatusBarProvider] = []

        if antigravityEnabled {
            providers.append(.antigravity)
        }

        if codexEnabled {
            providers.append(.codex)
        }

//        if antigravityEnabled && codexEnabled {
//            providers.append(.both)
//        }

        return providers.isEmpty ? [.antigravity] : providers
    }

    var body: some View {
        ScrollView {
            Form {
                Section {
                    header: do {
                        Text("Model Options")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    
                    Toggle("Enable Antigravity monitoring", isOn: $antigravityEnabled)
                        .onChange(of: antigravityEnabled) { _, _ in
                            normalizeStatusBarProvider()
                        }
                        .padding(.top, 8)

                    Toggle("Enable Codex monitoring", isOn: $codexEnabled)
                        .onChange(of: codexEnabled) { _, _ in
                            normalizeStatusBarProvider()
                        }
                }

                Toggle("Show usage in menu bar", isOn: $showStatusText)
                Text("Status bar provider:")
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.headline)

                if showStatusText {
                    Picker("Status bar provider", selection: statusBarProviderBinding) {
                        ForEach(availableProviders) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }.labelsHidden()
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .center)

                    Text("Choose which provider's usage to show in the menu bar. If a particular model is pinned in the dropdown menu, that will override this option.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func normalizeStatusBarProvider() {
        if let first = availableProviders.first {
            statusBarProviderRaw = first.rawValue
        }
    }
}

private struct CodexSettingsView: View {
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
        ScrollView {
            Form {
                Section {
                    header: do {
                        Text("Codex")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Text("Monitor your ChatGPT plan usage limits via the Codex CLI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }.font(.headline).frame(maxWidth: .infinity, alignment: .center)

                Section {
                    Text("Refresh cadence").padding(.top, 8)

                    Picker("Cadence", selection: cadenceBinding) {
                        ForEach(CodexRefreshCadence.allCases) { cadence in
                            Text(cadence.label).tag(cadence)
                        }
                    }.labelsHidden()
                    .pickerStyle(.segmented)

                    Text("How often to fetch usage from Codex CLI. Use the Refresh button for on-demand updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    header: do {
                        Text("Codex Binary Path:").padding(.top, 4)
                    }
                    TextField("Path to codex", text: $binaryPath, prompt: Text("Auto-detect")).labelsHidden()
                    if let detected = detectedPath {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Found: \(detected)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }.padding(.top, 2)
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
                    }.padding(.top, 2)
                }

                Section {
                    header: do {
                        Text("Session").padding(.top, 4)
                    }
                    Button("Open Codex Terminal Session") {
                        NotificationCenter.default.post(name: .codexOpenSession, object: nil)
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
            .padding(.bottom, 8)
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

private struct AntigravitySettingsView: View {
    @AppStorage(AppSettingsKeys.refreshCadenceMinutes) private var refreshCadenceMinutes = RefreshCadence.fiveMinutes.rawValue
    @AppStorage(AppSettingsKeys.maxVisibleModels) private var maxVisibleModels = 5
    @AppStorage(AppSettingsKeys.antigravitySignedIn) private var antigravitySignedIn = false

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
        ScrollView {
            Form {
                Section {
                    header: do {
                        Text("Antigravity Language Server")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Text("Monitor your Antigravity plan usage limits via the Antigravity local language server.")
                        .font(.caption)
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
                }
                Section {
                    Text("Refresh cadence").padding(.top, 8)

                    Picker("Cadence", selection: cadenceBinding) {
                        ForEach(RefreshCadence.allCases) { cadence in
                            Text(cadence.label).tag(cadence)
                        }
                    }.labelsHidden()
                    .pickerStyle(.segmented)

                    Text("How often to fetch usage from Codex CLI. Use the Refresh button for on-demand updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    header: do {
                        Text("Account").padding(.top, 4)
                    }
                    if antigravitySignedIn {
                        Button("Switch Account") {
                            NotificationCenter.default.post(name: .antigravitySwitchAccount, object: nil)
                        }

                        Button("Sign Out") {
                            NotificationCenter.default.post(name: .antigravitySignOut, object: nil)
                        }
                    } else {
                        Button("Sign in with Google") {
                            NotificationCenter.default.post(name: .antigravitySignIn, object: nil)
                        }
                    }
                }

                Section {
                    header: do {
                        Text("Dropdown Display").padding(.top, 4)
                        HStack{
                            
                            Stepper(value: $maxVisibleModels, in: 1...12) {
                            }
                            Text("Max visible models: \(maxVisibleModels)").padding(.top, 4)
                        }
                    }}

                Section {
                    header: do {
                        Text("Models").padding(.top, 4)}
                    if knownModels.isEmpty {
                        Text("No models detected yet.")
                            .foregroundStyle(.secondary)
                        Text("Open the menu bar app and refresh once to populate this list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        

//                        Toggle("Show hidden models", isOn: $showHiddenOnly)

//                        HStack {
//                            Button("Show All") {
//                                hiddenModelIds.removeAll()
//                                AppSettings.setHiddenModelIds(hiddenModelIds)
//                            }
//
//                            Button("Hide All") {
//                                hiddenModelIds = Set(knownModels.map { $0.modelId })
//                                AppSettings.setHiddenModelIds(hiddenModelIds)
//                            }
//
//                            Spacer()
//                        }

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
            .padding(.bottom, 8)
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
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)

                Text("AI Usage Limit Monitor")
                    .font(.title3)
                    .bold()

                Text(versionString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Link(destination: URL(string: "https://github.com/vishnu09bharath/ai-usage-limit-monitor")!) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                .padding(.top, 8)

                Divider()

                Toggle("Check for updates automatically", isOn: $checkUpdatesAutomatically)

                Button("Check for Updates…") {}
                    .disabled(true)

                Spacer()

                Text("© 2025")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsRootView()
        .frame(width: 720, height: 560)
}
#endif
