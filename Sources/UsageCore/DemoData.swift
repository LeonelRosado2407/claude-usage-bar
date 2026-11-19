import Foundation

/// Fictional data for screenshots and `--demo` mode. Contains nothing from the real machine.
public enum DemoData {
    public static func snapshot(now: Date) -> Snapshot {
        let window = 1_000_000
        return Snapshot(
            interactive: [
                SessionRow(id: "demo-1", name: "mi-api", model: "claude-opus-5-5",
                           tokens: 910_000, window: window, isInteractive: true),
                SessionRow(id: "demo-2", name: "portafolio", model: "claude-sonnet-5-5",
                           tokens: 400_000, window: window, isInteractive: true),
            ],
            background: [
                SessionRow(id: "demo-3", name: "suite-pruebas", model: "claude-opus-5-5",
                           tokens: 580_000, window: window, isInteractive: false,
                           jobId: "d3m0b9f2", cwd: "/tmp/demo/suite-pruebas"),
            ],
            limits: UsageLimits(
                fiveHour: LimitWindow(utilization: 78, resetsAt: now.addingTimeInterval(2 * 3600)),
                sevenDay: LimitWindow(utilization: 31, resetsAt: now.addingTimeInterval(4 * 86400))),
            limitsUpdatedAt: now.addingTimeInterval(-120))
    }
}
