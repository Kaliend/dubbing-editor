import Foundation

enum EditorError: LocalizedError {
    case unableToReadWordFile
    case missingWordDocumentXML
    case unableToParseWordXML
    case noDialogueLinesFound
    case unableToBuildDocx
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .unableToReadWordFile:
            return String(localized: "error.word_read", bundle: .appBundle)
        case .missingWordDocumentXML:
            return String(localized: "error.word_missing_xml", bundle: .appBundle)
        case .unableToParseWordXML:
            return String(localized: "error.word_parse", bundle: .appBundle)
        case .noDialogueLinesFound:
            return String(localized: "error.word_no_lines", bundle: .appBundle)
        case .unableToBuildDocx:
            return String(localized: "error.word_build_docx", bundle: .appBundle)
        case .noAudioTrack:
            return String(localized: "error.no_audio_track", bundle: .appBundle)
        }
    }
}
