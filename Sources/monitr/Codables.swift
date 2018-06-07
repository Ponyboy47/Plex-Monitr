import PathKit
import Cron
import Foundation
import SwiftyBeaver

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

extension SwiftyBeaver.Level: Codable {
    public static func > (lhs: SwiftyBeaver.Level, rhs: Int) -> Bool {
        return lhs.rawValue > rhs
    }
}

extension SizeTarget: Codable {}

extension VideoProfile: Codable {}

enum TargetError: Error {
    case invalid
}

extension Target: Codable {
    enum CodingKeys: String, CodingKey {
        case size
        case profile
        case bitRate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        if let profile = try values.decodeIfPresent(VideoProfile.self, forKey: .profile),
           let bitRate = try values.decodeIfPresent(Int.self, forKey: .bitRate) {
               rawValue = .bitRate(profile, bitRate)
        } else if let size = try values.decodeIfPresent(SizeTarget.self, forKey: .size) {
            rawValue = .size(size)
        } else {
            throw TargetError.invalid
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch rawValue {
        case .size(let size): try container.encode(size, forKey: .size)
        case .bitRate(let profile, let bitRate):
            try container.encode(profile, forKey: .profile)
            try container.encode(bitRate, forKey: .bitRate)
        }
    }
}

extension TranscodeSpeed: Codable {}

extension X264Preset: Codable {}
