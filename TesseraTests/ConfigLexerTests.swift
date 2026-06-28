//
//  ConfigLexerTests.swift
//  TesseraTests
//
// AI-generated

import Testing
@testable import Tessera

@MainActor
struct ConfigLexerTests {

    private func tokenize(_ input: String) -> [Token] {
        var lexer = ConfigLexer(input: input)
        var tokens: [Token] = []
        while let tok = lexer.nextToken() {
            tokens.append(tok)
        }
        return tokens
    }

    @Test func keywords() {
        let tokens = tokenize("select set then and or hasMinimumSize hasMaximumSize isLeftOf isRightOf isAbove isBelow")
        #expect(tokens == [.select, .set, .then, .and, .or, .hasMinimumSize, .hasMaximumSize, .isLeftOf, .isRightOf, .isAbove, .isBelow])
    }

    @Test func punctuation() {
        let tokens = tokenize("(,)")
        #expect(tokens == [.openBracket, .comma, .closeBracket])
    }

    @Test func identifier() {
        let tokens = tokenize("w1 myWindow")
        #expect(tokens == [.identifier(id: "w1"), .identifier(id: "myWindow")])
    }

    @Test func integer() {
        let tokens = tokenize("42 0 1920")
        #expect(tokens == [.integer(num: 42), .integer(num: 0), .integer(num: 1920)])
    }

    @Test func stringLiteral() {
        let tokens = tokenize("\"Safari\"")
        #expect(tokens == [.string(value: "Safari")])
    }

    @Test func mixedInput() {
        let tokens = tokenize("select w1, w2 then set w1 isLeftOf w2")
        #expect(tokens == [.select, .identifier(id: "w1"), .comma, .identifier(id: "w2"), .then, .set, .identifier(id: "w1"), .isLeftOf, .identifier(id: "w2")])
    }

    @Test func whitespaceIsTrimmed() {
        let tokens = tokenize("  select   w1  ")
        #expect(tokens == [.select, .identifier(id: "w1")])
    }

    @Test func emptyInput() {
        #expect(tokenize("").isEmpty)
    }
}
