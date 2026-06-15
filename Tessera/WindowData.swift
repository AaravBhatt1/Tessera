//
//  WindowData.swift
//  Tessera
//
//  Created by Aarav Bhatt on 15/06/2026.
//

import Foundation
import ApplicationServices

struct WindowData {
    let id : CGWindowID
    let pid : pid_t
    let x : Int?
    let y : Int?
    let width : Int?
    let height : Int?
    
    // Z3 variable name for width
    func getWindowWidthVar() -> String {
        return "\(id)_width"
    }
    
    // Z3 variable name for height
    func getWindowHeightVar() -> String {
        return "\(id)_height"
    }
    
    // Z3 variable name for x pos
    func getWindowXVar() -> String {
        return "\(id)_x"
    }
    
    // Z3 variable name for y pos
    func getWindowYVar() -> String {
        return "\(id)_y"
    }

}
