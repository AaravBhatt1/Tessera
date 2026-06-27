//
//  RuleAST.swift
//  Tessera
//
//  Created by Aarav Bhatt on 27/06/2026.
//

import Foundation
import Z3

// Using indirect enum for FP style ADTs

enum ComparisonOp {
    case lt, leq, eq, geq, gt

    func apply(_ lhs: z3.expr, _ rhs: z3.expr) -> z3.expr {
        switch self {
        case .lt:  return lhs < rhs
        case .leq: return lhs <= rhs
        case .eq:  return lhs == rhs
        case .geq: return lhs >= rhs
        case .gt:  return lhs > rhs
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

}

indirect enum ConditionExpr {
    // Resolved early
    case titleContains(window: String, value: String)
    case appContains(window: String, value: String)
    case isFocused(window: String)

    // Returns an expression
    case windowWidth(window: String, op: ComparisonOp, value: Int)
    case windowHeight(window: String, op: ComparisonOp, value: Int)
    case windowX(window: String, op: ComparisonOp, value: Int)
    case windowY(window: String, op: ComparisonOp, value: Int)

    case and(ConditionExpr, ConditionExpr)
    case or(ConditionExpr, ConditionExpr)

    func evaluate(vars: [String: LayoutWindow], makeConst: (Int) -> z3.expr) -> ConditionValue {
        switch self {
        case .titleContains(let v, let value):
            guard let w = vars[v] else { return .bool(false) }
            return .bool(w.title.lowercased().contains(value.lowercased()))
        case .appContains(let v, let value):
            guard let w = vars[v] else { return .bool(false) }
            return .bool(w.app.lowercased().contains(value.lowercased()))
        case .isFocused(let v):
            guard let w = vars[v], let focused = WindowManager.getCurrentFocusedWindow() else { return .bool(false) }
            return .bool(CFEqual(w.element, focused))
        case .windowWidth(let v, let op, let value):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr(op.apply(w.width, makeConst(value)))
        case .windowHeight(let v, let op, let value):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr(op.apply(w.height, makeConst(value)))
        case .windowX(let v, let op, let value):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr(op.apply(w.x, makeConst(value)))
        case .windowY(let v, let op, let value):
            guard let w = vars[v] else { return .bool(false) }
            return .z3Expr(op.apply(w.y, makeConst(value)))
        case .and(let a, let b):
            return a.evaluate(vars: vars, makeConst: makeConst)
                   .and(b.evaluate(vars: vars, makeConst: makeConst))
        case .or(let a, let b):
            return a.evaluate(vars: vars, makeConst: makeConst)
                   .or(b.evaluate(vars: vars, makeConst: makeConst))
        }
    }
}

struct Rule {
    let variables: [String]
    let condition: ConditionExpr?
    let effects: [(ConstraintEffect, Int)]

    func apply(windows: [LayoutWindow], solver: LayoutSolver) {
        let makeConst: (Int) -> z3.expr = { n in solver.makeConstant(n) }
        var vars: [String: LayoutWindow] = [:]
        var available: [LayoutWindow] = windows

        func bind(remaining: [String]) {
            guard let varName = remaining.first else {
                let condValue: ConditionValue
                if let condition {
                    condValue = condition.evaluate(vars: vars, makeConst: makeConst)
                } else {
                    condValue = .bool(true)
                }

                switch condValue {
                case .bool(false):
                    return
                case .bool(true):
                    for (effect, weight) in effects {
                        if let expr = effect.generateExpr(vars: vars, makeConst: makeConst) {
                            solver.addSoftConstraint(expr, weight: weight)
                        }
                    }
                case .z3Expr(let guardExpr):
                    for (effect, weight) in effects {
                        if let expr = effect.generateExpr(vars: vars, makeConst: makeConst) {
                            solver.addSoftConstraint(z3.implies(guardExpr, expr), weight: weight)
                        }
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
    case minimumSize(window: String, wMin: Int, hMin: Int)
    case maximumSize(window: String, wMax: Int, hMax: Int)
    case preferredPosition(window: String, x: Int, y: Int)
    case preferredSize(window: String, width: Int, height: Int)
    case leftOf(window1: String, window2: String)
    case rightOf(window1: String, window2: String)
    case above(window1: String, window2: String)
    case below(window1: String, window2: String)
    case landscape(window: String)
    case portrait(window: String)
    case and(ConstraintEffect, ConstraintEffect)
    case or(ConstraintEffect, ConstraintEffect)

    func generateExpr(vars: [String: LayoutWindow], makeConst: (Int) -> z3.expr) -> z3.expr? {
        let pad = makeConst(15)

        switch self {
        case .minimumSize(let v, let wMin, let hMin):
            guard let w = vars[v] else { return nil }
            return (w.width >= makeConst(wMin)) && (w.height >= makeConst(hMin))
        case .maximumSize(let v, let wMax, let hMax):
            guard let w = vars[v] else { return nil }
            return (w.width <= makeConst(wMax)) && (w.height <= makeConst(hMax))
        case .preferredPosition(let v, let x, let y):
            guard let w = vars[v] else { return nil }
            return (w.x == makeConst(x)) && (w.y == makeConst(y))
        case .preferredSize(let v, let width, let height):
            guard let w = vars[v] else { return nil }
            return (w.width == makeConst(width)) && (w.height == makeConst(height))
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
        case .and(let a, let b):
            guard let ea = a.generateExpr(vars: vars, makeConst: makeConst),
                  let eb = b.generateExpr(vars: vars, makeConst: makeConst) else { return nil }
            return ea && eb
        case .or(let a, let b):
            guard let ea = a.generateExpr(vars: vars, makeConst: makeConst),
                  let eb = b.generateExpr(vars: vars, makeConst: makeConst) else { return nil }
            return ea || eb
        }
    }
}
