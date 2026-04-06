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
            return "Nepodařilo se načíst Word soubor."
        case .missingWordDocumentXML:
            return "Ve Word souboru chybí word/document.xml."
        case .unableToParseWordXML:
            return "Nepodařilo se zpracovat obsah Word dokumentu."
        case .noDialogueLinesFound:
            return "V dokumentu nebyly nalezeny žádné repliky."
        case .unableToBuildDocx:
            return "Nepodařilo se vytvořit výstupní DOCX."
        case .noAudioTrack:
            return "Video neobsahuje audio stopu, waveform nelze zobrazit."
        }
    }
}
