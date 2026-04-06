import AppKit
import SwiftUI

enum SettingsWindowPresenter {
    private static var window: NSWindow?
    private static var hostingController: NSHostingController<AnyView>?

    static func show(model: EditorViewModel) {
        if let window {
            hostingController?.rootView = AnyView(
                AppSettingsWindowContainer(model: model)
                    .frame(width: 640, height: 560)
            )
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = AnyView(
            AppSettingsWindowContainer(model: model)
                .frame(width: 640, height: 560)
        )
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Nastaveni"
        window.setContentSize(NSSize(width: 640, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .disallowed
        window.center()
        window.isReleasedWhenClosed = false

        self.hostingController = hostingController
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
