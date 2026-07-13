//
//  ConfigParser.swift
//  Tessera
//
//  Created by Aarav Bhatt on 30/06/2026.
//

// LL(1) grammar - draft
// S   :- R $
// R   :- C set E2 W    (variables come from condition + effect getFreeVars())
// W   :- : int | | int | ε  (weight; absence = hard constraint, ':' or '|' = soft with the given weight)
// C   :- when C2 | ε
// C2  :- C3 C2'         -- OR level
// C2' :- or C2 | ε
// C3  :- C4 C3'         -- AND level (binds tighter than OR → DNF by default)
// C3' :- and C3 | ε
// C4  :- ( C2 ) | C5
// C5  :- id appIs str | id contentContains str | id isBiggerThan WS | id isSmallerThan WS | id hasTag str
// E2  :- E3 E2'         -- OR level
// E2' :- or E2 | ε
// E3  :- E4 E3'         -- AND level (binds tighter than OR → DNF by default)
// E3' :- and E3 | ε
// E4  :- ( E2 ) | E5
// E5  :- id E5'
// E5' :- isLeftOf id | isRightOf id | isAbove id | isBelow id | isLandscape | isPortrait | isBiggerThan WS | isSmallerThan WS | hasTag str
// WS  :- ( SV , SV )
// SV  :- int | int %

enum ParseError : Error {
    case unexpected(Token?, expected : String)
    case unexpectedEnd
}

extension ParseError : CustomStringConvertible {
    var description : String {
        switch self {
        case .unexpected(nil, let expected):
            return "expected \(expected) but reached end of line"
        case .unexpected(.some(let token), let expected):
            return "expected \(expected) but found \(token)"
        case .unexpectedEnd:
            return "unexpected end of line"
        }
    }
}

struct ConfigParser {
    private let tokens : [Token]
    private var pos : Int = 0

    init(tokens : [Token]) {
        self.tokens = tokens
    }

    private func peek() -> Token? {
        return pos < tokens.count ? tokens[pos] : nil
    }

    private mutating func advance() -> Token? {
        guard pos < tokens.count else { return nil }
        let t = tokens[pos]
        pos += 1
        return t
    }

    private mutating func expect(_ t : Token, label : String) throws {
        guard let got = advance() else { throw ParseError.unexpectedEnd }
        if got != t { throw ParseError.unexpected(got, expected: label) }
    }

    private mutating func expectIdentifier() throws -> String {
        guard let got = advance() else { throw ParseError.unexpectedEnd }
        if case .identifier(let id) = got { return id }
        throw ParseError.unexpected(got, expected: "identifier")
    }
    
    private mutating func expectString() throws -> String {
        guard let got = advance() else { throw ParseError.unexpectedEnd }
        if case .string(let s) = got {
            return s
        }
        throw ParseError.unexpected(got, expected: "string")
    }

    private mutating func expectInteger() throws -> Int {
        guard let got = advance() else { throw ParseError.unexpectedEnd }
        if case .integer(let n) = got { return n }
        throw ParseError.unexpected(got, expected: "integer")
    }

    private mutating func expectSizeValue() throws -> SizeValue {
        guard let got = advance() else { throw ParseError.unexpectedEnd }
        switch got {
        case .integer(let n): return .absolute(n)
        case .percentage(let n): return .percent(n)
        default: throw ParseError.unexpected(got, expected: "integer or percentage")
        }
    }

    // R :- C set E2 W   (variables derived from condition + effect free vars)
    mutating func parseRule() throws -> Rule {
        let cond = try parseWhenCondition()
        try expect(.set, label: "set")
        let effect = try parseEffect()
        let weight = try parseOptionalWeight()
        var freeVars : Set<String> = []
        effect.getFreeVars(accum: &freeVars)
        cond?.getFreeVars(accum: &freeVars)
        let vars = Array(freeVars).sorted()
        return Rule(variables: vars, condition: cond, effect: effect, weight: weight)
    }

    // W :- : int | | int | ε (nil = hard constraint)
    private mutating func parseOptionalWeight() throws -> Int? {
        guard peek() == .colon || peek() == .pipe else { return nil }
        _ = advance()
        return try expectInteger()
    }

    // C :- when C2 | ε
    private mutating func parseWhenCondition() throws -> ConditionExpr? {
        guard peek() == .when else { return nil }
        _ = advance()
        return try parseConditionExpr()
    }

    // C2 :- C3 (or C2)?
    private mutating func parseConditionExpr() throws -> ConditionExpr {
        let left = try parseConditionAnd()
        if peek() == .or {
            _ = advance()
            let right = try parseConditionExpr()
            return .or(left, right)
        }
        return left
    }

    // C3 :- C4 (and C3)?
    private mutating func parseConditionAnd() throws -> ConditionExpr {
        let left = try parseConditionAtom()
        if peek() == .and {
            _ = advance()
            let right = try parseConditionAnd()
            return .and(left, right)
        }
        return left
    }

    // C4 :- ( C2 ) | C5
    private mutating func parseConditionAtom() throws -> ConditionExpr {
        if peek() == .openBracket {
            _ = advance()
            let inner = try parseConditionExpr()
            try expect(.closeBracket, label: ")")
            return inner
        }
        return try parseAtomicCondition()
    }

    // C5 :- id appIs str | id contentContains str | id isBiggerThan WS | id isSmallerThan WS
    private mutating func parseAtomicCondition() throws -> ConditionExpr {
        let w1 = try expectIdentifier()
        guard let op = advance() else { throw ParseError.unexpectedEnd }
        switch op {
        case .appIs: return .appIs(window: w1, value: try expectString())
        case .contentContains: return .contentContains(window: w1, value: try expectString())
        case .isBiggerThan:
            let (w, h) = try parseSizeArgs()
            return .isBiggerThan(window: w1, width: w, height: h)
        case .isSmallerThan:
            let (w, h) = try parseSizeArgs()
            return .isSmallerThan(window: w1, width: w, height: h)
        case .hasTag:
            return .hasTag(window: w1, tag: try expectString())
        default:
            throw ParseError.unexpected(op, expected: "appIs/contentContains/isBiggerThan/isSmallerThan/hasTag")
        }
    }

    // E2 :- E3 (or E2)?
    private mutating func parseEffect() throws -> ConstraintEffect {
        let left = try parseEffectAnd()
        if peek() == .or {
            _ = advance()
            let right = try parseEffect()
            return .or(left, right)
        }
        return left
    }

    // E3 :- E4 (and E3)?
    private mutating func parseEffectAnd() throws -> ConstraintEffect {
        let left = try parseEffectAtom()
        if peek() == .and {
            _ = advance()
            let right = try parseEffectAnd()
            return .and(left, right)
        }
        return left
    }

    // E4 :- ( E2 ) | E5
    private mutating func parseEffectAtom() throws -> ConstraintEffect {
        if peek() == .openBracket {
            _ = advance()
            let inner = try parseEffect()
            try expect(.closeBracket, label: ")")
            return inner
        }
        return try parseAtomicEffect()
    }

    // E5 :- id E5'
    private mutating func parseAtomicEffect() throws -> ConstraintEffect {
        let w1 = try expectIdentifier()
        guard let op = advance() else { throw ParseError.unexpectedEnd }
        switch op {
        case .isLeftOf:  return .leftOf(window1: w1, window2: try expectIdentifier())
        case .isRightOf: return .rightOf(window1: w1, window2: try expectIdentifier())
        case .isAbove:   return .above(window1: w1, window2: try expectIdentifier())
        case .isBelow:   return .below(window1: w1, window2: try expectIdentifier())
        case .isLandscape: return .landscape(window: w1)
        case .isPortrait:  return .portrait(window: w1)
        case .isBiggerThan:
            let (w, h) = try parseSizeArgs()
            return .minimumSize(window: w1, wMin: w, hMin: h)
        case .isSmallerThan:
            let (w, h) = try parseSizeArgs()
            return .maximumSize(window: w1, wMax: w, hMax: h)
        case .hasTag:
            return .hasTag(window: w1, tag: try expectString())
        default:
            throw ParseError.unexpected(op, expected: "isLeftOf/isRightOf/isAbove/isBelow/isLandscape/isPortrait/isBiggerThan/isSmallerThan/hasTag")
        }
    }

    // WS :- ( SV , SV )
    private mutating func parseSizeArgs() throws -> (SizeValue, SizeValue) {
        try expect(.openBracket, label: "(")
        let w = try expectSizeValue()
        try expect(.comma, label: ",")
        let h = try expectSizeValue()
        try expect(.closeBracket, label: ")")
        return (w, h)
    }
}

