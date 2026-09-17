//
//  ShowsProgressBarTests.swift
//  SwiftTermTests
//
//  A host that draws progress in its own chrome turns the built-in bar off,
//  and no report it keeps receiving may draw one behind its back.
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

@MainActor
struct ShowsProgressBarTests {

    private func makeView() -> TerminalView {
        TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
    }

    private func progressBar(of view: TerminalView) -> TerminalProgressBarView? {
        view.subviews.compactMap { $0 as? TerminalProgressBarView }.first
    }

    /// The view parses on its I/O thread and hops to the main queue before it
    /// touches the bar, so a test waits for the effect rather than for a fixed
    /// slice. The deadline is only a backstop.
    private func settle(until satisfied: () -> Bool) async {
        let deadline = Date(timeIntervalSinceNow: 10)
        while !satisfied(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Long enough for a bar that should not have appeared to have appeared.
    private func waitOut(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    @Test func theBarIsDrawnByDefault() async {
        let view = makeView()
        #expect(view.showsProgressBar)

        view.feed(text: "\u{1b}]9;4;1;40\u{07}")
        await settle { self.progressBar(of: view)?.isHidden == false }

        #expect(progressBar(of: view)?.isHidden == false)
    }

    @Test func turningItOffKeepsEveryReportOffScreen() async {
        let view = makeView()
        view.showsProgressBar = false

        view.feed(text: "\u{1b}]9;4;1;40\u{07}")
        await waitOut(0.3)
        #expect(progressBar(of: view)?.isHidden != false)

        view.feed(text: "\u{1b}]9;4;3\u{07}")
        await waitOut(0.3)
        #expect(progressBar(of: view)?.isHidden != false)
    }

    /// The host still hears what it turned off, which is the whole point of
    /// turning it off.
    @Test func theDelegateStillHearsTheReports() async {
        final class Recorder: TerminalViewDelegate {
            nonisolated(unsafe) var reports: [Terminal.ProgressReport] = []
            func scrolled(source: TerminalView, position: Double) {}
            func setTerminalTitle(source: TerminalView, title: String) {}
            func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
            func send(source: TerminalView, data: ArraySlice<UInt8>) {}
            func clipboardCopy(source: TerminalView, content: Data) {}
            func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
            func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
            func bell(source: TerminalView) {}
            func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
            func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
            nonisolated func progressReport(source: TerminalView, report: Terminal.ProgressReport) {
                reports.append(report)
            }
        }

        let view = makeView()
        let recorder = Recorder()
        view.terminalDelegate = recorder
        view.showsProgressBar = false

        view.feed(text: "\u{1b}]9;4;1;40\u{07}")
        await settle { recorder.reports.isEmpty == false }

        #expect(recorder.reports.first?.state == .set)
        #expect(recorder.reports.first?.progress == 40)
        #expect(progressBar(of: view)?.isHidden != false)
    }

    /// Turning it off mid-task takes the bar that is already on screen down.
    @Test func turningItOffTakesALiveBarDown() async {
        let view = makeView()
        view.feed(text: "\u{1b}]9;4;1;40\u{07}")
        await settle { self.progressBar(of: view)?.isHidden == false }

        view.showsProgressBar = false

        #expect(progressBar(of: view)?.isHidden == true)
    }

    /// And turning it back on returns the report the program is still running,
    /// rather than waiting for the next one.
    @Test func turningItBackOnRestoresALiveReport() async {
        let view = makeView()
        view.progressReportTimeout = nil
        view.feed(text: "\u{1b}]9;4;1;40\u{07}")
        await settle { self.progressBar(of: view)?.isHidden == false }

        view.showsProgressBar = false
        #expect(progressBar(of: view)?.isHidden == true)

        view.showsProgressBar = true
        #expect(progressBar(of: view)?.isHidden == false)
    }

    /// A program that ended its work while the bar was off leaves nothing to
    /// come back to.
    @Test func turningItBackOnAfterTheProgramFinishedShowsNothing() async {
        let view = makeView()
        view.feed(text: "\u{1b}]9;4;1;40\u{07}")
        await settle { self.progressBar(of: view)?.isHidden == false }

        view.showsProgressBar = false
        view.feed(text: "\u{1b}]9;4;0\u{07}")
        await waitOut(0.3)

        view.showsProgressBar = true

        #expect(progressBar(of: view)?.isHidden == true)
    }
}
#endif
