/*

	String+.swift

	Created By: Jacob Williams
	Description: Adds useful functionality to Strings
	License: MIT License

*/

import Foundation

extension String {
    /// A randomly generated, unique string of 64 characters
    public static var uniq: String {
        let letters : NSString = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        #if os(Linux)
        let len = letters.length
        #else
        let len = UInt32(letters.length)
        #endif

        var randomString = ""

        for _ in 1...64 {
            #if os(Linux)
            let rand = random() % len
            #else
            let rand = arc4random_uniform(len)
            #endif
            var nextChar = letters.character(at: Int(rand))
            randomString += String(nextChar)
        }
        return randomString
    }

    /**
     Checks if a string ends with a specified string
     - Parameter string: The string to test against
     - Returns: A Boolean indicating whether or not the string ends in the specified parameter string
    */  
    public func ends(with string: String) -> Bool {
        if string.characters.count > characters.count {
            return false
        }
        let ending = substring(from: string.characters.count * -1)
        return ending == string
    }

    /**
     Checks if a string starts with a specified string
     - Parameter string: The string to test against
     - Returns: A Boolean indicating whether or not the string starts in the specified parameter string
     */ 
    public func starts(with string: String) -> Bool {
        if string.characters.count > characters.count {
            return false
        }
        let beginning = substring(to: string.characters.count)
        return beginning == string
    }

	public func dropFirst() -> String {
        return substring(from: 1)
    }

	public func dropLast() -> String {
        return substring(to: -2)
    }

    public func substring(from: Int = 0, to: Int = -1) -> String {
        let to = to == -1 ? characters.count : to
        var startIdx: String.Index
        var endIdx: String.Index
        if from == 0 {
            startIdx = startIndex
        } else {
            startIdx = index(startIndex, offsetBy: from)
        }
        if to == characters.count {
            endIdx = endIndex
        } else {
            endIdx = index(startIndex, offsetBy: to)
        }
        let range = startIdx..<endIdx
        return substring(with: range)
    }
}
