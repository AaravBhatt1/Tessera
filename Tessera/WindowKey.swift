//
//  WindowKey.swift
//  Tessera
//
//  Hashable wrapper around AXUIElement for use as a dictionary/set key.
//  Uses Core Foundation's CFEqual + CFHash so two AXUIElement handles that
//  refer to the same window compare equal and hash to the same bucket.
//

import Foundation
import ApplicationServices

struct WindowKey: Hashable {
    let element: AXUIElement
    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
        return CFEqual(lhs.element, rhs.element)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
