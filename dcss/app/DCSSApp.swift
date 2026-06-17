//
//  DCSSApp.swift
//  dcss (ASCII/console target — Target B)
//
//  SwiftUI entry point. Owns the GameModel, which bridges the SwiftUI layer
//  to the C console backend (console_bridge.h / libios.mm) and launches the
//  crawl engine on a background thread.
//

import SwiftUI
import UIKit

@main
struct DCSSApp: App {
    @StateObject private var model = GameModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .statusBarHidden(true)
                .preferredColorScheme(.dark)
        }
    }
}

// DCSS COLOURS (0-15) -> SwiftUI Color, matching the old UIKit palette.
let palette: [Color] = [
    Color(red:   0/255, green:   0/255, blue:   0/255), // black
    Color(red:   0/255, green:   0/255, blue: 170/255), // blue
    Color(red:   0/255, green: 170/255, blue:   0/255), // green
    Color(red:   0/255, green: 170/255, blue: 170/255), // cyan
    Color(red: 170/255, green:   0/255, blue:   0/255), // red
    Color(red: 170/255, green:   0/255, blue: 170/255), // magenta
    Color(red: 170/255, green:  85/255, blue:   0/255), // brown
    Color(red: 170/255, green: 170/255, blue: 170/255), // lightgrey
    Color(red:  85/255, green:  85/255, blue:  85/255), // darkgrey
    Color(red:  85/255, green:  85/255, blue: 255/255), // lightblue
    Color(red:  85/255, green: 255/255, blue:  85/255), // lightgreen
    Color(red:  85/255, green: 255/255, blue: 255/255), // lightcyan
    Color(red: 255/255, green:  85/255, blue:  85/255), // lightred
    Color(red: 255/255, green:  85/255, blue: 255/255), // lightmagenta
    Color(red: 255/255, green: 255/255, blue:  85/255), // yellow
    Color(red: 255/255, green: 255/255, blue: 255/255), // white
]

// Grid sizing. Console DCSS needs a wide layout (>= ~79 cols, stats to the
// right) OR — with our viewgeom patch — a narrower portrait "stacked" layout
// (stats below the map). Pick targets by aspect, then the largest font that
// still meets the minimum cols x rows for that layout.
struct GridMetrics {
    let cols: Int
    let rows: Int
    let fontSize: CGFloat
    let cellW: CGFloat
    let cellH: CGFloat

    static func compute(width: CGFloat, height: CGFloat) -> GridMetrics {
        let portrait = height >= width
        let minCols: CGFloat = portrait ? 42 : 79
        let minRows: CGFloat = portrait ? 37 : 24

        // Per-point metrics from a reference font.
        let ref: CGFloat = 12
        let refFont = UIFont(name: "Menlo", size: ref)
            ?? UIFont.monospacedSystemFont(ofSize: ref, weight: .regular)
        let charWPerPt = ("M" as NSString).size(withAttributes: [.font: refFont]).width / ref
        let lineHPerPt = refFont.lineHeight / ref

        let sizeForCols = (width / minCols) / charWPerPt
        let sizeForRows = (height / minRows) / lineHPerPt
        let fontSize = max(6, min(min(sizeForCols, sizeForRows), 22))

        let font = UIFont(name: "Menlo", size: fontSize)
            ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let cellW = ("M" as NSString).size(withAttributes: [.font: font]).width
        let cellH = font.lineHeight
        let cols = max(Int(minCols), Int(width / cellW))
        let rows = max(Int(minRows), Int(height / cellH))
        return GridMetrics(cols: cols, rows: rows, fontSize: fontSize,
                           cellW: cellW, cellH: cellH)
    }
}

final class GameModel: ObservableObject {
    static weak var shared: GameModel?

    @Published var tick: Int = 0            // bumped on every engine redraw
    @Published var cols: Int = 80
    @Published var rows: Int = 24
    @Published var cellW: CGFloat = 8
    @Published var cellH: CGFloat = 14
    @Published var fontSize: CGFloat = 12
    @Published var keyboardHeight: CGFloat = 0
    @Published var wantsKeyboard: Bool = false

    private var started = false

    init() {
        GameModel.shared = self
        observeKeyboard()
    }

    func bumpTick() { tick &+= 1 }

    // Called by ContentView whenever the drawable area changes (layout,
    // rotation, keyboard show/hide).
    func apply(width: CGFloat, height: CGFloat) {
        guard width > 1, height > 1 else { return }
        let m = GridMetrics.compute(width: width, height: height)
        let dimsChanged = (m.cols != cols || m.rows != rows)
        cols = m.cols; rows = m.rows
        cellW = m.cellW; cellH = m.cellH; fontSize = m.fontSize
        if !started {
            ios_console_set_size(Int32(m.cols), Int32(m.rows))
            start()
        } else if dimsChanged {
            ios_console_resize(Int32(m.cols), Int32(m.rows))
        }
    }

    private func start() {
        started = true
        ios_console_set_redraw(cConsoleRedraw)
        let docs = getDocumentURL()?.path ?? NSTemporaryDirectory()
        DispatchQueue.global(qos: .userInitiated).async {
            docs.withCString { _ = CDDA_iOS_main($0) }
        }
    }

    private func observeKeyboard() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                       object: nil, queue: .main) { [weak self] note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect else { return }
            let screenH = UIScreen.main.bounds.height
            self?.keyboardHeight = max(0, screenH - frame.origin.y)
        }
        nc.addObserver(forName: UIResponder.keyboardWillHideNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.keyboardHeight = 0
        }
    }
}

// Top-level (non-capturing) C callback the engine invokes via update_screen.
func cConsoleRedraw() {
    DispatchQueue.main.async { GameModel.shared?.bumpTick() }
}
