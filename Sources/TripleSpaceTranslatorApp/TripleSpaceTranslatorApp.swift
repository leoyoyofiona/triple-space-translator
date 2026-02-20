import AppKit
import SwiftUI

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let model = AppModel()

    func applicationDidFinishLaunching(_: Notification) {
        let contentView = ContentView()
            .environmentObject(model)
            .frame(minWidth: 560, minHeight: 460)

        let hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "三空格中英互译"
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

@main
@MainActor
struct TripleSpaceTranslatorApp {
    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = appDelegate
        app.run()
    }
}
