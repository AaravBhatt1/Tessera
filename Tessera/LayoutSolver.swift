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
}

actor LayoutSolver {

    var padding : Int = 15

    // Tunables for the soft area-optimization objective in solve(). Both
    // operate on a linear (perimeter-based) proxy for area rather than area
    // itself, so the whole model stays in QF_LRA.

    // How strongly each window is pulled toward a square (1:1) ratio,
    // relative to the reward for simply growing bigger.
    var aspectRatioWeight : Double = 300
    // How strongly windows are pulled toward being similarly sized.
    var balanceWeight : Double = 0.5

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
        params.set("timeout", UInt32(5000))
        optimizer.set(params)

        // Converts a Double into an exact z3 rational, since the optimizer's
        // weights and target ratios aren't whole numbers.
        func realVal(_ value : Double) -> z3.expr {
            let denominator : Int64 = 1_000_000
            return context.real_val(Int64((value * Double(denominator)).rounded()), denominator)
        }

        for constraint in constraints {
            switch constraint {
            case .minimumWidth(window: let window, wMin: let wMin):
                guard let widthVar : z3.expr = await variables[window.getWindowWidthVar()] else { return false }
                optimizer.add(widthVar >= context.real_val(Int32(wMin)))
            case .maximumWidth(window: let window, wMax: let wMax):
                guard let widthVar : z3.expr = await variables[window.getWindowWidthVar()] else { return false }
                optimizer.add(widthVar <= context.real_val(Int32(wMax)))
            case .minimumHeight(window: let window, hMin: let hMin):
                guard let heightVar : z3.expr = await variables[window.getWindowHeightVar()] else { return false }
                optimizer.add(heightVar >= context.real_val(Int32(hMin)))
            case .maximumHeight(window: let window, hMax: let hMax):
                guard let heightVar : z3.expr = await variables[window.getWindowHeightVar()] else { return false }
                optimizer.add(heightVar <= context.real_val(Int32(hMax)))
            case .minimumX(window: let window, xMin: let xMin):
                guard let xVar : z3.expr = await variables[window.getWindowXVar()] else { return false }
                optimizer.add(xVar >= context.real_val(Int32(xMin + padding)))
            case .maximumX(window: let window, xMax: let xMax):
                guard let xVar : z3.expr = await variables[window.getWindowXVar()],
                      let widthVar : z3.expr = await variables[window.getWindowWidthVar()]
                    else { return false }
                optimizer.add(xVar + widthVar <= context.real_val(Int32(xMax - padding)))
            case .minimumY(window: let window, yMin: let yMin):
                guard let yVar : z3.expr = await variables[window.getWindowYVar()] else { return false }
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
                      let w2Height : z3.expr = await variables[w2.getWindowHeightVar()] else { return false }
                let pad : z3.expr = context.real_val(Int32(padding))

                optimizer.add((w1X + w1Width + pad <= w2X) || (w2X + w2Width + pad <= w1X) || (w1Y + w1Height + pad + 20 <= w2Y) || (w2Y + w2Height + pad + 20 <= w1Y))
            }
        }

        // Soft objective: maximise total perimeter (a linear stand-in for
        // area, since for a fixed 1:1 ratio area = (width+height)^2/4 - a
        // monotonic function of that sum), penalised by how far each window
        // sits from a square and by how unevenly sized the windows are.
        var weightedSizes : [z3.expr] = []
        var objective : z3.expr = context.real_val(Int32(0))

        for window in windows {
            guard let width : z3.expr = await variables[window.getWindowWidthVar()],
                  let height : z3.expr = await variables[window.getWindowHeightVar()]
            else { return false }

            let weightedSize : z3.expr = width + height
            weightedSizes.append(weightedSize)

            let ratioDeviation : z3.expr = z3.abs(width - height)
            objective = objective + weightedSize - realVal(aspectRatioWeight) * ratioDeviation
        }

        if !weightedSizes.isEmpty {
            var totalWeightedSize : z3.expr = context.real_val(Int32(0))
            for size in weightedSizes {
                totalWeightedSize = totalWeightedSize + size
            }
            let avgWeightedSize : z3.expr = totalWeightedSize / context.real_val(Int32(weightedSizes.count))

            for size in weightedSizes {
                let imbalance : z3.expr = z3.abs(size - avgWeightedSize)
                objective = objective - realVal(balanceWeight) * imbalance
            }
        }

        _ = optimizer.maximize(objective)

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

        return true
    }
}
