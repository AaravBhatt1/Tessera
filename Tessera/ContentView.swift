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
            Button("Test", action: {
                Task {
                    let windows : [(String, AXUIElement)] = await WindowManager.shared.getAllWindows()
                    for (app, window) in windows {
                        let windowTitle : String = await WindowManager.shared.getWindowTitle(for: window) ?? "unknown"
                        let windowPosition : (Int, Int) = await WindowManager.shared.getWindowPosition(for: window)!
                        print("\(app): \(windowTitle) at \(windowPosition)")
                        await WindowManager.shared.setWindowPosition(for: window, to: (0, 0))
                        
                    }
                    await LayoutSolver().solve()

                }
            })

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
