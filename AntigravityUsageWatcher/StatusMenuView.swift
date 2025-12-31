import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var codexProvider: CodexProvider

    @AppStorage(AppSettingsKeys.maxVisibleModels) private var maxVisibleModels = 5
    @AppStorage(AppSettingsKeys.hiddenModelIdsJSON) private var hiddenModelIdsJSON = Data()
    @AppStorage(AppSettingsKeys.antigravityEnabled) private var antigravityEnabled = true
    @AppStorage(CodexSettingsKeys.enabled) private var codexEnabled = true

    private var snapshot: QuotaSnapshot? {
        model.snapshot
    }

    private var hiddenModelIds: Set<String> {
        guard !hiddenModelIdsJSON.isEmpty else {
            return []
        }
        if let decoded = try? JSONDecoder().decode([String].self, from: hiddenModelIdsJSON) {
            return Set(decoded)
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Antigravity Section
            antigravityHeader

            if let message = model.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !antigravityEnabled {
                Text("Antigravity monitoring disabled in Settings → General.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if model.isSignedIn {
                if let snapshot {
                    modelsSection(snapshot)
                } else {
                    Text(model.isRefreshing ? "Loading…" : "No data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Sign in to show Antigravity usage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Codex Section
            if codexEnabled {
                Divider()
                    .padding(.vertical, 4)
                
                codexSection
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - Antigravity Header

    @ViewBuilder
    private var antigravityHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Antigravity")
                    .font(.title3)
                    .bold()

                Spacer(minLength: 12)

                Text(snapshot?.accountEmail ?? (model.isSignedIn ? "Signed in" : "Signed out"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(antigravityUpdatedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                if let plan = snapshot?.planLabel, !plan.isEmpty {
                    Text(plan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var antigravityUpdatedLabel: String {
        guard model.isSignedIn else {
            return ""
        }
        guard let date = snapshot?.timestamp else {
            return model.isRefreshing ? "Updating…" : "Not updated yet"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Updated \(relative)"
    }

    // MARK: - Codex Section

    @ViewBuilder
    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex")
                    .font(.title3)
                    .bold()

                Spacer(minLength: 12)

                let email = codexProvider.snapshot?.email ?? (codexProvider.isRunning ? "Signed in" : "Signed out")
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(codexUpdatedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                if let planType = codexProvider.snapshot?.planType,
                   let label = CodexFormatting.planLabel(planType) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !codexProvider.isRunning {
                    Text("Not running")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }

        if let errorMessage = codexProvider.lastErrorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let codexSnapshot = codexProvider.snapshot, codexSnapshot.hasData {
            codexLimitsSection(codexSnapshot)
        } else if codexProvider.isRunning {
            Text("Fetching usage data…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if codexProvider.lastErrorMessage == nil {
            Text("Enable in Settings → OpenAI")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var codexUpdatedLabel: String {
        guard let date = codexProvider.snapshot?.timestamp else {
            return codexProvider.isRunning ? "Fetching…" : ""
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Updated \(relative)"
    }

    @ViewBuilder
    private func codexLimitsSection(_ snapshot: CodexSnapshot) -> some View {
        if let primary = snapshot.primaryLimit {
            limitRow(
                label: primary.windowLabel,
                usedPercent: primary.usedPercent,
                remainingPercent: primary.remainingPercent,
                resetTime: primary.timeUntilReset,
                isExhausted: primary.isExhausted
            )
        }

        if let secondary = snapshot.secondaryLimit {
            limitRow(
                label: secondary.windowLabel,
                usedPercent: secondary.usedPercent,
                remainingPercent: secondary.remainingPercent,
                resetTime: secondary.timeUntilReset,
                isExhausted: secondary.isExhausted
            )
        }
    }

    @ViewBuilder
    private func limitRow(label: String, usedPercent: Int, remainingPercent: Int, resetTime: String?, isExhausted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
                .lineLimit(1)

            ProgressView(value: Double(remainingPercent), total: 100)
                .progressViewStyle(.linear)
                .tint(isExhausted ? .red : Color(.sRGB, red: 0/255, green: 122/255, blue: 255/255, opacity: 1))

            HStack {
                Text("\(remainingPercent)% left")
                    .font(.subheadline)
                    .monospacedDigit()

                Spacer()

                if let resetTime {
                    Text("Resets \(resetTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Antigravity Models Section

    @ViewBuilder
    private func modelsSection(_ snapshot: QuotaSnapshot) -> some View {
        let pinned = model.pinnedModelId
        let filtered = snapshot.modelsSortedForDisplay.filter { quota in
            if let pinned, quota.modelId == pinned {
                return true
            }
            return !hiddenModelIds.contains(quota.modelId)
        }

        if filtered.isEmpty {
            Text("No models selected")
                .font(.subheadline)
            Text("Enable models in Settings → Advanced.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let visible = Array(filtered.prefix(max(1, maxVisibleModels)))

            ForEach(visible) { quota in
                VStack(alignment: .leading, spacing: 6) {
                    Text(quota.label)
                        .font(.headline)
                        .lineLimit(1)

                    ProgressView(value: Double(quota.remainingPercent), total: 100)
                        .progressViewStyle(.linear)
                        .tint(quota.isExhausted ? .red : Color(.sRGB, red: 0/255, green: 209/255, blue: 131/255, opacity: 1))

                    HStack {
                        Text("\(quota.remainingPercent)% left")
                            .font(.subheadline)
                            .monospacedDigit()

                        Spacer()

                        Text(resetLabel(for: quota))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if filtered.count > visible.count {
                Text("Showing \(visible.count) of \(filtered.count) selected models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resetLabel(for quota: ModelQuota) -> String {
        if let until = quota.timeUntilReset {
            return "Resets \(until)"
        }
        return ""
    }
}
