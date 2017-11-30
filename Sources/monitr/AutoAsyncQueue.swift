//
//  AutoQueue.swift
//  Plex-MonitrPackageDescription
//
//  Created by Jacob Williams on 11/20/17.
//

import Dispatch
import SwiftyBeaver
import Foundation
import PathKit

final class AutoAsyncQueue<T: Equatable & Codable>: Collection, Codable {
    typealias Index = Int
    typealias AutoAsyncCallback = (T) -> Void

    var startIndex: Index {
        return self.queue.startIndex
    }
    var endIndex: Index {
        return self.queue.endIndex
    }
    private var _queue: [T] = []
    var queue: [T] {
        get {
            return self._queue
        }
        set {
            self._queue = newValue
            self.check()
        }
    }
    var upNext: [T] = []
    var active: [T] = []
    private var callback: AutoAsyncCallback?
    private var dispatchQueue: DispatchQueue
    private var run: Bool = false
    private var maxSimultaneous: Int
    private var logger: SwiftyBeaver.Type?
    private var group: DispatchGroup = DispatchGroup()

    subscript(position: Index) -> T {
        return self.queue[position]
    }
    func index(after index: Index) -> Index {
        return index + 1
    }

    private enum CodingKeys: CodingKey {
        case queue
        case upNext
        case qos
        case maxSimultaneous
    }

    init(maxSimultaneous: Int, qos: DispatchQoS = .utility, logger: SwiftyBeaver.Type, callback: @escaping AutoAsyncCallback) {
        self.maxSimultaneous = maxSimultaneous
        self.dispatchQueue = DispatchQueue(label: "AutoAsyncQueue", qos: qos, attributes: .concurrent)
        self.callback = callback
        self.logger = logger
    }

    /// Initializes by reading the file at the path as a JSON string
    init(fromFile file: Path, with logger: SwiftyBeaver.Type, callback: @escaping AutoAsyncCallback) throws {
        let other = try file.decode(with: JSONDecoder(), to: AutoAsyncQueue.self)
        maxSimultaneous = other.maxSimultaneous
        dispatchQueue = other.dispatchQueue
        queue = other.queue
        upNext = other.upNext
        self.logger = logger
        self.callback = callback
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        maxSimultaneous = try values.decode(Int.self, forKey: .maxSimultaneous)
        dispatchQueue = DispatchQueue(label: "AutoAsyncQueue", qos: try values.decode(DispatchQoS.self, forKey: .qos), attributes: .concurrent)
        queue = try values.decode([T].self, forKey: .queue)
        upNext = try values.decode([T].self, forKey: .upNext)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(maxSimultaneous, forKey: .maxSimultaneous)
        try container.encode(dispatchQueue.qos, forKey: .qos)
        try container.encode(queue, forKey: .queue)
        try container.encode(upNext, forKey: .upNext)
    }

    func start() {
        self.logger?.verbose("Starting Queue Execution")
        run = true
        check()
    }

    func stop() {
        run = false
    }

    func wait() {
        self.logger?.verbose("Waiting for Dispatch Group to complete")
        self.group.wait()
    }

    private func check() {
        guard run else { return }
        while active.count + upNext.count < maxSimultaneous && !queue.isEmpty {
            self.logger?.verbose("Adding an item to the upNext array")
            upNext.append(queue.remove(at: 0))
        }
        if active.count < maxSimultaneous && upNext.count > 0 {
            self.logger?.verbose("Empty slots in the active array being filled by the upNext array")
            runUpNext()
        }
    }

    private func runUpNext() {
        guard run else { return }
        while !upNext.isEmpty {
            let item = upNext.remove(at: 0)
            active.append(item)
            dispatchQueue.async(group: self.group) {
                self.callback?(item)
                guard let index = self.active.index(where: { (elem: T) -> Bool in
                    return elem == item
                }) else {
                    print("Something very wrong has occurred and the item cannot be found in the active array")
                    return
                }
                self.active.remove(at: index)
                self.check()
            }
        }
    }

    func append(_ newElement: T) {
        self.logger?.verbose("Appending new element to queue")
        self.queue.append(newElement)
    }

    func save(to file: Path) throws {
        let data = try JSONEncoder().encode(self)
        let str = String(data: data, encoding: .utf8)!
        try file.write(str, force: true)
    }
}
