//
//  WindowData.swift
//  Tessera
//
//  Created by Aarav Bhatt on 15/06/2026.
//

import Foundation
import ApplicationServices

struct WindowData : Hashable, Equatable {
    let element : AXUIElement

    init(element : AXUIElement) {
        self.element = element
    }

    static func == (l : WindowData, r : WindowData) -> Bool {
        return CFEqual(l.element, r.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }

    func getWindowWidthVar() -> String {
        return "\(CFHash(element))_width"
    }

    func getWindowHeightVar() -> String {
        return "\(CFHash(element))_height"
    }

    func getWindowXVar() -> String {
        return "\(CFHash(element))_x"
    }

    func getWindowYVar() -> String {
        return "\(CFHash(element))_y"
    }
}
