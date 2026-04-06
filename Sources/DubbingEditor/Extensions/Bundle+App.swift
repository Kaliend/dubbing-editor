import Foundation

extension Bundle {
    static let appBundle: Bundle = {
        let bundleName = "DubbingEditor_DubbingEditor"
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.executableURL?.deletingLastPathComponent()
        ]
        for case let candidate? in candidates {
            let url = candidate.appendingPathComponent(bundleName + ".bundle")
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }()
}
