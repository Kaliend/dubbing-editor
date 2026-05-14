import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("DubbingEditor_DubbingEditor.bundle").path
        let buildPath = "/Users/philipkiulpekidis/Dropbox/Filmy/Aplikace/Uprava/.build-arm64/arm64-apple-macosx/release/DubbingEditor_DubbingEditor.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}