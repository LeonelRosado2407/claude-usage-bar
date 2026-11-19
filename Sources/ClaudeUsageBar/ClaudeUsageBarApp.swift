import AppKit
import ServiceManagement
import SwiftUI
import UsageCore

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var poller: Poller

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-demo"), i + 1 < args.count {
            let lang = args.firstIndex(of: "--lang").flatMap { j in
                j + 1 < args.count ? AppLanguage(rawValue: args[j + 1]) : nil } ?? .es
            DemoRenderer.render(to: URL(fileURLWithPath: args[i + 1]), language: lang)
            exit(0)
        }
        let demo = args.contains("--demo")
        let config = demo ? AppConfig() : AppConfig.loadOrCreate(at: AppConfig.defaultURL)
        _poller = StateObject(wrappedValue: Poller(config: config, demo: demo, configURL: AppConfig.defaultURL))

        if Bundle.main.bundleIdentifier != nil {
            Notifier.requestAuthorization()
            try? SMAppService.mainApp.register()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(poller: poller)
        } label: {
            Image(nsImage: MenuBarLabel.image(for: poller.snapshot, config: poller.config))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Renders the menu bar text as a non-template image so it can carry color
/// (SwiftUI strips foreground colors from menu bar labels).
enum MenuBarLabel {
    static func image(for snapshot: Snapshot, config: AppConfig) -> NSImage {
        var text = snapshot.barTitle
        if snapshot.hasContextWarning(config: config) { text += " ⚠" }

        let color: NSColor
        switch snapshot.barLevel(config: config) {
        case .normal: color = .labelColor
        case .warn: color = .systemYellow
        case .critical: color = .systemRed
        }
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ])
        let size = attributed.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: 18), flipped: false) { rect in
            attributed.draw(at: NSPoint(x: 0, y: (rect.height - size.height) / 2))
            return true
        }
        // Normal state follows the menu bar's light/dark appearance; colored states keep their color.
        image.isTemplate = snapshot.barLevel(config: config) == .normal
        return image
    }
}
