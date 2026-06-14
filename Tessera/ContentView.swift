//
//  ContentView.swift
//  Tessera
//
//  Created by Aarav Bhatt on 14/06/2026.
//

import SwiftUI
import SwiftData

// Temporary
import ApplicationServices

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            // Text("Select an item")
            // Temporary
            Button("Test", action: testAS)

        }
    }
    
    // Temporary
    private func testAS() {
        print ("New Call")
        let runningApps : [NSRunningApplication] = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            if let appName : String = app.localizedName {
                                
                let appElement : AXUIElement = AXUIElementCreateApplication(app.processIdentifier)
                
                var windowsListRef : CFTypeRef?
                let result : AXError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsListRef)
                
                if result == .success, let windows = windowsListRef as? [AXUIElement] {
                    for window : AXUIElement in windows {
                        var titleRef : CFTypeRef?
                        let titleResult : AXError = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                        
                        if titleResult == .success, let titleName = titleRef as? String {
                            print ("Window: \(titleName), App: \(appName)")
                        }
                        
                        var positionRef : CFTypeRef?
                        let positionResult : AXError = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
                        
                        if positionResult == .success  {
                            var point = CGPoint.zero
                            AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
                            print ("Position \(point.x), \(point.y)")
                            
                        }
                    }
                }
                
            }
        }
    }
    
    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
