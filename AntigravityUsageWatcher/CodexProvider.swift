import Combine
import Darwin
import Foundation
import os

/// Actor that manages a background Codex CLI session for usage monitoring.
@MainActor
final class CodexProvider: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var onUpdate: (() -> Void)?

    private(set) var snapshot: CodexSnapshot?
    private(set) var isRunning = false
    private(set) var lastErrorMessage: String?
    private(set) var sessionLog: String = ""

    private let maxLogCharacters = 20000

    private var masterFD: Int32 = -1
    private var process: Process?
    private var outputBuffer = Data()
    private var readSource: DispatchSourceRead?
    private var autoRefreshTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.github.shekohex.AntigravityUsageWatcher", category: "codex")

    init() {}

    private func notifyChanged() {
        objectWillChange.send()
        onUpdate?()
    }

    // MARK: - Public API

    /// Start the Codex CLI background session.
    func start() async {
        guard !isRunning else { return }
        guard CodexSettings.enabled else {
            log.info("Codex provider disabled in settings")
            return
        }

        guard let codexPath = findCodexBinary() else {
            lastErrorMessage = "Codex CLI not found. Install with: brew install --cask codex"
            notifyChanged()
            return
        }

        log.info("Starting Codex session with binary: \(codexPath, privacy: .public)")

        do {
            try spawnCodexProcess(at: codexPath)
            isRunning = true
            lastErrorMessage = nil
            notifyChanged()

            // Wait for initial prompt
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // Initial status fetch
            await refreshNow()

            // Start auto-refresh loop
            startAutoRefresh()
        } catch {
            log.error("Failed to start Codex: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = "Failed to start Codex: \(error.localizedDescription)"
            notifyChanged()
        }
    }

    /// Stop the Codex CLI session.
    func stop() async {
        stopSync()
    }

    private func stopSync() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil

        readSource?.cancel()
        readSource = nil

        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }

        if let process, process.isRunning {
            process.terminate()
        }
        process = nil

        isRunning = false
        outputBuffer.removeAll()
    }

    /// Clear the in-memory session log.
    func clearLog() {
        sessionLog = ""
        notifyChanged()
    }

    /// Refresh the status by sending /status to the CLI.
    func refreshNow() async {
        guard isRunning, masterFD >= 0 else {
            log.warning("Cannot refresh: Codex session not running")
            return
        }

        log.debug("Sending /status command")

        // Clear buffer before sending
        outputBuffer.removeAll()

        // Send /status command
        let command = "/status\r"
        _ = command.withCString { ptr in
            write(masterFD, ptr, strlen(ptr))
        }

        // Wait for response
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        // Parse the output
        let output = String(decoding: outputBuffer, as: UTF8.self)
        log.debug("Raw output length: \(output.count, privacy: .public)")

        if !output.isEmpty {
            // Extract email/plan/account from cached auth.json if available
            let (email, planType, accountId) = loadAuthInfo()
            snapshot = CodexOutputParser.parseStatusOutput(output, email: email, planType: planType, accountId: accountId)
            log.info("Parsed snapshot: primary=\(self.snapshot?.primaryLimit?.usedPercent ?? -1, privacy: .public)%, secondary=\(self.snapshot?.secondaryLimit?.usedPercent ?? -1, privacy: .public)%")
        }

        notifyChanged()
    }

    /// Restart the session (e.g., after settings change).
    func restart() async {
        await stop()
        await start()
    }

    // MARK: - PTY Management

    private func spawnCodexProcess(at path: String) throws {
        var master: Int32 = 0
        var slave: Int32 = 0

        // Open a pseudo-terminal
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw CodexProviderError.ptyOpenFailed
        }

        masterFD = master

        // Configure the PTY
        var termios = Darwin.termios()
        tcgetattr(slave, &termios)
        cfmakeraw(&termios)
        tcsetattr(slave, TCSANOW, &termios)

        // Set window size
        var winsize = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(slave, TIOCSWINSZ, &winsize)

        // Create the process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = []
        proc.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "xterm-256color",
            "COLUMNS": "120",
            "LINES": "40"
        ]) { _, new in new }

        // Use the slave PTY for I/O
        proc.standardInput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardOutput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardError = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

        proc.terminationHandler = { [weak self] terminatedProcess in
            let exitCode = terminatedProcess.terminationStatus
            DispatchQueue.main.async { [weak self] in
                self?.handleTermination(exitCode: exitCode)
            }
        }

        try proc.run()
        process = proc

        // Close slave in parent
        close(slave)

        // Start reading from master
        setupReadSource()
    }

    private func setupReadSource() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .global(qos: .userInteractive))

        source.setEventHandler { [weak self] in
            guard let self else { return }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(self.masterFD, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                Task { @MainActor in
                    self.handleIncomingData(data)
                }
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            close(self.masterFD)
        }

        source.resume()
        readSource = source
    }

    private func handleIncomingData(_ data: Data) {
        outputBuffer.append(data)

        let str = String(decoding: data, as: UTF8.self)
        appendToLog(str)

        // Check for cursor position query and respond
        // The query is ESC [ 6 n, we respond with ESC [ row ; col R
        if str.contains("\u{1B}[6n") {
            log.debug("Responding to cursor position query")
            let response = "\u{1B}[24;1R"
            _ = response.withCString { ptr in
                write(masterFD, ptr, strlen(ptr))
            }
        }
    }

    private func handleTermination(exitCode: Int32) {
        log.warning("Codex process terminated with code: \(exitCode, privacy: .public)")
        isRunning = false

        if exitCode != 0 {
            lastErrorMessage = "Codex exited with code \(exitCode)"
        }

        notifyChanged()
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()

        let intervalSeconds = CodexSettings.refreshCadence.seconds
        guard intervalSeconds > 0 else {
            log.info("Codex auto-refresh disabled (manual mode)")
            return
        }

        autoRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRunning {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refreshNow()
            }
        }
    }

    // MARK: - Helpers

    private func appendToLog(_ chunk: String) {
        guard !chunk.isEmpty else { return }

        let cleaned = CodexOutputParser.stripANSI(chunk)
        sessionLog.append(cleaned)

        if sessionLog.count > maxLogCharacters {
            let overflow = sessionLog.count - maxLogCharacters
            sessionLog.removeFirst(overflow)
        }

        notifyChanged()
    }

    /// Find the codex binary in common locations.
    private func findCodexBinary() -> String? {
        // Check user-configured path first
        let customPath = CodexSettings.binaryPath
        if !customPath.isEmpty, FileManager.default.isExecutableFile(atPath: customPath) {
            return customPath
        }

        // Search common locations
        let searchPaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
            "\(NSHomeDirectory())/bin/codex"
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try PATH
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/codex"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    /// Load email, plan type, and account ID from ~/.codex/auth.json.
    private func loadAuthInfo() -> (email: String?, planType: String?, accountId: String?) {
        let authPath = "\(NSHomeDirectory())/.codex/auth.json"
        guard let data = FileManager.default.contents(atPath: authPath) else {
            return (nil, nil, nil)
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tokens = json["tokens"] as? [String: Any],
               let accessToken = tokens["access_token"] as? String {
                let tokenAccountId = tokens["account_id"] as? String

                // Decode JWT payload
                let parts = accessToken.split(separator: ".")
                if parts.count >= 2 {
                    var payload = String(parts[1])
                        .replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")

                    // Add padding
                    while payload.count % 4 != 0 {
                        payload += "="
                    }

                    if let payloadData = Data(base64Encoded: payload),
                       let claims = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {

                        let profile = claims["https://api.openai.com/profile"] as? [String: Any]
                        let auth = claims["https://api.openai.com/auth"] as? [String: Any]

                        let email = profile?["email"] as? String
                        let planType = auth?["chatgpt_plan_type"] as? String
                        let claimAccountId = auth?["chatgpt_account_id"] as? String
                        let accountId = tokenAccountId ?? claimAccountId

                        return (email, planType, accountId)
                    }
                }
            }
        } catch {
            log.error("Failed to parse auth.json: \(error.localizedDescription, privacy: .public)")
        }

        return (nil, nil, nil)
    }
}

// MARK: - Errors

enum CodexProviderError: Error, LocalizedError {
    case ptyOpenFailed
    case processStartFailed
    case notRunning

    var errorDescription: String? {
        switch self {
        case .ptyOpenFailed:
            return "Failed to open pseudo-terminal"
        case .processStartFailed:
            return "Failed to start Codex process"
        case .notRunning:
            return "Codex session is not running"
        }
    }
}

// MARK: - Settings

enum CodexSettingsKeys {
    static let enabled = "codexEnabled"
    static let binaryPath = "codexBinaryPath"
    static let refreshCadenceMinutes = "codexRefreshCadenceMinutes"
    static let showInStatusBar = "codexShowInStatusBar"
}

enum CodexRefreshCadence: Int, CaseIterable, Identifiable {
    case manual = 0
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

enum CodexSettings {
    static var enabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: CodexSettingsKeys.enabled) == nil {
            return true  // Enabled by default
        }
        return defaults.bool(forKey: CodexSettingsKeys.enabled)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: CodexSettingsKeys.enabled)
    }

    static var binaryPath: String {
        UserDefaults.standard.string(forKey: CodexSettingsKeys.binaryPath) ?? ""
    }

    static func setBinaryPath(_ value: String) {
        UserDefaults.standard.set(value, forKey: CodexSettingsKeys.binaryPath)
    }

    static var refreshCadence: CodexRefreshCadence {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: CodexSettingsKeys.refreshCadenceMinutes) == nil {
            return .oneMinute  // Default to 1 minute as requested
        }
        return CodexRefreshCadence(rawValue: defaults.integer(forKey: CodexSettingsKeys.refreshCadenceMinutes)) ?? .oneMinute
    }

    static func setRefreshCadence(_ value: CodexRefreshCadence) {
        UserDefaults.standard.set(value.rawValue, forKey: CodexSettingsKeys.refreshCadenceMinutes)
    }

    static var showInStatusBar: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: CodexSettingsKeys.showInStatusBar) == nil {
            return false  // Off by default, Antigravity takes priority
        }
        return defaults.bool(forKey: CodexSettingsKeys.showInStatusBar)
    }

    static func setShowInStatusBar(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: CodexSettingsKeys.showInStatusBar)
    }
}
