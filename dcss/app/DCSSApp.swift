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
// (stats below the map). The *engine grid* (cols x rows) is chosen by aspect for
// the full screen and only changes on rotation. The *render scale* (font/cell
// size) fits that fixed grid into whatever drawable area is currently free —
// so showing the keyboard just shrinks the font, it does NOT resize/clear the
// engine grid (which would blank menus that don't repaint on resize).
enum GridMetrics {
    // Per-point metrics of Menlo.
    private static func perPoint() -> (charW: CGFloat, lineH: CGFloat) {
        let ref: CGFloat = 12
        let f = UIFont(name: "Menlo", size: ref)
            ?? UIFont.monospacedSystemFont(ofSize: ref, weight: .regular)
        let charW = ("M" as NSString).size(withAttributes: [.font: f]).width / ref
        return (charW, f.lineHeight / ref)
    }

    // Engine grid (cols x rows) for a full-screen area, by aspect.
    static func gridSize(width: CGFloat, height: CGFloat) -> (cols: Int, rows: Int) {
        let portrait = height >= width
        let minCols: CGFloat = portrait ? 42 : 79
        let minRows: CGFloat = portrait ? 37 : 24
        let (charW, lineH) = perPoint()
        let size = max(6, min(min((width / minCols) / charW, (height / minRows) / lineH), 22))
        let cellW = size * charW, cellH = size * lineH
        return (max(Int(minCols), Int(width / cellW)),
                max(Int(minRows), Int(height / cellH)))
    }

    // Largest font that fits a fixed cols x rows grid into the given area.
    static func fit(cols: Int, rows: Int, width: CGFloat, height: CGFloat)
        -> (fontSize: CGFloat, cellW: CGFloat, cellH: CGFloat)
    {
        let (charW, lineH) = perPoint()
        let size = max(4, min(min(width / (CGFloat(cols) * charW),
                                  height / (CGFloat(rows) * lineH)), 22))
        return (size, size * charW, size * lineH)
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

    // Set the engine grid for the full-screen area. Called on first layout and
    // on rotation only — NOT when the keyboard appears (that would clear the
    // grid and blank screens that don't repaint on resize).
    func setEngineGrid(width: CGFloat, height: CGFloat) {
        guard width > 1, height > 1 else { return }
        let g = GridMetrics.gridSize(width: width, height: height)
        let changed = (g.cols != cols || g.rows != rows)
        cols = g.cols; rows = g.rows
        if !started {
            ios_console_set_size(Int32(g.cols), Int32(g.rows))
            rescale(width: width, height: height)
            start()
        } else if changed {
            ios_console_resize(Int32(g.cols), Int32(g.rows))
        }
    }

    // Fit the fixed engine grid into the currently-free drawable area (changes
    // with the keyboard). Pure rendering — never touches the engine.
    func rescale(width: CGFloat, height: CGFloat) {
        guard cols > 0, rows > 0, width > 1, height > 1 else { return }
        let f = GridMetrics.fit(cols: cols, rows: rows, width: width, height: height)
        fontSize = f.fontSize; cellW = f.cellW; cellH = f.cellH
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
