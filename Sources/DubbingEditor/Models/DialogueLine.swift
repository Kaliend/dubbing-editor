import Foundation

struct DialogueLine: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var index: Int
    var speaker: String
    var text: String
    var startTimecode: String
    var endTimecode: String

    init(
        id: UUID = UUID(),
        index: Int,
        speaker: String = "",
        text: String,
        startTimecode: String = "",
        endTimecode: String = ""
    ) {
        self.id = id
        self.index = index
        self.speaker = speaker
        self.text = text
        self.startTimecode = startTimecode
        self.endTimecode = endTimecode
    }
}
