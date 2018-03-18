import PathKit
import Cron
import Foundation

extension Path: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self = Path(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.absolute.string)
    }

    public func decode<T>(with decoder: JSONDecoder, to type: T.Type) throws -> T where T: Decodable {
        let str: String = try self.read()
        return try decoder.decode(type, from: str.data(using: .utf8)!)
    }
}

extension Cron.Date: Codable {
    enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
        case hour
        case minute
        case second
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        year = try values.decode(Int.self, forKey: .year)
        month = try values.decode(Int.self, forKey: .month)
        day = try values.decode(Int.self, forKey: .day)
        hour = try values.decode(Int.self, forKey: .hour)
        minute = try values.decode(Int.self, forKey: .minute)
        second = try values.decode(Int.self, forKey: .second)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(day, forKey: .day)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
        try container.encode(second, forKey: .second)
    }
}

extension Cron.DatePattern: Codable {
    enum CodingKeys: String, CodingKey {
        case pattern
        case hash
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let p = try DatePattern(values.decode(String.self, forKey: .pattern))

        self.second     = p.second
        self.minute     = p.minute
        self.hour       = p.hour
        self.dayOfMonth = p.dayOfMonth
        self.month      = p.month
        self.dayOfWeek  = p.dayOfWeek
        self.year       = p.year
        self.hash       = try values.decode(Int64.self, forKey: .hash)
        self.string     = p.string
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(string, forKey: .pattern)
        try container.encode(hash, forKey: .hash)
    }
}

extension QualityOfService: Codable {}
