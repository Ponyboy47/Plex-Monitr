/*

 IgnoredMedia.swift

 Created By: Jacob Williams
 Description: This file contains the Ignored media structure for easy management of downloaded files
 License: MIT License

 */

import Foundation
import PathKit
import Downpour
import SwiftyBeaver
import JSON

/// Management for media types that we don't care about and can just delete
final class Ignore: BaseMedia {
    enum SupportedExtension: String {
        case txt; case png; case jpg; case jpeg
        case gif; case rst; case md; case nfo
        case sfv; case sub; case idx; case css
        case js; case htm; case html; case url
        case php; case md5; case doc; case docx
        case rtf; case db
    }

    override var plexName: String {
        return path.lastComponentWithoutExtension
    }
    override var finalDirectory: Path {
        return "/dev/null"
    }

    required init(_ path: Path) throws {
        if !path.string.lowercased().contains("sample") && !path.string.lowercased().contains(".ds_store") {
            guard Ignore.isSupported(ext: path.extension ?? "") else {
                throw MediaError.unsupportedFormat(path.extension ?? "")
            }
        }
        try super.init(path)
    }

    /// JSONInitializable protocol requirement
    required init(json: JSON) throws {
        let p = Path(try json.get("path"))
        if !p.string.lowercased().contains("sample") && !p.string.lowercased().contains(".ds_store") {
            guard Ignore.isSupported(ext: p.extension ?? "") else {
                throw MediaError.unsupportedFormat(p.extension ?? "")
            }
        }
        try super.init(json: json)
    }

    override func move(to plexPath: Path, log: SwiftyBeaver.Type) throws {
        log.verbose("Deleting ignorable file: \(path.string)")
        try path.delete()
        path = ""
    }

    override class func isSupported(ext: String) -> Bool {
        guard let _ = SupportedExtension(rawValue: ext.lowercased()) else {
            return false
        }
        return true
    }
}
