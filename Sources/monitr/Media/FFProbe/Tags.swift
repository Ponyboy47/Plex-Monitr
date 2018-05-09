import Foundation

enum Language: String, Codable {
    case eng // English
    case spa // Spanish
    case ita // Italian
    case fre // French
    case fin // Finnish
    case ger // German
    case por // Portuguese
    case dut // Dutch
    case jap // Japanese
    case chi // Chinese
    case rus // Russian
    case per // Persian
    case und // Undetermined
}

struct Tags: Codable {
    var language: Language?
    var handler: String?
    var creation: Date?
    var creationFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    enum CodingKeys: String, CodingKey {
        case language
        case handler = "handler_name"
        case creation = "creation_time"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        language = try values.decodeIfPresent(Language.self, forKey: .language)
        handler = try values.decodeIfPresent(String.self, forKey: .handler)
        if let creationString = try values.decodeIfPresent(String.self, forKey: .creation) {
            creation = creationFormatter.date(from: creationString)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(handler, forKey: .handler)
        if let creation = creation {
            try container.encodeIfPresent(creationFormatter.string(from: creation), forKey: .creation)
        }
    }
}
