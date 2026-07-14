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

    func resolveWidth(for window: LayoutWindow, solver: LayoutSolver, screenSizeFor: (LayoutWindow) -> (Int, Int)) -> z3.expr {
        switch self {
        case .absolute(let n): return solver.makeConstant(n)
        case .percent(let p): return solver.makeConstant(screenSizeFor(window).0 * p / 100)
        }
    }

    func resolveHeight(for window: LayoutWindow, solver: LayoutSolver, screenSizeFor: (LayoutWindow) -> (Int, Int)) -> z3.expr {
        switch self {
        case .absolute(let n): return solver.makeConstant(n)
        case .percent(let p): return solver.makeConstant(screenSizeFor(window).1 * p / 100)
        }
    }
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

    func not(solver: LayoutSolver) -> ConditionValue {
        switch self {
        case .bool(let b): return .bool(!b)
        case .z3Expr(let e): return .z3Expr(solver.makeNot(e))
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
    // Dynamic tags are user-controlled; effects can't set them.
    case hasDynamicTag(window: String, tag: String)
    // TODO: window1 isBiggerThan window2?

    case and(ConditionExpr, ConditionExpr)
    case or(ConditionExpr, ConditionExpr)
    case not(ConditionExpr)

    func evaluate(vars: [String: LayoutWindow], solver: LayoutSolver, screenSizeFor: (LayoutWindow) -> (Int, Int)) -> ConditionValue {
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
            return .z3Expr((w.width >= width.resolveWidth(for: w, solver: solver, screenSizeFor: screenSizeFor)) && (w.height >= height.resolveHeight(for: w, solver: solver, screenSizeFor: screenSizeFor)))
        case .isSmallerThan(let v, let width, let height):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr((w.width <= width.resolveWidth(for: w, solver: solver, screenSizeFor: screenSizeFor)) && (w.height <= height.resolveHeight(for: w, solver: solver, screenSizeFor: screenSizeFor)))
        case .hasTag(let v, let tag):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr(solver.getTagVar(window: w, tag: tag))
        case .hasDynamicTag(let v, let tag):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr(solver.getDynamicTagVar(window: w, tag: tag))
        case .and(let a, let b):
            return a.evaluate(vars: vars, solver: solver, screenSizeFor: screenSizeFor)
                   .and(b.evaluate(vars: vars, solver: solver, screenSizeFor: screenSizeFor))
        case .or(let a, let b):
            return a.evaluate(vars: vars, solver: solver, screenSizeFor: screenSizeFor)
                   .or(b.evaluate(vars: vars, solver: solver, screenSizeFor: screenSizeFor))
        case .not(let a):
            return a.evaluate(vars: vars, solver: solver, screenSizeFor: screenSizeFor).not(solver: solver)
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
        case .hasDynamicTag(let w, _): accum.insert(w)
        case .and(let a, let b): a.getFreeVars(accum: &accum); b.getFreeVars(accum: &accum)
        case .or(let a, let b): a.getFreeVars(accum: &accum); b.getFreeVars(accum: &accum)
        case .not(let a): a.getFreeVars(accum: &accum)
        }
    }

    func getTagNames(accum : inout Set<String>) {
        switch self {
        case .hasTag(_, let tag): accum.insert(tag)
        case .and(let a, let b): a.getTagNames(accum: &accum); b.getTagNames(accum: &accum)
        case .or(let a, let b): a.getTagNames(accum: &accum); b.getTagNames(accum: &accum)
        case .not(let a): a.getTagNames(accum: &accum)
        default: break
        }
    }

    func getDynamicTagNames(accum : inout Set<String>) {
        switch self {
        case .hasDynamicTag(_, let tag): accum.insert(tag)
        case .and(let a, let b): a.getDynamicTagNames(accum: &accum); b.getDynamicTagNames(accum: &accum)
        case .or(let a, let b): a.getDynamicTagNames(accum: &accum); b.getDynamicTagNames(accum: &accum)
        case .not(let a): a.getDynamicTagNames(accum: &accum)
        default: break
        }
    }

}

enum RuleWeight {
    case hard
    case perBinding(Int)
    case aggregated(Int)
}

struct Rule {
    let variables: [String]
    let condition: ConditionExpr?
    let effect: ConstraintEffect
    let weight: RuleWeight

    func getDynamicTagNames() -> Set<String> {
        var acc: Set<String> = []
        condition?.getDynamicTagNames(accum: &acc)
        return acc
    }

    func apply(windows: [LayoutWindow], solver: LayoutSolver, screenSizeFor: @escaping (LayoutWindow) -> (Int, Int)) {
        var vars: [String: LayoutWindow] = [:]
        var available: [LayoutWindow] = windows

        var aggregatedExprs: [z3.expr] = []

        // How to add constraint
        func emit(_ expr: z3.expr) {
            switch weight {
            case .hard:
                solver.addHardConstraint(expr)
            case .perBinding(let w):
                solver.addSoftConstraint(expr, weight: w)
            case .aggregated:
                aggregatedExprs.append(expr)
            }
        }

        // TODO: Push conditions in to falsify ASAP?
        func bind(remaining: [String]) {
            guard let varName = remaining.first else {
                let condValue: ConditionValue
                if let condition {
                    condValue = condition.evaluate(vars: vars, solver: solver, screenSizeFor: screenSizeFor)
                } else {
                    condValue = .bool(true)
                }

                switch condValue {
                case .bool(false):
                    return
                case .bool(true):
                    if let expr = effect.generateExpr(vars: vars, solver: solver, screenSizeFor: screenSizeFor) {
                        emit(expr)
                    }
                case .z3Expr(let guardExpr):
                    if let expr = effect.generateExpr(vars: vars, solver: solver, screenSizeFor: screenSizeFor) {
                        emit(z3.implies(guardExpr, expr))
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

        // If this rule aggregates, and all the aggregated rules together with weight
        if case .aggregated(let w) = weight, !aggregatedExprs.isEmpty {
            var combined = aggregatedExprs[0]
            for i in 1..<aggregatedExprs.count {
                combined = combined && aggregatedExprs[i]
            }
            solver.addSoftConstraint(combined, weight: w)
        }
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

    func getTagNames(accum : inout Set<String>) {
        switch self {
        case .hasTag(_, let tag): accum.insert(tag)
        case .and(let a, let b): a.getTagNames(accum: &accum); b.getTagNames(accum: &accum)
        case .or(let a, let b): a.getTagNames(accum: &accum); b.getTagNames(accum: &accum)
        default: break
        }
    }

    func generateExpr(vars: [String: LayoutWindow], solver: LayoutSolver, screenSizeFor: (LayoutWindow) -> (Int, Int)) -> z3.expr? {
        let pad = solver.makeConstant(15)

        switch self {
        case .minimumSize(let v, let wMin, let hMin):
            guard let w = vars[v] else { return nil }
            return (w.width >= wMin.resolveWidth(for: w, solver: solver, screenSizeFor: screenSizeFor)) && (w.height >= hMin.resolveHeight(for: w, solver: solver, screenSizeFor: screenSizeFor))
        case .maximumSize(let v, let wMax, let hMax):
            guard let w = vars[v] else { return nil }
            return (w.width <= wMax.resolveWidth(for: w, solver: solver, screenSizeFor: screenSizeFor)) && (w.height <= hMax.resolveHeight(for: w, solver: solver, screenSizeFor: screenSizeFor))
        case .preferredPosition(let v, let x, let y):
            guard let w = vars[v] else { return nil }
            return (w.x == solver.makeConstant(x)) && (w.y == solver.makeConstant(y))
        case .preferredSize(let v, let width, let height):
            guard let w = vars[v] else { return nil }
            return (w.width == width.resolveWidth(for: w, solver: solver, screenSizeFor: screenSizeFor)) && (w.height == height.resolveHeight(for: w, solver: solver, screenSizeFor: screenSizeFor))
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
            return solver.makeConstant(5) * w.width >= solver.makeConstant(7) * w.height
        case .portrait(let v):
            guard let w = vars[v] else { return nil }
            return solver.makeConstant(5) * w.height >= solver.makeConstant(7) * w.width
        case .hasTag(let v, let tag):
            guard let w = vars[v] else { return nil }
            return solver.getTagVar(window: w, tag: tag)
        case .and(let a, let b):
            guard let ea = a.generateExpr(vars: vars, solver: solver, screenSizeFor: screenSizeFor),
                  let eb = b.generateExpr(vars: vars, solver: solver, screenSizeFor: screenSizeFor) else { return nil }
            return ea && eb
        case .or(let a, let b):
            guard let ea = a.generateExpr(vars: vars, solver: solver, screenSizeFor: screenSizeFor),
                  let eb = b.generateExpr(vars: vars, solver: solver, screenSizeFor: screenSizeFor) else { return nil }
            return ea || eb
        }
    }
}
