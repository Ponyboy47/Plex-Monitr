//
//  MediaOperation+Queue.swift
//
//  Created by Jacob Williams on 03/01/18
//

import Foundation
import PathKit

final class MediaOperationQueue: OperationQueue, Codable {
    private enum CodingKeys: String, CodingKey {
        case maxConcurrentOperationCount
        case operations
        case qualityOfService
        case name
        case isSuspended
    }

    init(_ maxConcurrent: Int) {
        super.init()
        self.maxConcurrentOperationCount = maxConcurrent
    }

    init(from file: Path) throws {
        super.init()
        let other = try file.decode(with: JSONDecoder(), to: MediaOperationQueue.self)
        self.maxConcurrentOperationCount = other.maxConcurrentOperationCount
        self.addOperations(other.operations, waitUntilFinished: false)
    }

    init(from decoder: Decoder) throws {
        super.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)

        name = try values.decodeIfPresent(String.self, forKey: .name)
        maxConcurrentOperationCount = try values.decode(Int.self, forKey: .maxConcurrentOperationCount)
        qualityOfService = try values.decode(QualityOfService.self, forKey: .qualityOfService)
        isSuspended = try values.decode(Bool.self, forKey: .isSuspended)
        if let videoOperations = try? values.decode([MediaOperation<Video>].self, forKey: .operations) {
            addOperations(videoOperations, waitUntilFinished: false)
        }
        if let audioOperations = try? values.decode([MediaOperation<Audio>].self, forKey: .operations) {
            addOperations(audioOperations, waitUntilFinished: false)
        }
        if let ignoreOperations = try? values.decode([MediaOperation<Ignore>].self, forKey: .operations) {
            addOperations(ignoreOperations, waitUntilFinished: false)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(maxConcurrentOperationCount, forKey: .maxConcurrentOperationCount)
        try container.encode(qualityOfService, forKey: .qualityOfService)
        try container.encode(isSuspended, forKey: .isSuspended)
        // try container.encode(operations, forKey: .operations)
    }

    func save(to file: Path) throws {
    }
}
