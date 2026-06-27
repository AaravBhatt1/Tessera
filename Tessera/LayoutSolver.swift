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
    case noOverlap(window1 : LayoutWindow, window2 : LayoutWindow, weight : Int = 1000)
    case landscapePref(window: LayoutWindow, weight: Int = 30)
    case portraitPref(window: LayoutWindow, weight: Int = 30)
    case prefWidth(window: LayoutWindow, width: Int, weight: Int = 20)
    case prefHeight(window: LayoutWindow, height: Int, weight: Int = 20)
    case minimumWidthPref(window: LayoutWindow, wMin: Int, weight: Int = 20)
    case minimumHeightPref(window: LayoutWindow, hMin: Int, weight: Int = 20)
    case prefX(window: LayoutWindow, x: Int, weight: Int = 20)
    case prefY(window: LayoutWindow, y: Int, weight: Int = 20)
    case leftOfPref(window1: LayoutWindow, window2: LayoutWindow, weight: Int = 20)
    case rightOfPref(window1: LayoutWindow, window2: LayoutWindow, weight: Int = 20)
    case abovePref(window1: LayoutWindow, window2: LayoutWindow, weight: Int = 20)
    case belowPref(window1: LayoutWindow, window2: LayoutWindow, weight: Int = 20)
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

actor LayoutSolver {

    var padding : Int = 15

    private var context : z3.context = z3.context()
    private var windows : [LayoutWindow] = []
    private var constraints : [LayoutConstraint] = []

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

    func solve() async -> Layout? {
        var optimizer : z3.optimize = z3.optimize(&context)
        var params : z3.params = z3.params(&context)
        params.set("timeout", UInt32(2000))

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
                optimizer.add(w.x >= context.real_val(Int32(xMin + padding)))
            case .maximumX(window: let w, xMax: let xMax):
                optimizer.add(w.x + w.width <= context.real_val(Int32(xMax - padding)))
            case .minimumY(window: let w, yMin: let yMin):
                optimizer.add(w.y >= context.real_val(Int32(yMin + padding)))
            case .maximumY(window: let w, yMax: let yMax):
                optimizer.add(w.y + w.height <= context.real_val(Int32(yMax - padding)))
            case .noOverlap(window1: let w1, window2: let w2, let weight):
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft((w1.x + w1.width + pad <= w2.x) || (w2.x + w2.width + pad <= w1.x) || (w1.y + w1.height + pad + 20 <= w2.y) || (w2.y + w2.height + pad + 20 <= w1.y), UInt32(weight))
            case .landscapePref(window: let w, let weight):
                let ratio : z3.expr = context.real_val(Int64(7), Int64(5))
                optimizer.add_soft(w.width >= ratio * w.height, UInt32(weight))
            case .portraitPref(window: let w, let weight):
                let ratio : z3.expr = context.real_val(Int64(7), Int64(5))
                optimizer.add_soft(w.height >= ratio * w.width, UInt32(weight))
            case .prefWidth(window: let w, width: let width, let weight):
                optimizer.add_soft(w.width == context.real_val(Int32(width)), UInt32(weight))
            case .prefHeight(window: let w, height: let height, let weight):
                optimizer.add_soft(w.height == context.real_val(Int32(height)), UInt32(weight))
            case .minimumWidthPref(window: let w, wMin: let wMin, let weight):
                optimizer.add_soft(w.width >= context.real_val(Int32(wMin)), UInt32(weight))
            case .minimumHeightPref(window: let w, hMin: let hMin, let weight):
                optimizer.add_soft(w.height >= context.real_val(Int32(hMin)), UInt32(weight))
            case .prefX(window: let w, x: let x, let weight):
                optimizer.add_soft(w.x == context.real_val(Int32(x)), UInt32(weight))
            case .prefY(window: let w, y: let y, let weight):
                optimizer.add_soft(w.y == context.real_val(Int32(y)), UInt32(weight))
            case .leftOfPref(window1: let w1, window2: let w2, let weight):
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft(w1.x + w1.width + pad <= w2.x, UInt32(weight))
            case .rightOfPref(window1: let w1, window2: let w2, let weight):
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft(w2.x + w2.width + pad <= w1.x, UInt32(weight))
            case .abovePref(window1: let w1, window2: let w2, let weight):
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft(w1.y + w1.height + pad <= w2.y, UInt32(weight))
            case .belowPref(window1: let w1, window2: let w2, let weight):
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft(w2.y + w2.height + pad <= w1.y, UInt32(weight))
            }
        }

        // By default, we prefer square-ish windows
        for w in windows {
            let ratio : z3.expr = context.real_val(Int32(2))
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

        let varianceRatio : z3.expr = context.real_val(Int32(3))
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
