import PathKit
import Duration
import Cron
import Foundation

extension Array where Element == Double {
    func avg() -> Double? {
        guard self.count > 0 else { return nil }
        var total: Double = 0.0
        for d in self {
            total += d
        }
        return total / Double(self.count)
    }
}

extension Array where Element == Statistic.Event {
    func avg() -> Double? {
        return self.flatMap({ $0.duration }).avg()
    }

    func min() -> Double? {
        return self.flatMap({ $0.duration }).min()
    }

    func max() -> Double? {
        return self.flatMap({ $0.duration }).max()
    }
}

enum StatisticsError: Error {
    case pathIsNotDirectory(Path)
}

enum Statistics: String {
    case startup
    case move
    case convert
    case lifespan
}

struct Statistic: Codable {
    struct Event: Codable {
        var start: Cron.Date = Cron.Date()
        var finish: Cron.Date?
        var success: Bool?
        var duration: Double?

        enum CodingKeys: String, CodingKey {
            case start
            case finish
            case success
            case duration
        }

        init() {}

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            start = try values.decode(Cron.Date.self, forKey: .start)
            finish = try values.decodeIfPresent(Cron.Date.self, forKey: .finish)
            success = try values.decodeIfPresent(Bool.self, forKey: .success)
            duration = try values.decodeIfPresent(Double.self, forKey: .duration)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(start, forKey: .start)
            try container.encodeIfPresent(duration, forKey: .duration)
            try container.encodeIfPresent(success, forKey: .success)
            try container.encodeIfPresent(finish, forKey: .finish)
        }
    }

    static let filename: Path = "statistics.json"

    // From the moment the executable is ran, to the first run on the monitr
    var shortestStartup: Double {
        return startups.min() ?? 0.0
    }
    var longestStartup: Double {
        return startups.max() ?? 0.0
    }
    var averageStartup: Double {
        return startups.avg() ?? 0.0
    }
    fileprivate var startups: [Event] = []

    // Moving media from the downloads directory to the plex directory
    var shortestMove: Double {
        return moves.min() ?? 0.0
    }
    var longestMove: Double {
        return moves.max() ?? 0.0
    }
    var averageMove: Double {
        return moves.avg() ?? 0.0
    }
    fileprivate var moves: [Event] = []

    // Converting a single media file
    var shortestConversion: Double {
        return conversions.min() ?? 0.0
    }
    var longestConversion: Double {
        return conversions.min() ?? 0.0
    }
    var averageConversion: Double {
        return conversions.avg() ?? 0.0
    }
    fileprivate var conversions: [Event] = []

    // The lifespan of the monitr application
    var shortestLife: Double {
        return lifespans.min() ?? 0.0
    }
    var longestLife: Double {
        return lifespans.max() ?? 0.0
    }
    var averageLife: Double {
        return lifespans.avg() ?? 0.0
    }
    fileprivate var lifespans: [Event] = []

    init() {
        Duration.pushLogStyle(style: .none)
    }

    enum CodingKeys: String, CodingKey {
        case startups
        case moves
        case conversions
        case lifespans
    }

    init(_ path: Path) throws {
        self = try path.decode(with: JSONDecoder(), to: Statistic.self)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        startups = try values.decode([Event].self, forKey: .startups)
        moves = try values.decode([Event].self, forKey: .moves)
        conversions = try values.decode([Event].self, forKey: .conversions)
        lifespans = try values.decode([Event].self, forKey: .lifespans)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startups, forKey: .startups)
        try container.encode(moves, forKey: .moves)
        try container.encode(conversions, forKey: .conversions)
        try container.encode(lifespans, forKey: .lifespans)
    }

    func save(_ dir: Path) throws {
        if !dir.exists {
            try dir.mkpath()
        }

        guard dir.isDirectory else {
            throw StatisticsError.pathIsNotDirectory(dir)
        }

        let statisticsPath = dir + Statistic.filename
        let data = try JSONEncoder().encode(self)
        try statisticsPath.write(data, force: true)
    }

    public func measure(_ statKey: Statistics, _ block: MeasuredBlock) {
        var event = Event()
        event.duration = Duration.measure(UUID().description, block: block)
        event.finish = Cron.Date()

        var stat = self[statKey]
        stat.append(event)
    }

    public subscript(_ key: Statistics) -> [Event] {
        switch key {
        case .startup:
            return startups
        case .move:
            return moves
        case .convert:
            return conversions
        case .lifespan:
            return lifespans
        }
    }
}
