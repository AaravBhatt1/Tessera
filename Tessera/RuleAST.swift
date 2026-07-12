//
//  RuleAST.swift
//  Tessera
//
//  Created by Aarav Bhatt on 27/06/2026.
//

import Foundation
import Z3

// TODO: Add tagging support (e.g. conditions based on window having some tag, and effects based on tagging windows)
// TODO: Add support for relative sizing (w1 isBiggerThan w2)


// Using indirect enum for FP style ADTs

// A width or height literal in the rule DSL: either an absolute pixel value or a percentage
// of the screen dimension corresponding to the axis it is used on.
enum SizeValue : Equatable {
    case absolute(Int)
    case percent(Int)
}

// Either true or false if current window constraint (e.g. description), or an expression if it needs to be resolved later
enum ConditionValue {
    case bool(Bool)
    case z3Expr(z3.expr)

    func and(_ other: ConditionValue) -> ConditionValue {
        switch (self, other) {
        case (.bool(false), _): return .bool(false)
        case (_, .bool(false)): return .bool(false)
        case (.bool(true), let x): return x
        case (let x, .bool(true)): return x
        case (.z3Expr(let a), .z3Expr(let b)): return .z3Expr(a && b)
        }
    }

    func or(_ other: ConditionValue) -> ConditionValue {
        switch (self, other) {
        case (.bool(true), _): return .bool(true)
        case (_, .bool(true)): return .bool(true)
        case (.bool(false), let x): return x
        case (let x, .bool(false)): return x
        case (.z3Expr(let a), .z3Expr(let b)): return .z3Expr(a || b)
        }
    }

}

indirect enum ConditionExpr {
    // Resolved early
    case contentContains(window: String, value: String)
    case appIs(window: String, value: String)
    case isFocused(window: String)

    // Returns an expression
    case isBiggerThan(window: String, width: SizeValue, height: SizeValue)
    case isSmallerThan(window: String, width: SizeValue, height: SizeValue)
    case hasTag(window: String, tag: String)
    // TODO: window1 isBiggerThan window2?

    case and(ConditionExpr, ConditionExpr)
    case or(ConditionExpr, ConditionExpr)

    func evaluate(vars: [String: LayoutWindow], makeConst: (Int) -> z3.expr, makeTagVar: (LayoutWindow, String) -> z3.expr, resolveW: (SizeValue, LayoutWindow) -> z3.expr, resolveH: (SizeValue, LayoutWindow) -> z3.expr) -> ConditionValue {
        switch self {
        case .contentContains(let v, let value):
            guard let w = vars[v] else { return .bool(false) }
            return .bool(w.title.lowercased().contains(value.lowercased()))
        case .appIs(let v, let value):
            guard let w = vars[v] else { return .bool(false) }
            return .bool(w.app.lowercased() == value.lowercased())
        case .isFocused(let v):
            guard let w = vars[v], let focused = WindowManager.getCurrentFocusedWindow() else { return .bool(false) }
            return .bool(CFEqual(w.element, focused))
        case .isBiggerThan(let v, let width, let height):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr((w.width >= resolveW(width, w)) && (w.height >= resolveH(height, w)))
        case .isSmallerThan(let v, let width, let height):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr((w.width <= resolveW(width, w)) && (w.height <= resolveH(height, w)))
        case .hasTag(let v, let tag):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr(makeTagVar(w, tag))
        case .and(let a, let b):
            return a.evaluate(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH)
                   .and(b.evaluate(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH))
        case .or(let a, let b):
            return a.evaluate(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH)
                   .or(b.evaluate(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH))
        }
    }

    func getFreeVars(accum : inout Set<String>) {
        switch self {
        case .contentContains(let w, _): accum.insert(w)
        case .appIs(let w, _): accum.insert(w)
        case .isFocused(let w): accum.insert(w)
        case .isBiggerThan(let w, _, _): accum.insert(w)
        case .isSmallerThan(let w, _, _): accum.insert(w)
        case .hasTag(let w, _): accum.insert(w)
        case .and(let a, let b): a.getFreeVars(accum: &accum); b.getFreeVars(accum: &accum)
        case .or(let a, let b): a.getFreeVars(accum: &accum); b.getFreeVars(accum: &accum)
        }
    }

}

struct Rule {
    let variables: [String]
    let condition: ConditionExpr?
    let effect: ConstraintEffect
    let weight: Int

    // `screenSizeFor` returns the (width, height) of the screen the given window is on.
    // Used to resolve percentage size literals to absolute pixels per-window.
    func apply(windows: [LayoutWindow], solver: LayoutSolver, screenSizeFor: @escaping (LayoutWindow) -> (Int, Int)) {
        let makeConst: (Int) -> z3.expr = { n in solver.makeConstant(n) }
        let makeTagVar: (LayoutWindow, String) -> z3.expr = { w, tag in solver.getTagVar(window: w, tag: tag) }
        let resolveW: (SizeValue, LayoutWindow) -> z3.expr = { v, w in
            switch v {
            case .absolute(let n): return solver.makeConstant(n)
            case .percent(let p): return solver.makeConstant(screenSizeFor(w).0 * p / 100)
            }
        }
        let resolveH: (SizeValue, LayoutWindow) -> z3.expr = { v, w in
            switch v {
            case .absolute(let n): return solver.makeConstant(n)
            case .percent(let p): return solver.makeConstant(screenSizeFor(w).1 * p / 100)
            }
        }
        var vars: [String: LayoutWindow] = [:]
        var available: [LayoutWindow] = windows

        // TODO: Push conditions in to falsify ASAP?
        func bind(remaining: [String]) {
            guard let varName = remaining.first else {
                let condValue: ConditionValue
                if let condition {
                    condValue = condition.evaluate(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH)
                } else {
                    condValue = .bool(true)
                }

                switch condValue {
                case .bool(false):
                    return
                case .bool(true):
                    if let expr = effect.generateExpr(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH) {
                        solver.addSoftConstraint(expr, weight: weight)
                    }
                case .z3Expr(let guardExpr):
                    if let expr = effect.generateExpr(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH) {
                        solver.addSoftConstraint(z3.implies(guardExpr, expr), weight: weight)
                    }
                }
                return
            }
            let rest = Array(remaining.dropFirst())
            for (i, window) in available.enumerated() {
                vars[varName] = window
                available.remove(at: i)
                bind(remaining: rest)
                available.insert(window, at: i)
                vars.removeValue(forKey: varName)
            }
        }

        bind(remaining: variables)
    }
}

indirect enum ConstraintEffect {
    case minimumSize(window: String, wMin: SizeValue, hMin: SizeValue)
    case maximumSize(window: String, wMax: SizeValue, hMax: SizeValue)
    case preferredPosition(window: String, x: Int, y: Int)
    case preferredSize(window: String, width: SizeValue, height: SizeValue)
    case leftOf(window1: String, window2: String)
    case rightOf(window1: String, window2: String)
    case above(window1: String, window2: String)
    case below(window1: String, window2: String)
    case landscape(window: String)
    case portrait(window: String)
    case hasTag(window: String, tag: String)
    case and(ConstraintEffect, ConstraintEffect)
    case or(ConstraintEffect, ConstraintEffect)

    func getFreeVars( accum : inout Set<String>) {
        switch self {
        case .minimumSize(let w, _, _): accum.insert(w)
        case .maximumSize(let w, _, _): accum.insert(w)
        case .preferredPosition(let w, _, _): accum.insert(w)
        case .preferredSize(let w, _, _): accum.insert(w)
        case .leftOf(window1: let w1, window2: let w2): accum.insert(w1); accum.insert(w2)
        case .rightOf(window1: let w1, window2: let w2): accum.insert(w1); accum.insert(w2)
        case .above(window1: let w1, window2: let w2): accum.insert(w1); accum.insert(w2)
        case .below(window1: let w1, window2: let w2): accum.insert(w1); accum.insert(w2)
        case .landscape(window: let w1): accum.insert(w1)
        case .portrait(window: let w1): accum.insert(w1)
        case .hasTag(window: let w1, _): accum.insert(w1)
        case .and(let e1, let e2): e1.getFreeVars(accum: &accum); e2.getFreeVars(accum: &accum)
        case .or(let e1, let e2): e1.getFreeVars(accum: &accum); e2.getFreeVars(accum: &accum)
        }

    }

    func generateExpr(vars: [String: LayoutWindow], makeConst: (Int) -> z3.expr, makeTagVar: (LayoutWindow, String) -> z3.expr, resolveW: (SizeValue, LayoutWindow) -> z3.expr, resolveH: (SizeValue, LayoutWindow) -> z3.expr) -> z3.expr? {
        let pad = makeConst(15)

        switch self {
        case .minimumSize(let v, let wMin, let hMin):
            guard let w = vars[v] else { return nil }
            return (w.width >= resolveW(wMin, w)) && (w.height >= resolveH(hMin, w))
        case .maximumSize(let v, let wMax, let hMax):
            guard let w = vars[v] else { return nil }
            return (w.width <= resolveW(wMax, w)) && (w.height <= resolveH(hMax, w))
        case .preferredPosition(let v, let x, let y):
            guard let w = vars[v] else { return nil }
            return (w.x == makeConst(x)) && (w.y == makeConst(y))
        case .preferredSize(let v, let width, let height):
            guard let w = vars[v] else { return nil }
            return (w.width == resolveW(width, w)) && (w.height == resolveH(height, w))
        case .leftOf(let v1, let v2):
            guard let w1 = vars[v1], let w2 = vars[v2] else { return nil }
            return w1.x + w1.width + pad <= w2.x
        case .rightOf(let v1, let v2):
            guard let w1 = vars[v1], let w2 = vars[v2] else { return nil }
            return w2.x + w2.width + pad <= w1.x
        case .above(let v1, let v2):
            guard let w1 = vars[v1], let w2 = vars[v2] else { return nil }
            return w1.y + w1.height + pad <= w2.y
        case .below(let v1, let v2):
            guard let w1 = vars[v1], let w2 = vars[v2] else { return nil }
            return w2.y + w2.height + pad <= w1.y
        case .landscape(let v):
            guard let w = vars[v] else { return nil }
            return makeConst(5) * w.width >= makeConst(7) * w.height
        case .portrait(let v):
            guard let w = vars[v] else { return nil }
            return makeConst(5) * w.height >= makeConst(7) * w.width
        case .hasTag(let v, let tag):
            guard let w = vars[v] else { return nil }
            return makeTagVar(w, tag)
        case .and(let a, let b):
            guard let ea = a.generateExpr(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH),
                  let eb = b.generateExpr(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH) else { return nil }
            return ea && eb
        case .or(let a, let b):
            guard let ea = a.generateExpr(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH),
                  let eb = b.generateExpr(vars: vars, makeConst: makeConst, makeTagVar: makeTagVar, resolveW: resolveW, resolveH: resolveH) else { return nil }
            return ea || eb
        }
    }
}
