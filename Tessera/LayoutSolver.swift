//
//  LayoutSolver.swift
//  Tessera
//
//  Created by Aarav Bhatt on 15/06/2026.
//

import Foundation
import Z3

enum LayoutConstraint {
    case minimumWidth(window : WindowData, wMin : Int)
    case maximumWidth(window : WindowData, wMax : Int)
    case minimumHeight(window : WindowData, hMin : Int)
    case maximumHeight(window : WindowData, hMax : Int)
    case minimumX(window : WindowData, xMin : Int)
    case maximumX(window : WindowData, xMax : Int)
    case minimumY(window : WindowData, yMin : Int)
    case maximumY(window : WindowData, yMax : Int)
    case noOverlap(window1 : WindowData, window2 : WindowData)
    case landscapePref(window: WindowData, weight: Int = 30)
    case portraitPref(window: WindowData, weight: Int = 30)
    case prefWidth(window: WindowData, width: Int, weight: Int = 20)
    case prefHeight(window: WindowData, height: Int, weight: Int = 20)
    case minimumWidthPref(window: WindowData, wMin: Int, weight: Int = 20)
    case minimumHeightPref(window: WindowData, hMin: Int, weight: Int = 20)
    case prefX(window: WindowData, x: Int, weight: Int = 20)
    case prefY(window: WindowData, y: Int, weight: Int = 20)
    case leftOfPref(window1: WindowData, window2: WindowData, weight: Int = 20)
    case rightOfPref(window1: WindowData, window2: WindowData, weight: Int = 20)
    case abovePref(window1: WindowData, window2: WindowData, weight: Int = 20)
    case belowPref(window1: WindowData, window2: WindowData, weight: Int = 20)
}

actor LayoutSolver {

    var padding : Int = 15

    private var variableNames : [String : WindowData] = [:]
    private var windows : [WindowData] = []
    private var constraints : [LayoutConstraint] = []

    func addWindow(window : WindowData) async {
        await variableNames.updateValue(window, forKey: window.getWindowWidthVar())
        await variableNames.updateValue(window, forKey: window.getWindowHeightVar())
        await variableNames.updateValue(window, forKey: window.getWindowXVar())
        await variableNames.updateValue(window, forKey: window.getWindowYVar())
        windows.append(window)
    }

    func addConstraints(constraint c : LayoutConstraint) {
        constraints.append(c)
    }

    func solve() async -> Bool {
        var context : z3.context = z3.context()

        var variables : [String : z3.expr] = [:]
        for key in variableNames.keys {
            variables.updateValue(context.real_const(key), forKey: key)
        }

        var optimizer : z3.optimize = z3.optimize(&context)
        var params : z3.params = z3.params(&context)
        params.set("timeout", UInt32(2000))

        // Handle user constraints
        for constraint in constraints {
            switch constraint {
            case .minimumWidth(window: let window, wMin: let wMin):
                guard let widthVar : z3.expr = await variables[window.getWindowWidthVar()] else { continue }
                optimizer.add(widthVar >= context.real_val(Int32(wMin)))
            case .maximumWidth(window: let window, wMax: let wMax):
                guard let widthVar : z3.expr = await variables[window.getWindowWidthVar()] else { continue }
                optimizer.add(widthVar <= context.real_val(Int32(wMax)))
            case .minimumHeight(window: let window, hMin: let hMin):
                guard let heightVar : z3.expr = await variables[window.getWindowHeightVar()] else { continue }
                optimizer.add(heightVar >= context.real_val(Int32(hMin)))
            case .maximumHeight(window: let window, hMax: let hMax):
                guard let heightVar : z3.expr = await variables[window.getWindowHeightVar()] else { continue }
                optimizer.add(heightVar <= context.real_val(Int32(hMax)))
            case .minimumX(window: let window, xMin: let xMin):
                guard let xVar : z3.expr = await variables[window.getWindowXVar()] else { continue }
                optimizer.add(xVar >= context.real_val(Int32(xMin + padding)))
            case .maximumX(window: let window, xMax: let xMax):
                guard let xVar : z3.expr = await variables[window.getWindowXVar()],
                      let widthVar : z3.expr = await variables[window.getWindowWidthVar()]
                    else { return false }
                optimizer.add(xVar + widthVar <= context.real_val(Int32(xMax - padding)))
            case .minimumY(window: let window, yMin: let yMin):
                guard let yVar : z3.expr = await variables[window.getWindowYVar()] else { continue }
                optimizer.add(yVar >= context.real_val(Int32(yMin + padding)))
            case .maximumY(window: let window, yMax: let yMax):
                guard let yVar : z3.expr = await variables[window.getWindowYVar()],
                      let heightVar : z3.expr = await variables[window.getWindowHeightVar()]
                    else { return false }
                optimizer.add(yVar + heightVar <= context.real_val(Int32(yMax - padding)))
            case .noOverlap(window1: let w1, window2: let w2):
                guard let w1X : z3.expr = await variables[w1.getWindowXVar()],
                      let w1Y : z3.expr = await variables[w1.getWindowYVar()],
                      let w1Width : z3.expr = await variables[w1.getWindowWidthVar()],
                      let w1Height : z3.expr = await variables[w1.getWindowHeightVar()],
                      let w2X : z3.expr = await variables[w2.getWindowXVar()],
                      let w2Y : z3.expr = await variables[w2.getWindowYVar()],
                      let w2Width : z3.expr = await variables[w2.getWindowWidthVar()],
                      let w2Height : z3.expr = await variables[w2.getWindowHeightVar()] else { continue }
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add((w1X + w1Width + pad <= w2X) || (w2X + w2Width + pad <= w1X) || (w1Y + w1Height + pad + 20 <= w2Y) || (w2Y + w2Height + pad + 20 <= w1Y))
            case .landscapePref(window: let w, let weight):
                guard let width : z3.expr = await variables[w.getWindowWidthVar()],
                      let height : z3.expr = await variables[w.getWindowHeightVar()] else { continue }
                let ratio : z3.expr = context.real_val(Int64(7), Int64(5))
                optimizer.add_soft(width >= ratio * height, UInt32(weight))
            case .portraitPref(window: let w, let weight):
                guard let width : z3.expr = await variables[w.getWindowWidthVar()],
                      let height : z3.expr = await variables[w.getWindowHeightVar()] else { continue }
                let ratio : z3.expr = context.real_val(Int64(7), Int64(5))
                optimizer.add_soft(height >= ratio * width, UInt32(weight))
            case .prefWidth(window: let w, width: let width, let weight):
                guard let widthVar : z3.expr = await variables[w.getWindowWidthVar()] else { continue }
                optimizer.add_soft(widthVar == context.real_val(Int32(width)), UInt32(weight))
            case .prefHeight(window: let w, height: let height, let weight):
                guard let heightVar : z3.expr = await variables[w.getWindowHeightVar()] else { continue }
                optimizer.add_soft(heightVar == context.real_val(Int32(height)), UInt32(weight))
            case .minimumWidthPref(window: let w, wMin: let wMin, let weight):
                guard let widthVar : z3.expr = await variables[w.getWindowWidthVar()] else { continue }
                optimizer.add_soft(widthVar >= context.real_val(Int32(wMin)), UInt32(weight))
            case .minimumHeightPref(window: let w, hMin: let hMin, let weight):
                guard let heightVar : z3.expr = await variables[w.getWindowHeightVar()] else { continue }
                optimizer.add_soft(heightVar >= context.real_val(Int32(hMin)), UInt32(weight))
            case .prefX(window: let w, x: let x, let weight):
                guard let xVar : z3.expr = await variables[w.getWindowXVar()] else { continue }
                optimizer.add_soft(xVar == context.real_val(Int32(x)), UInt32(weight))
            case .prefY(window: let w, y: let y, let weight):
                guard let yVar : z3.expr = await variables[w.getWindowYVar()] else { continue }
                optimizer.add_soft(yVar == context.real_val(Int32(y)), UInt32(weight))
            case .leftOfPref(window1: let w1, window2: let w2, let weight):
                guard let w1X : z3.expr = await variables[w1.getWindowXVar()],
                      let w1Width : z3.expr = await variables[w1.getWindowWidthVar()],
                      let w2X : z3.expr = await variables[w2.getWindowXVar()] else { continue }
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft(w1X + w1Width + pad <= w2X, UInt32(weight))
            case .rightOfPref(window1: let w1, window2: let w2, let weight):
                guard let w1X : z3.expr = await variables[w1.getWindowXVar()],
                      let w2X : z3.expr = await variables[w2.getWindowXVar()],
                      let w2Width : z3.expr = await variables[w2.getWindowWidthVar()] else { continue }
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft(w2X + w2Width + pad <= w1X, UInt32(weight))
            case .abovePref(window1: let w1, window2: let w2, let weight):
                guard let w1Y : z3.expr = await variables[w1.getWindowYVar()],
                      let w1Height : z3.expr = await variables[w1.getWindowHeightVar()],
                      let w2Y : z3.expr = await variables[w2.getWindowYVar()] else { continue }
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft(w1Y + w1Height + pad <= w2Y, UInt32(weight))
            case .belowPref(window1: let w1, window2: let w2, let weight):
                guard let w1Y : z3.expr = await variables[w1.getWindowYVar()],
                      let w2Y : z3.expr = await variables[w2.getWindowYVar()],
                      let w2Height : z3.expr = await variables[w2.getWindowHeightVar()] else { continue }
                let pad : z3.expr = context.real_val(Int32(padding))
                optimizer.add_soft(w2Y + w2Height + pad <= w1Y, UInt32(weight))
            }
        }
        
        // By default, we prefer square-ish windows
        for w in windows {
            guard let width : z3.expr = await variables[w.getWindowWidthVar()],
                  let height : z3.expr = await variables[w.getWindowHeightVar()] else { continue }
            let ratio : z3.expr = context.real_val(Int32(2))
            optimizer.add_soft((ratio * width >= height) && (ratio * height >= width), 10)
        }
        
        // Maximize perimiter and minimize spread
        var totalPerimeter : z3.expr = context.real_val(Int32(0))
        for w in windows {
            let wWidth : z3.expr = await variables[w.getWindowWidthVar()]!
            let wHeight : z3.expr = await variables[w.getWindowHeightVar()]!
            totalPerimeter = totalPerimeter + wWidth + wHeight
        }
        
        let numWindows : z3.expr = context.real_val(Int32(windows.count))
        var totalSpread : z3.expr = context.real_val(Int32(0))
        for w in windows {
            let wWidth : z3.expr = await variables[w.getWindowWidthVar()]!
            let wHeight : z3.expr = await variables[w.getWindowHeightVar()]!
            // Use this to calculate spread rather than using disjunctions
            let differenceVar : z3.expr = context.real_const("\(await w.hashValue)Spread")
            optimizer.add(differenceVar >= numWindows * wWidth + numWindows * wHeight - totalPerimeter)
            optimizer.add(differenceVar >= totalPerimeter - numWindows * wWidth - numWindows * wHeight)
            totalSpread = totalSpread + differenceVar
        }
        
        let varianceRatio : z3.expr = context.real_val(Int32(3))
        optimizer.maximize(varianceRatio * totalPerimeter - totalSpread)
        

        if optimizer.check() == z3.unsat {
            return false
        }

        let model : z3.model = optimizer.get_model()

        for window in windows {
            let width : Int? = await variables[window.getWindowWidthVar()].map { (expr : z3.expr) -> Int in Int(model.eval(expr).as_double().rounded()) }
            let height : Int? = await variables[window.getWindowHeightVar()].map { (expr : z3.expr) -> Int in Int(model.eval(expr).as_double().rounded()) }
            let x : Int? = await variables[window.getWindowXVar()].map { (expr : z3.expr) -> Int in Int(model.eval(expr).as_double().rounded()) }
            let y : Int? = await variables[window.getWindowYVar()].map { (expr : z3.expr) -> Int in Int(model.eval(expr).as_double().rounded()) }

            if let w : Int = width, let h : Int = height {

                guard await WindowManager.setWindowSize(for: window.element, to: (w, h)) else {
                    return false
                }
            }
            if let px : Int = x, let py : Int = y {
                guard await WindowManager.setWindowPosition(for: window.element, to: (px, py)) else {
                    return false
                }
            }
        }

        // Second pass, in case some apps didn't fully apply the size/position the first time
        for window in windows {
            let width : Int? = await variables[window.getWindowWidthVar()].map { (expr : z3.expr) -> Int in Int(model.eval(expr).as_double().rounded()) }
            let height : Int? = await variables[window.getWindowHeightVar()].map { (expr : z3.expr) -> Int in Int(model.eval(expr).as_double().rounded()) }
            let x : Int? = await variables[window.getWindowXVar()].map { (expr : z3.expr) -> Int in Int(model.eval(expr).as_double().rounded()) }
            let y : Int? = await variables[window.getWindowYVar()].map { (expr : z3.expr) -> Int in Int(model.eval(expr).as_double().rounded()) }

            if let w : Int = width, let h : Int = height {

                guard await WindowManager.setWindowSize(for: window.element, to: (w, h)) else {
                    return false
                }
            }
            if let px : Int = x, let py : Int = y {
                guard await WindowManager.setWindowPosition(for: window.element, to: (px, py)) else {
                    return false
                }
            }
        }

        return true
    }
}
