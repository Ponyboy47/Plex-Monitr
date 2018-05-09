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

extension QualityOfService: Codable {}
