import Dispatch
import TaskKit
import SwiftyBeaver

class MediaTask<MediaType: Media>: DependentTask, CustomStringConvertible {
    var media: MediaType
    var logger: SwiftyBeaver.Type!
    var status: TaskStatus = .ready
    var qos: DispatchQoS
    var priority: TaskPriority
    var dependencies: [Task] = []
    var completionBlock: (TaskStatus) -> Void = { _ in }
    var dependencyCompletionBlock: (Task) -> Void {
        return { dependency in
            self.media = (dependency as! MediaTask).media
       }
    }

    var description: String {
        return "\(type(of: self))(id: \(id), media: \(media), state: \(status.state))"
    }

    init(_ media: MediaType, qos: DispatchQoS = .utility, priority: TaskPriority = .minimal, logger: SwiftyBeaver.Type) {
        self.media = media
        self.qos = qos
        self.priority = priority
        self.logger = logger
    }

    func execute() -> Bool {
        fatalError("This must be implemented in subclasses")
    }
}
