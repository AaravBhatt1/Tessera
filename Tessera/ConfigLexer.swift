//
//  ConfigLexer.swift
//  Tessera
//
//  Created by Aarav Bhatt on 28/06/2026.
//

import Foundation
// TODO: Support for more basic language features like conditions (e.g. where window isBiggerThan ...)
enum Token : Equatable {
    case when
    case appIs
    case contentContains
    case set
    case and
    case or
    case not
    case isBiggerThan
    case isSmallerThan
    case isLeftOf
    case isRightOf
    case isAbove
    case isBelow
    case isLandscape
    case isPortrait
    case hasTag
    case hasDynamicTag
    case comma
    case colon
    case pipe
    case openBracket
    case closeBracket
    case identifier(id : String)
    case integer(num : Int)
    case percentage(num : Int)
    case string(value : String)
}

extension Token : CustomStringConvertible {
    nonisolated var description : String {
        switch self {
        case .when: return "when"
        case .appIs: return "appIs"
        case .contentContains: return "contentContains"
        case .set: return "set"
        case .and: return "and"
        case .or: return "or"
        case .not: return "not"
        case .isBiggerThan: return "isBiggerThan"
        case .isSmallerThan: return "isSmallerThan"
        case .isLeftOf: return "isLeftOf"
        case .isRightOf: return "isRightOf"
        case .isAbove: return "isAbove"
        case .isBelow: return "isBelow"
        case .isLandscape: return "isLandscape"
        case .isPortrait: return "isPortrait"
        case .hasTag: return "hasTag"
        case .hasDynamicTag: return "hasDynamicTag"
        case .comma: return ","
        case .colon: return ":"
        case .pipe: return "|"
        case .openBracket: return "("
        case .closeBracket: return ")"
        case .identifier(let id): return "identifier '\(id)'"
        case .integer(let num): return "integer \(num)"
        case .percentage(let num): return "percentage \(num)%"
        case .string(let value): return "string \"\(value)\""
        }
    }
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
        case "when"           : token = .when
        case "appIs"          : token = .appIs
        case "contentContains": token = .contentContains
        case "set"            : token = .set
        case "and"            : token = .and
        case "or"             : token = .or
        case "not"            : token = .not
        case "isBiggerThan"   : token = .isBiggerThan
        case "isSmallerThan"  : token = .isSmallerThan
        case "isLeftOf"       : token = .isLeftOf
        case "isRightOf"      : token = .isRightOf
        case "isAbove"        : token = .isAbove
        case "isBelow"        : token = .isBelow
        case "isLandscape"    : token = .isLandscape
        case "isPortrait"     : token = .isPortrait
        case "hasTag"         : token = .hasTag
        case "hasDynamicTag"  : token = .hasDynamicTag
        default:
            if match.isEmpty {
                if remainder.isEmpty { return nil }
                let punctuation = remainder.removeFirst()
                switch (punctuation) {
                case "," : token = .comma
                case ":" : token = .colon
                case "|" : token = .pipe
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
                    remainder = remainder[match.endIndex...]
                    if remainder.first == "%" {
                        remainder.removeFirst()
                        return .percentage(num: num)
                    }
                    return .integer(num: num)
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
