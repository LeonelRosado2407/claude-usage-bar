import AppKit
import SwiftUI
import UsageCore

/// `--render-demo <file.png> [--lang en]`: draws the menu bar label and panel with fictional data,
/// for README screenshots (no screen-recording permission needed).
@MainActor
enum DemoRenderer {
    static func render(to url: URL, language: AppLanguage = .es) {
        var config = AppConfig()
        config.language = language
        let poller = Poller(config: config, demo: true)
        let view = VStack(alignment: .trailing, spacing: 8) {
            Image(nsImage: MenuBarLabel.image(for: poller.snapshot, config: poller.config))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            PanelView(poller: poller)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
