import AppKit
import SwiftUI

@MainActor
final class CodexSessionWindowController: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?

    func show(provider: CodexProvider) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = CodexSessionView(provider: provider)
        let hosting = NSHostingView(rootView: view)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Codex Session"
        newWindow.contentView = hosting
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        newWindow.delegate = self
        window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct CodexSessionView: View {
    @ObservedObject var provider: CodexProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex Session")
                    .font(.title2)
                    .bold()

                Spacer()

                if provider.isRunning {
                    Text("Live")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Stopped")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let error = provider.lastErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            TextEditor(text: Binding(
                get: { provider.sessionLog },
                set: { _ in }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 300)
            .disabled(true)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            HStack {
                Button("Refresh Status") {
                    Task { await provider.refreshNow() }
                }
                .disabled(!provider.isRunning)

                Button("Restart Codex") {
                    Task { await provider.restart() }
                }

                Button("Clear Log") {
                    provider.clearLog()
                }

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(provider.sessionLog, forType: .string)
                }

                Spacer()
            }
        }
        .padding(16)
    }
}
