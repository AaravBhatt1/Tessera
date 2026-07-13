//
//  LockStore.swift
//  Tessera
//
//  Created by Aarav Bhatt on 13/07/2026.
//

import Foundation
import ApplicationServices

@MainActor
final class LockStore {
    static let shared = LockStore()

    private var locked: Set<WindowKey> = []

    func isLocked(_ element: AXUIElement) -> Bool {
        return locked.contains(WindowKey(element: element))
    }

    func lock(_ element: AXUIElement) {
        locked.insert(WindowKey(element: element))
    }

    func unlock(_ element: AXUIElement) {
        locked.remove(WindowKey(element: element))
    }

    func toggle(_ element: AXUIElement) {
        if isLocked(element) {
            unlock(element)
        } else {
            lock(element)
        }
    }
}
