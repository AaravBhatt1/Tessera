//
//  LayoutSolverTests.swift
//  TesseraTests
//
// AI-generated

import Testing
import ApplicationServices
@testable import Tessera

@MainActor
struct LayoutSolverTests {

    @Test func singleWindowSolves() async {
        let solver = LayoutSolver()
        let win = solver.addWindow(element: AXUIElementCreateSystemWide(), app: "TestApp", title: "Test")
        solver.addConstraint(.minimumWidth(window: win, wMin: 200))
        solver.addConstraint(.maximumWidth(window: win, wMax: 800))
        solver.addConstraint(.minimumHeight(window: win, hMin: 200))
        solver.addConstraint(.maximumHeight(window: win, hMax: 600))
        solver.addConstraint(.minimumX(window: win, xMin: 0))
        solver.addConstraint(.maximumX(window: win, xMax: 1920))
        solver.addConstraint(.minimumY(window: win, yMin: 0))
        solver.addConstraint(.maximumY(window: win, yMax: 1080))
        let layout = await solver.solve()
        #expect(layout != nil)
    }

    @Test func unsatisfiableConstraintsReturnNil() async {
        let solver = LayoutSolver()
        let win = solver.addWindow(element: AXUIElementCreateSystemWide(), app: "TestApp", title: "Test")
        solver.addConstraint(.minimumWidth(window: win, wMin: 1000))
        solver.addConstraint(.maximumWidth(window: win, wMax: 100))
        let layout = await solver.solve()
        #expect(layout == nil)
    }

    @Test func hardSizeConstraintsAreRespected() async {
        let solver = LayoutSolver()
        let win = solver.addWindow(element: AXUIElementCreateSystemWide(), app: "TestApp", title: "Test")
        solver.addConstraint(.minimumWidth(window: win, wMin: 400))
        solver.addConstraint(.maximumWidth(window: win, wMax: 400))
        solver.addConstraint(.minimumHeight(window: win, hMin: 300))
        solver.addConstraint(.maximumHeight(window: win, hMax: 300))
        guard let layout = await solver.solve(), let geo = layout.windows.values.first else {
            Issue.record("Solver returned nil")
            return
        }
        #expect(geo.width == 400)
        #expect(geo.height == 300)
    }

    @Test func twoWindowLayoutHasBothWindows() async {
        let solver = LayoutSolver()
        let w1 = solver.addWindow(element: AXUIElementCreateSystemWide(), app: "App1", title: "Win1")
        let w2 = solver.addWindow(element: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier), app: "App2", title: "Win2")
        for w in [w1, w2] {
            solver.addConstraint(.minimumWidth(window: w, wMin: 200))
            solver.addConstraint(.maximumWidth(window: w, wMax: 800))
            solver.addConstraint(.minimumHeight(window: w, hMin: 200))
            solver.addConstraint(.maximumHeight(window: w, hMax: 600))
            solver.addConstraint(.minimumX(window: w, xMin: 0))
            solver.addConstraint(.maximumX(window: w, xMax: 1920))
            solver.addConstraint(.minimumY(window: w, yMin: 0))
            solver.addConstraint(.maximumY(window: w, yMax: 1080))
        }
        let layout = await solver.solve()
        #expect(layout != nil)
        #expect(layout?.windows.count == 2)
    }
}
