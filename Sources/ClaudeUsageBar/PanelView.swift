import AppKit
import SwiftUI
import UsageCore

struct PanelView: View {
    @ObservedObject var poller: Poller

    private var snapshot: Snapshot { poller.snapshot }
    private var config: AppConfig { poller.config }
    private var t: Strings { config.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LimitRow(title: t.fiveHourLimit, window: snapshot.limits?.fiveHour,
                     resetStyle: .time, config: config)
            LimitRow(title: t.weekly, window: snapshot.limits?.sevenDay,
                     resetStyle: .weekday, config: config)

            Divider()

            if snapshot.interactive.isEmpty && snapshot.background.isEmpty {
                Text(t.noSessions)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                ForEach(snapshot.interactive) { SessionLine(row: $0, config: config, poller: poller) }
                if !snapshot.background.isEmpty {
                    Text(t.background)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(snapshot.background) { SessionLine(row: $0, config: config, poller: poller) }
                }
            }

            Divider()

            HStack {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(snapshot.limitsError == nil ? Color.secondary : Color.orange)
                    .lineLimit(1)
                Spacer()
                LanguageToggle(current: config.language) { poller.setLanguage($0) }
                    .help(t.languageHelp)
                Button { poller.openConfig() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .help(t.openConfigHelp)
                Button(t.refresh) { poller.refreshNow() }
                    .disabled(poller.isFetchingLimits)
                Button(t.quit) { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    private var footerText: String {
        switch snapshot.limitsError {
        case .tokenExpired: return t.tokenExpired
        case .noToken: return t.noToken
        case .some: return t.limitsFailed
        case nil: break
        }
        guard let updated = snapshot.limitsUpdatedAt else { return t.updatingLimits }
        let minutes = Int(Date().timeIntervalSince(updated) / 60)
        return minutes < 1 ? t.updatedJustNow : t.updatedMinutesAgo(minutes)
    }
}

private struct LimitRow: View {
    enum ResetStyle { case time, weekday }

    let title: String
    let window: LimitWindow?
    let resetStyle: ResetStyle
    let config: AppConfig

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 70, alignment: .leading)
            UsageBar(percent: window?.utilization, level: BarLevel.level(for: window?.utilization, config: config))
            Text(window?.utilization.map { "\(Int($0.rounded()))%" } ?? "—")
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
            Text(resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
        }
    }

    private var resetText: String {
        guard let date = window?.resetsAt else { return "" }
        let t = config.strings
        return t.resets(resetStyle == .time ? t.time(date) : t.weekdayTime(date))
    }
}

private struct SessionLine: View {
    let row: SessionRow
    let config: AppConfig
    let poller: Poller

    @State private var confirmingStop = false
    @State private var stopping = false
    @State private var stopFailed = false

    private var warn: Bool {
        guard row.isInteractive, let p = row.percent, let first = config.contextThresholds.min() else { return false }
        return p >= first
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.isInteractive ? "circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(row.isInteractive ? Color.green : Color.secondary)
            Text(row.name).lineLimit(1).truncationMode(.middle)
                .frame(width: 110, alignment: .leading)
            Text(shortModel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            UsageBar(percent: row.percent, level: BarLevel.level(for: row.percent, config: config))
            Text(row.percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
            if row.isInteractive {
                Text(warn ? "⚠" : " ").frame(width: 56, alignment: .leading)
            } else {
                backgroundActions.frame(width: 56, alignment: .leading)
            }
        }
        .help(tokensText)
    }

    @ViewBuilder private var backgroundActions: some View {
        if row.jobId == nil {
            Text(" ")
        } else if stopping {
            ProgressView().controlSize(.small)
        } else if confirmingStop {
            Button(config.strings.confirmStop) { stop() }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.caption)
                .help(config.strings.confirmStopHelp)
        } else {
            HStack(spacing: 6) {
                Button { poller.openInTerminal(row) } label: { Image(systemName: "terminal") }
                    .help(config.strings.openInTerminalHelp)
                Button { confirmStop() } label: {
                    Image(systemName: stopFailed ? "exclamationmark.octagon" : "stop.circle")
                        .foregroundStyle(stopFailed ? Color.orange : Color.primary)
                }
                .help(stopFailed ? config.strings.stopFailedHelp : config.strings.stopHelp)
            }
            .buttonStyle(.plain)
        }
    }

    private func confirmStop() {
        confirmingStop = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            confirmingStop = false
        }
    }

    private func stop() {
        guard let jobId = row.jobId else { return }
        confirmingStop = false
        stopping = true
        Task {
            stopFailed = !(await poller.stopSession(jobId: jobId))
            stopping = false
        }
    }

    private var shortModel: String {
        guard let model = row.model else { return "" }
        return model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
    }

    private var tokensText: String {
        guard let tokens = row.tokens else { return config.strings.noRepliesYet }
        return "\(compact(tokens)) / \(compact(row.window))"
    }

    private func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return n % 1_000_000 == 0 ? "\(n / 1_000_000)M" : String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1_000)k" }
        return "\(n)"
    }
}

private struct UsageBar: View {
    let percent: Double?
    let level: BarLevel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max((percent ?? 0) / 100, 0), 1))
            }
        }
        .frame(height: 6)
    }

    private var color: Color {
        switch level {
        case .normal: return .accentColor
        case .warn: return .yellow
        case .critical: return .red
        }
    }
}

/// "ES · EN" switch; the active language is bold.
private struct LanguageToggle: View {
    let current: AppLanguage
    let onChange: (AppLanguage) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppLanguage.allCases, id: \.self) { lang in
                if lang != AppLanguage.allCases.first {
                    Text("·").foregroundStyle(.secondary)
                }
                Button(lang.rawValue.uppercased()) { onChange(lang) }
                    .buttonStyle(.plain)
                    .fontWeight(lang == current ? .bold : .regular)
                    .foregroundStyle(lang == current ? Color.primary : Color.secondary)
            }
        }
        .font(.caption)
    }
}
