//
//  MediaOperation+Base.swift
//
//  Created by Jacob Williams on 03/01/18
//

import Foundation
import SwiftyBeaver

class MediaOperation<MediaType: Media>: Operation, Codable {
    var media: MediaType
    var logger: SwiftyBeaver.Type!

    override var isReady: Bool {
        return dependencies.reduce(true) { value, dependency in
            return dependency.isFinished && value
        }
    }

    enum CodingKeys: CodingKey {
        case media
    }

    override init() {
        fatalError("Cannot initialize using the default initializer")
    }

    init(_ media: MediaType, logger: SwiftyBeaver.Type) {
        self.media = media
        self.logger = logger
        super.init()
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        media = try values.decode(MediaType.self, forKey: .media)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(media, forKey: .media)
    }
}
