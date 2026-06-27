//
//  RuleParser.swift
//  Tessera
//
//  Created by Aarav Bhatt on 21/06/2026.
//

import Foundation

// A single condition a window must satisfy to fill a selector's slot
// TODO: Add tagging support
enum WindowCondition {
    case appEquals(app : String)
    case titleContains(title : String)
    case isFocused
}

// One window slot for a rule - assumed to bind to a distinct window
struct WindowSelector {
    let windowVar : String
    let conditions : [WindowCondition]
}

enum Orientation : String {
    case portrait
    case landscape
}

enum RelativeDirection : String {
    case left
    case right
    case above
    case below
}

enum RuleEffect {
    case sizePref(windowVar : String, size : (width : Int, height : Int))
    case orientationPref(windowVar : String, orientation : Orientation)
    case relativePositioningPref(window1Var : String, window2Var : String, position : RelativeDirection)
}

struct Rule {
    let selectors : [WindowSelector]
    let effects : [RuleEffect]

    // Number of distinct windows this rule needs bound before it can be evaluated
    var arity : Int {
        return selectors.count
    }
}
