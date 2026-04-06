import AppKit
import Foundation

enum WindowSnapshotService {
    @MainActor
    static func captureMainWindowPNGData() -> Data? {
        let candidateWindows = [
            NSApp.mainWindow,
            NSApp.keyWindow
        ].compactMap { $0 } + NSApp.windows

        guard let targetView = candidateWindows.compactMap(\.contentView).first else {
            return nil
        }

        let bounds = targetView.bounds
        guard !bounds.isEmpty else { return nil }
        guard let bitmap = targetView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        targetView.cacheDisplay(in: bounds, to: bitmap)
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }
}
