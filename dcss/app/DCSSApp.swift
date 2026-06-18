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
    // DCSS menus assume ~80 cols, so the engine grid is at least this wide and
    // the view scrolls. In portrait the font is sized so ~visibleCols fit the
    // screen width (readable); the extra cols are reached by scrolling.
    static let menuCols = 80
    static let visibleCols: CGFloat = 42

    struct Result { let portrait: Bool; let cols, rows: Int
                    let fontSize, cellW, cellH: CGFloat }

    private static func perPoint() -> (charW: CGFloat, lineH: CGFloat) {
        let ref: CGFloat = 12
        let f = UIFont(name: "Menlo", size: ref)
            ?? UIFont.monospacedSystemFont(ofSize: ref, weight: .regular)
        let charW = ("M" as NSString).size(withAttributes: [.font: f]).width / ref
        return (charW, f.lineHeight / ref)
    }

    static func compute(width: CGFloat, height: CGFloat) -> Result {
        let (charW, lineH) = perPoint()
        let portrait = height >= width
        if portrait {
            // Readable font (~visibleCols across the width); wide scrollable grid.
            let size = max(6, min((width / visibleCols) / charW, 22))
            let cellW = size * charW, cellH = size * lineH
            let cols = max(menuCols, Int(width / cellW))
            let rows = max(37, Int(height / cellH))   // >= stacked-layout minimum
            return Result(portrait: true, cols: cols, rows: rows,
                          fontSize: size, cellW: cellW, cellH: cellH)
        } else {
            // Landscape: fit the standard wide layout across the width.
            let minCols: CGFloat = 79, minRows: CGFloat = 24
            let size = max(6, min(min((width / minCols) / charW,
                                      (height / minRows) / lineH), 22))
            let cellW = size * charW, cellH = size * lineH
            let cols = max(Int(minCols), Int(width / cellW))
            let rows = max(Int(minRows), Int(height / cellH))
            return Result(portrait: false, cols: cols, rows: rows,
                          fontSize: size, cellW: cellW, cellH: cellH)
        }
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

    @Published var inGame = false           // a game is in progress (vs title/menu)
    @Published var acceptingMoves = false   // engine waiting for a map command
    @Published var hintsToken = 0           // bump to flash the touch-control hints

    private var started = false
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)

    init() {
        GameModel.shared = self
        observeKeyboard()
        hapticLight.prepare()
        hapticMedium.prepare()
    }

    func bumpTick() {
        tick &+= 1
        let g = ios_console_in_game() != 0
        if g != inGame {
            inGame = g
            if g { flashHints() }            // entered the dungeon
        }
        let a = ios_console_accepting_moves() != 0
        if a != acceptingMoves { acceptingMoves = a }
    }

    func flashHints() { hintsToken &+= 1 }

    func haptic(strong: Bool = false) {
        let g = strong ? hapticMedium : hapticLight
        g.impactOccurred()
        g.prepare()
    }

    // Size the engine grid + render scale for the full-screen area. Called on
    // first layout and on rotation only — NOT when the keyboard appears (the
    // scroll viewport just shrinks; the grid is unchanged so menus don't blank).
    func setEngineGrid(width: CGFloat, height: CGFloat) {
        guard width > 1, height > 1 else { return }
        let g = GridMetrics.compute(width: width, height: height)
        ios_set_force_stacked(g.portrait ? 1 : 0)   // before (re)size → init_geometry sees it
        let changed = (g.cols != cols || g.rows != rows)
        cols = g.cols; rows = g.rows
        cellW = g.cellW; cellH = g.cellH; fontSize = g.fontSize
        if !started {
            ios_console_set_size(Int32(g.cols), Int32(g.rows))
            start()
        } else if changed {
            ios_console_resize(Int32(g.cols), Int32(g.rows))
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
            guard let self, let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect else { return }
            let screenH = UIScreen.main.bounds.height
            let h = max(0, screenH - frame.origin.y)
            if h != self.keyboardHeight { self.keyboardHeight = h; if self.inGame { self.flashHints() } }
        }
        nc.addObserver(forName: UIResponder.keyboardWillHideNotification,
                       object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.keyboardHeight != 0 { self.keyboardHeight = 0; if self.inGame { self.flashHints() } }
        }
    }
}

// Top-level (non-capturing) C callback the engine invokes via update_screen.
func cConsoleRedraw() {
    DispatchQueue.main.async { GameModel.shared?.bumpTick() }
}
