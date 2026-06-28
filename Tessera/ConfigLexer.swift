//
//  ConfigLexer.swift
//  Tessera
//
//  Created by Aarav Bhatt on 28/06/2026.
//

import Foundation

// TODO: Support for more basic language features like conditions (e.g. where window isBiggerThan ...)
enum Token : Equatable {
    case select
    case set
    case then
    case and
    case or
    case hasMinimumSize
    case hasMaximumSize
    case isLeftOf
    case isRightOf
    case isAbove
    case isBelow
    case comma
    case openBracket
    case closeBracket
    case identifier(id : String)
    case integer(num : Int)
    case string(value : String)
}

struct ConfigLexer {
    // Use substring because Swift's string support is weird
    private var remainder : Substring
    
    init(input : String) {
        self.remainder = Substring(input)
    }
    
    // Remove whitespace from the start of remainder
    private mutating func skipWhitespace() {
        while let char = remainder.first, char.isWhitespace {
            remainder.removeFirst()
        }
        
    }
    
    mutating func nextToken() -> Token? {
        skipWhitespace()
        
        let match : Substring = remainder.prefix(while: {$0.isLetter || $0.isNumber || $0 == "_"})
        
        let token : Token
        
        switch (match) {
        case "select"         : token = .select
        case "set"            : token = .set
        case "then"           : token = .then
        case "and"            : token = .and
        case "or"             : token = .or
        case "hasMinimumSize" : token = .hasMinimumSize
        case "hasMaximumSize" : token = .hasMaximumSize
        case "isLeftOf"       : token = .isLeftOf
        case "isRightOf"      : token = .isRightOf
        case "isAbove"        : token = .isAbove
        case "isBelow"        : token = .isBelow
        default:
            if match.isEmpty {
                if remainder.isEmpty { return nil }
                let punctuation = remainder.removeFirst()
                switch (punctuation) {
                case "," : token = .comma
                case "(" : token = .openBracket
                case ")" : token = .closeBracket
                case "\"":
                    let body = remainder.prefix(while: { $0 != "\"" })
                    remainder = remainder[body.endIndex...]
                    if remainder.first == "\"" { remainder.removeFirst() }
                    token = .string(value: String(body))
                default: return nil
                }
                return token
                
            } else {
                if match.first!.isLetter && match.first!.isLowercase {
                    token = .identifier(id: String(match))
                }
                else if let num : Int = Int(match) {
                    token = .integer(num : num)
                }
                else {
                    return nil
                }
            }
        }
        
        remainder = remainder[match.endIndex...]
        
        return token
    }
}
