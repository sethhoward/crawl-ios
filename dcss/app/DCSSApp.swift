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

// We drive the window through an App/Scene delegate (rather than WindowGroup) so
// the root can be a UIHostingController subclass that defers the bottom-edge
// system gesture — letting a swipe up from the control strip raise the keyboard
// without first triggering the home-indicator gesture.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let model = GameModel()   // strong owner (GameModel.shared is weak)

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let root = ContentView(model: model)
            .preferredColorScheme(.dark)
        let host = GameHostingController(rootView: root)
        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds   // ensure non-zero size
        window.rootViewController = host
        self.window = window
        window.makeKeyAndVisible()
    }

    // Auto-save when backgrounded so progress survives if iOS kills the app.
    // Hold a background task so the engine thread has time to flush the save.
    func sceneDidEnterBackground(_ scene: UIScene) {
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = app.beginBackgroundTask(withName: "dcss-save") {
            if task != .invalid { app.endBackgroundTask(task); task = .invalid }
        }
        ios_request_save()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if task != .invalid { app.endBackgroundTask(task); task = .invalid }
        }
    }
}

// Hides the status bar and defers the bottom-edge system gesture so the first
// upward swipe from the control strip is captured by the app.
final class GameHostingController<Content: View>: UIHostingController<Content> {
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
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
    @Published var menuOpen = false         // a menu/prompt/help overlay is open
    @Published var hintsToken = 0           // bump to flash the touch-control hints
    @Published var portrait = true          // current layout orientation

    // Assignable in-game button bar (per-orientation slot loadouts, persisted).
    let bar = ButtonBarModel()

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
        let m = ios_console_menu_open() != 0
        if m != menuOpen { menuOpen = m }
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
        if g.portrait != portrait { portrait = g.portrait }
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

// MARK: - Command catalog

// One assignable game command, resolved from the C bridge.
struct GameCommand: Identifiable, Hashable {
    let id: Int          // engine command_type as int (opaque)
    let label: String    // curated short label for the button face
    let name: String     // engine command name (also the persistence token)
    let key: Int32       // default keystroke to send
}

struct CommandCategory: Identifiable {
    let id: Int
    let name: String
    let commands: [GameCommand]
}

// Built once from the bridge. Commands with no bound key are dropped (can't fire).
enum CommandCatalog {
    static let categories: [CommandCategory] = {
        var cats: [CommandCategory] = []
        for c in 0..<Int(ios_cmd_cat_count()) {
            let catName = String(cString: ios_cmd_cat_name(Int32(c)))
            var cmds: [GameCommand] = []
            for i in 0..<Int(ios_cmd_count(Int32(c))) {
                let id = Int(ios_cmd_id(Int32(c), Int32(i)))
                let key = ios_cmd_key(Int32(id))
                guard key != 0 else { continue }
                cmds.append(GameCommand(
                    id: id,
                    label: String(cString: ios_cmd_label(Int32(id))),
                    name: String(cString: ios_cmd_name(Int32(id))),
                    key: key))
            }
            if !cmds.isEmpty { cats.append(CommandCategory(id: c, name: catName, commands: cmds)) }
        }
        return cats
    }()

    private static let byToken: [String: GameCommand] = {
        var m: [String: GameCommand] = [:]
        for cat in categories { for cmd in cat.commands { m[cmd.name] = cmd } }
        return m
    }()

    static func command(forToken token: String) -> GameCommand? { byToken[token] }
}

// MARK: - Assignable button bar model

// Per-orientation loadouts of 10 slots; each slot holds a command token or nil.
// Persisted in UserDefaults so customizations survive launches.
final class ButtonBarModel: ObservableObject {
    static let slotCount = 15   // 2 rows shown by default + a 3rd on pull-up (15 in landscape)

    @Published private(set) var portraitSlots: [String?]
    @Published private(set) var landscapeSlots: [String?]

    // Provisional defaults (final loadout TBD after playtest): seed the first
    // four slots, leave the rest empty.
    private static let defaultTokens: [String?] = {
        var s = [String?](repeating: nil, count: slotCount)
        let seed = ["CMD_AUTOFIGHT", "CMD_EXPLORE", "CMD_INTERLEVEL_TRAVEL", "CMD_FIRE"]
        for (i, t) in seed.enumerated() where i < slotCount { s[i] = t }
        return s
    }()

    init() {
        portraitSlots = ButtonBarModel.load(orientation: "portrait")
        landscapeSlots = ButtonBarModel.load(orientation: "landscape")
    }

    func slots(portrait: Bool) -> [String?] { portrait ? portraitSlots : landscapeSlots }

    func command(at slot: Int, portrait: Bool) -> GameCommand? {
        guard let token = slots(portrait: portrait)[safe: slot] ?? nil else { return nil }
        return CommandCatalog.command(forToken: token)
    }

    func assign(token: String?, slot: Int, portrait: Bool) {
        guard slot >= 0, slot < ButtonBarModel.slotCount else { return }
        if portrait { portraitSlots[slot] = token } else { landscapeSlots[slot] = token }
        ButtonBarModel.save(slots(portrait: portrait), orientation: portrait ? "portrait" : "landscape")
    }

    func clear(slot: Int, portrait: Bool) { assign(token: nil, slot: slot, portrait: portrait) }

    // --- persistence ---
    private static func key(_ orientation: String, _ i: Int) -> String { "btnbar.\(orientation).\(i)" }

    private static func load(orientation: String) -> [String?] {
        let d = UserDefaults.standard
        // First run for this orientation: seed defaults.
        if d.object(forKey: "btnbar.\(orientation).seeded") == nil {
            d.set(true, forKey: "btnbar.\(orientation).seeded")
            for (i, t) in defaultTokens.enumerated() { d.set(t, forKey: key(orientation, i)) }
            return defaultTokens
        }
        return (0..<slotCount).map { d.string(forKey: key(orientation, $0)) }
    }

    private static func save(_ slots: [String?], orientation: String) {
        let d = UserDefaults.standard
        for (i, t) in slots.enumerated() {
            if let t { d.set(t, forKey: key(orientation, i)) } else { d.removeObject(forKey: key(orientation, i)) }
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
