import PathKit
import Async
import SwiftyBeaver
import Cron
import JSON

enum ConversionError: Error {
    case maxThreadsReached
}

struct ConversionQueue {
    static let filename: String = "conversionqueue.json"

    fileprivate var configPath: Path
    fileprivate var cronStart: Cron.DatePattern
    fileprivate var cronEnd: Cron.DatePattern
    fileprivate var statistics: Statistic
    fileprivate var maxThreads: Int
    fileprivate var deleteOriginal: Bool
    fileprivate var log: SwiftyBeaver.Type

    fileprivate var jobs: [BaseMedia] = []
    fileprivate var activeJobs: [BaseMedia] = []

    var active: Int {
        return activeJobs.count
    }

    init(_ config: Config, statistics stats: Statistic? = nil) {
        configPath = config.configFile
        // Ignore errors here, if the cron string were invalid then the config
        // object would have already thrown an error
        cronStart = try! Cron.parseExpression(config.convertCronStart)
        cronEnd = try! Cron.parseExpression(config.convertCronEnd)
        maxThreads = config.convertThreads
        deleteOriginal = config.deleteOriginal
        if stats != nil {
            statistics = stats!
        } else {
            statistics = Statistic()
        }
        log = config.log
    }

    /// Adds a new Media object to the list of media items to convert
    mutating func push(_ job: BaseMedia) {
        jobs.append(job)
    }

    @discardableResult
    mutating fileprivate func pop() -> BaseMedia {
        let j = jobs.removeFirst()
        activeJobs.append(j)
        return j
    }

    mutating func startNextConversion() throws {
        guard active < maxThreads else {
            throw ConversionError.maxThreadsReached
        }
        let next = pop()
        statistics.measure(.convert) {
            do {
                try next.convert(log)
            } catch {
                log.warning("Error while converting media: \(next.path)")
                log.error(error)
            }
        }
    }
}

extension ConversionQueue: JSONInitializable {
    init(json: JSON) throws {
        let configFile = Path(try json.get("configPath"))
        let configString: String = try configFile.read()
        let configJSON: JSON = try JSON.Parser.parse(configString)
        config = try Config(json: configJSON)
        self.init(config)
        jobs = ConversionQueue.setupJobs(try json.get("jobs"))
    }

    private static func setupJobs(_ jobs: [BaseMedia]) -> [BaseMedia] {
        var conversions: [BaseMedia] = []
        for job in jobs {
            if job is Video {
                conversions.append((job as! Video))
            } else if job is Audio {
                conversions.append((job as! Audio))
            } else if job is Subtitle {
                conversions.append((job as! Subtitle))
            } else {
                conversions.append((job as! Ignore))
            }
        }
        return conversions
    }
}

extension ConversionQueue: JSONRepresentable {
    public func encoded() -> JSON {
        return [
            "configPath": configPath.string,
            "jobs": jobs.encoded()
        ]
    }
}
