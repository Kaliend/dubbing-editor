import AVFoundation
import AppKit
import SwiftUI

@MainActor
final class DetachedVideoWindowPresenter: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DetachedVideoWindowPresenter()

    @Published private(set) var isPresented = false

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

    func show(player: AVPlayer, hasLoadedVideo: Bool) {
        if let window {
            updateRootView(player: player, hasLoadedVideo: hasLoadedVideo)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isPresented = true
            return
        }

        let hostingController = NSHostingController(
            rootView: AnyView(
                DetachedVideoWindowContent(player: player, hasLoadedVideo: hasLoadedVideo)
            )
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Video"
        window.setContentSize(NSSize(width: 1280, height: 720))
        window.minSize = NSSize(width: 720, height: 405)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.hostingController = hostingController
        self.window = window
        isPresented = true

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        guard let window else { return }
        window.orderOut(nil)
        window.close()
    }

    func toggle(player: AVPlayer, hasLoadedVideo: Bool) {
        if isPresented {
            hide()
        } else {
            show(player: player, hasLoadedVideo: hasLoadedVideo)
        }
    }

    func refresh(player: AVPlayer, hasLoadedVideo: Bool) {
        guard isPresented else { return }
        updateRootView(player: player, hasLoadedVideo: hasLoadedVideo)
    }

    func windowWillClose(_ notification: Notification) {
        isPresented = false
        window?.delegate = nil
        window = nil
        hostingController = nil
    }

    private func updateRootView(player: AVPlayer, hasLoadedVideo: Bool) {
        hostingController?.rootView = AnyView(
            DetachedVideoWindowContent(player: player, hasLoadedVideo: hasLoadedVideo)
        )
    }
}

private struct DetachedVideoWindowContent: View {
    let player: AVPlayer
    let hasLoadedVideo: Bool

    var body: some View {
        Group {
            if hasLoadedVideo {
                PlayerContainerView(player: player)
                    .equatable()
                    .background(Color.black)
            } else {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.black)
                    .overlay {
                        VStack(spacing: 8) {
                            Text("Neni nactene video")
                                .foregroundStyle(.white)
                            Text("Importuj video v hlavnim okne editoru.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
