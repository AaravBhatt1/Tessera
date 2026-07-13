//
//  LayoutSolver.swift
//  Tessera
//
//  Created by Aarav Bhatt on 15/06/2026.
//

import Foundation
import ApplicationServices
import Z3

enum LayoutConstraint {
    case minimumWidth(window : LayoutWindow, wMin : Int)
    case maximumWidth(window : LayoutWindow, wMax : Int)
    case minimumHeight(window : LayoutWindow, hMin : Int)
    case maximumHeight(window : LayoutWindow, hMax : Int)
    case minimumX(window : LayoutWindow, xMin : Int)
    case maximumX(window : LayoutWindow, xMax : Int)
    case minimumY(window : LayoutWindow, yMin : Int)
    case maximumY(window : LayoutWindow, yMax : Int)
}

struct Layout {
    struct WindowGeometry {
        let x : Int
        let y : Int
        let width : Int
        let height : Int
    }
    let windows : [LayoutWindow : WindowGeometry]
}

@MainActor class LayoutSolver {

    private var context : z3.context = z3.context()
    private var constants : [Int : z3.expr] = [:]
    private var windows : [LayoutWindow] = []
    private var constraints : [LayoutConstraint] = []
    private var hardConstraints : [z3.expr] = []
    private var softConstraints : [(expr : z3.expr, weight : Int)] = []
    private var tagVars : [LayoutWindow : [String : z3.expr]] = [:]
    private var dynamicTagVars : [LayoutWindow : [String : z3.expr]] = [:]

    func addWindow(element : AXUIElement, app : String, title : String) -> LayoutWindow {
        let hash = CFHash(element)
        let window = LayoutWindow(
            element: element,
            app: app,
            title: title,
            x: context.real_const("\(hash)_x"),
            y: context.real_const("\(hash)_y"),
            width: context.real_const("\(hash)_width"),
            height: context.real_const("\(hash)_height")
        )
        windows.append(window)
        return window
    }

    func addConstraint(_ c : LayoutConstraint) {
        constraints.append(c)
    }

    func addSoftConstraint(_ expr : z3.expr, weight : Int) {
        softConstraints.append((expr: expr, weight: weight))
    }

    func addHardConstraint(_ expr : z3.expr) {
        hardConstraints.append(expr)
    }

    var allConstants : [Int : z3.expr] { constants }

    @discardableResult
    func makeConstant(_ n : Int) -> z3.expr {
        if let cached = constants[n] { return cached }
        let expr = context.real_val(Int32(n))
        constants[n] = expr
        return expr
    }

    func makeRational(numerator : Int64, denominator : Int64) -> z3.expr {
        return context.real_val(numerator, denominator)
    }

    func getTagVar(window : LayoutWindow, tag : String) -> z3.expr {
        if let cached = tagVars[window]?[tag] { return cached }
        let hash = CFHash(window.element)
        let expr = context.bool_const("\(hash)_tag_\(tag)")
        tagVars[window, default: [:]][tag] = expr
        return expr
    }

    // Dynamic tag vars live in their own namespace: they're pinned by the UI, not
    // touched by rule effects, and read via hasDynamicTag conditions.
    func getDynamicTagVar(window : LayoutWindow, tag : String) -> z3.expr {
        if let cached = dynamicTagVars[window]?[tag] { return cached }
        let hash = CFHash(window.element)
        let expr = context.bool_const("\(hash)_dyntag_\(tag)")
        dynamicTagVars[window, default: [:]][tag] = expr
        return expr
    }

    // Pin a window's dynamic tag to a fixed truth value as a hard constraint.
    func setDynamicTagHard(window : LayoutWindow, tag : String, value : Bool) {
        let expr = getDynamicTagVar(window: window, tag: tag)
        hardConstraints.append(expr == context.bool_val(value))
    }

    func solve() async -> Layout? {
        var optimizer : z3.optimize = z3.optimize(&context)
        var params : z3.params = z3.params(&context)
        params.set("timeout", UInt32(1000))
        optimizer.set(params)

        for expr in hardConstraints {
            optimizer.add(expr)
        }

        for (expr, weight) in softConstraints {
            optimizer.add_soft(expr, UInt32(weight))
        }

        for constraint in constraints {
            switch constraint {
            case .minimumWidth(window: let w, wMin: let wMin):
                optimizer.add(w.width >= context.real_val(Int32(wMin)))
            case .maximumWidth(window: let w, wMax: let wMax):
                optimizer.add(w.width <= context.real_val(Int32(wMax)))
            case .minimumHeight(window: let w, hMin: let hMin):
                optimizer.add(w.height >= context.real_val(Int32(hMin)))
            case .maximumHeight(window: let w, hMax: let hMax):
                optimizer.add(w.height <= context.real_val(Int32(hMax)))
            case .minimumX(window: let w, xMin: let xMin):
                optimizer.add(w.x >= makeConstant(xMin + 15))
            case .maximumX(window: let w, xMax: let xMax):
                optimizer.add(w.x + w.width <= makeConstant(xMax - 15))
            case .minimumY(window: let w, yMin: let yMin):
                optimizer.add(w.y >= makeConstant(yMin + 15))
            case .maximumY(window: let w, yMax: let yMax):
                optimizer.add(w.y + w.height <= makeConstant(yMax - 15))
            }
        }

        // TODO: Keep track of windows to exclude from no-overlap (e.g. floating windows)
        let xPad = makeConstant(15)
        let yPad = makeConstant(35)
        for i in 0..<windows.count {
            for j in (i + 1)..<windows.count {
                let w1 = windows[i]
                let w2 = windows[j]
                optimizer.add_soft(
                    (w1.x + w1.width + xPad <= w2.x) ||
                    (w2.x + w2.width + xPad <= w1.x) ||
                    (w1.y + w1.height + yPad <= w2.y) ||
                    (w2.y + w2.height + yPad <= w1.y),
                    1000
                )
            }
        }

        // By default, we prefer square-ish windows
        for w in windows {
            let ratio : z3.expr = makeConstant(2)
            optimizer.add_soft((ratio * w.width >= w.height) && (ratio * w.height >= w.width), 10)
        }

        // Maximize perimeter and minimize spread
        var totalPerimeter : z3.expr = context.real_val(Int32(0))
        for w in windows {
            totalPerimeter = totalPerimeter + w.width + w.height
        }

        let numWindows : z3.expr = context.real_val(Int32(windows.count))
        var totalSpread : z3.expr = context.real_val(Int32(0))
        for w in windows {
            let differenceVar : z3.expr = context.real_const("\(CFHash(w.element))Spread")
            optimizer.add(differenceVar >= numWindows * w.width + numWindows * w.height - totalPerimeter)
            optimizer.add(differenceVar >= totalPerimeter - numWindows * w.width - numWindows * w.height)
            totalSpread = totalSpread + differenceVar
        }

        let varianceRatio : z3.expr = context.real_val(Int32(50))
        optimizer.maximize(varianceRatio * totalPerimeter - totalSpread)
        
        if optimizer.check() == z3.unsat {
            return nil
        }
        

        let model : z3.model = optimizer.get_model()

        var geometries : [LayoutWindow : Layout.WindowGeometry] = [:]
        for window in windows {
            geometries[window] = Layout.WindowGeometry(
                x:      Int(model.eval(window.x).as_double().rounded()),
                y:      Int(model.eval(window.y).as_double().rounded()),
                width:  Int(model.eval(window.width).as_double().rounded()),
                height: Int(model.eval(window.height).as_double().rounded())
            )
        }

        return Layout(windows: geometries)
    }
}
