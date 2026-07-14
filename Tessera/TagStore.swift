//
//  TagStore.swift
//  Tessera
//
//  Created by Aarav Bhatt on 13/07/2026.
//

import Foundation
import ApplicationServices

@MainActor
final class TagStore {
    static let shared = TagStore()

    private var windowTags: [WindowKey: Set<String>] = [:]

    var allKnownTags: Set<String> {
        var out: Set<String> = []
        for (_, tags) in windowTags {
            out.formUnion(tags)
        }
        return out
    }

    func tags(for element: AXUIElement) -> Set<String> {
        return windowTags[WindowKey(element: element)] ?? []
    }

    func hasTag(_ tag: String, for element: AXUIElement) -> Bool {
        return tags(for: element).contains(tag)
    }

    func addTag(_ tag: String, to element: AXUIElement) {
        windowTags[WindowKey(element: element), default: []].insert(tag)
    }

    func removeTag(_ tag: String, from element: AXUIElement) {
        let key = WindowKey(element: element)
        windowTags[key]?.remove(tag)
        if windowTags[key]?.isEmpty == true {
            windowTags.removeValue(forKey: key)
        }
    }

    func toggleTag(_ tag: String, on element: AXUIElement) {
        if hasTag(tag, for: element) {
            removeTag(tag, from: element)
        } else {
            addTag(tag, to: element)
        }
    }

    func resetAll() {
        windowTags.removeAll()
    }
}
