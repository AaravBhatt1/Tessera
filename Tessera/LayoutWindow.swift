//
//  LayoutWindow.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import Foundation
import ApplicationServices
import Z3

struct LayoutWindow : Hashable, Equatable {
    let element : AXUIElement
    let app : String
    let title : String
    let x : z3.expr
    let y : z3.expr
    let width : z3.expr
    let height : z3.expr

    static func == (l : LayoutWindow, r : LayoutWindow) -> Bool {
        return CFEqual(l.element, r.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
