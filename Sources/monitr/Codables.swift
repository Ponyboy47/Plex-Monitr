import PathKit
import Cron
import Foundation
import Dispatch
#if os(Linux)
import CDispatch
typealias qos_class_t = dispatch_qos_class_t

internal enum _OSQoSClass : UInt32  {
	case QOS_CLASS_USER_INTERACTIVE = 0x21
	case QOS_CLASS_USER_INITIATED = 0x19
	case QOS_CLASS_DEFAULT = 0x15
	case QOS_CLASS_UTILITY = 0x11
	case QOS_CLASS_BACKGROUND = 0x09
	case QOS_CLASS_UNSPECIFIED = 0x00

	internal init?(qosClass: dispatch_qos_class_t) {
		switch qosClass {
		case 0x21: self = .QOS_CLASS_USER_INTERACTIVE
		case 0x19: self = .QOS_CLASS_USER_INITIATED
		case 0x15: self = .QOS_CLASS_DEFAULT
		case 0x11: self = .QOS_CLASS_UTILITY
		case 0x09: self = .QOS_CLASS_BACKGROUND
		case 0x00: self = .QOS_CLASS_UNSPECIFIED
		default: return nil
		}
	}
}
#endif

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
        return try decoder.decode(type, from: self.read()) 
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

extension DispatchQoS: Codable {
    enum CodingKeys: String, CodingKey {
        case qosClass
        case relativePriority
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        qosClass = try values.decode(DispatchQoS.QoSClass.self, forKey: .qosClass)
        relativePriority = try values.decode(Int.self, forKey: .relativePriority)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(qosClass, forKey: .qosClass)
        try container.encode(relativePriority, forKey: .relativePriority)
    }
}

extension DispatchQoS.QoSClass: Codable {
    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
		#if !os(Linux)
        self.init(rawValue: try values.decode(qos_class_t.self))!
        #else
        self = _OSQoSClass(rawValue: try values.decode(qos_class_t.self)) as! DispatchQoS.QoSClass
		#endif
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self)
    }
}

#if !os(Linux)
extension qos_class_t: Codable {}
#endif
