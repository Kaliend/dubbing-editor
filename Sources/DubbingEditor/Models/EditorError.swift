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
            return String(localized: "error.word_read")
        case .missingWordDocumentXML:
            return String(localized: "error.word_missing_xml")
        case .unableToParseWordXML:
            return String(localized: "error.word_parse")
        case .noDialogueLinesFound:
            return String(localized: "error.word_no_lines")
        case .unableToBuildDocx:
            return String(localized: "error.word_build_docx")
        case .noAudioTrack:
            return String(localized: "error.no_audio_track")
        }
    }
}
