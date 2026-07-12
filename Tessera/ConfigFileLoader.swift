//
//  ConfigFileLoader.swift
//  Tessera
//
//  Created by Aarav Bhatt on 12/07/2026.
//

import Foundation

/// One problem encountered while loading the config.
/// `lineNumber` and `sourceLine` are `nil` for file-level errors (e.g. permission denied).
struct ConfigError {
    let lineNumber : Int?
    let sourceLine : String?
    let message : String
}

// TODO: Track whether a change was made so we don't have to reload everytime we run
class ConfigFileLoader {
    static let shared = ConfigFileLoader()

    private(set) var rules : [Rule] = []
    private(set) var lastErrors : [ConfigError] = []

    private var configURL : URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".tessera/rules.conf")
    }

    /// Reloads rules from disk. Returns any errors encountered (empty on success).
    /// A missing config file is not an error — it is treated as an empty ruleset.
    @discardableResult
    func reload() -> [ConfigError] {
        var errors : [ConfigError] = []
        let contents : String
        do {
            contents = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            let nsError = error as NSError
            let missing = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
            if !missing {
                errors.append(ConfigError(
                    lineNumber: nil,
                    sourceLine: nil,
                    message: "Could not read \(configURL.path): \(error.localizedDescription)"
                ))
            }
            rules = []
            lastErrors = errors
            return errors
        }
        // We create 'newRules' so errors in the config don't break the running program
        var newRules: [Rule] = []
        // Rules are seperated by new lines
        for (idx, line) in contents.components(separatedBy: "\n").enumerated() {
            let lineNum = idx + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            var lexer = ConfigLexer(input: String(trimmed))
            var tokens: [Token] = []
            while let t = lexer.nextToken() { tokens.append(t) }
            var parser = ConfigParser(tokens: tokens)

            do { newRules.append(try parser.parseRule()) }
            catch {
                errors.append(ConfigError(
                    lineNumber: lineNum,
                    sourceLine: trimmed,
                    message: String(describing: error)
                ))
            }
        }
        rules = newRules
        lastErrors = errors
        return errors
    }

}
