//
//  LayoutSolver.swift
//  Tessera
//
//  Created by Aarav Bhatt on 15/06/2026.
//

import Foundation
import Z3

actor LayoutSolver {
    
    // Maps from the string name of variables to the window it refers to
    var widthVars : [String : WindowData] = [:]
    var heightVars : [String : WindowData] = [:]
    var xVars : [String : WindowData] = [:]
    var yVars : [String : WindowData] = [:]
    
    // Adds a window set of variables
    func addWindow(window : WindowData) async -> Void {
        let widthVar : String = await window.getWindowWidthVar()
        let heightVar : String = await window.getWindowHeightVar()
        let xVar : String = await window.getWindowXVar()
        let yVar : String = await window.getWindowYVar()
        widthVars.updateValue(window, forKey: widthVar)
        heightVars.updateValue(window, forKey: heightVar)
        xVars.updateValue(window, forKey: xVar)
        yVars.updateValue(window, forKey: yVar)
    }
    
    func solve() -> [WindowData]? {
        var context = z3.context()
        
        // Adds variables to the context
        var variables : [String : z3.expr] = [:]
        for key in widthVars.keys {
            variables.updateValue(context.int_const(key), forKey: key)
        }
        for key in heightVars.keys {
            variables.updateValue(context.int_const(key), forKey: key)
        }
        for key in xVars.keys {
            variables.updateValue(context.int_const(key), forKey: key)
        }
        for key in yVars.keys {
            variables.updateValue(context.int_const(key), forKey: key)
        }
        
        let x : z3.expr = context.int_const("x")
        let y : z3.expr = context.int_const("y")
        var solver = z3.solver(&context)
        solver.add(x > 2)
        solver.add(y > 0)
        solver.add(x + y < 5)
        let check : z3.check_result = solver.check()
        guard check == z3.sat else {
            return nil
        }
        let model : z3.model = solver.get_model()
        let x_val = model.eval(x)
        let y_val = model.eval(y)
        print ("x : \(x_val.as_int64()) and y : \(y_val.as_int64())")
        return nil
    }
}
