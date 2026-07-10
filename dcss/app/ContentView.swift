//
//  ContentView.swift
//  dcss (ASCII/console target — Target B)
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var model: GameModel

    private let stripHeight: CGFloat = 46
    private let barHeight: CGFloat = 92    // in-game portrait: two compact rows + grabber
                                           // (kept small so the viewport still fits the
                                           // engine's 37-row stacked-layout minimum —
                                           // otherwise the message log clamps off-screen)
    @State private var barExpanded = false // pulled-up 3rd row of less-used shortcuts

    var body: some View {
      ZStack(alignment: .top) {
        GeometryReader { geo in
            // When the keyboard is up, the accessory bar carries Esc/Tab/Hide,
            // so the floating strip hides; the scroll viewport shrinks above the
            // keyboard (the grid is unchanged — no resize, no blanking).
            let kbd = model.keyboardHeight
            let keyboardDown = kbd == 0
            // Reserved bottom region: title strip, or the in-game portrait bar.
            // In-game landscape the bar floats (no reserve); keyboard up hides the
            // bar (the keyboard accessory carries Esc/Tab/Hide).
            let bottomReserved: CGFloat = !keyboardDown ? 0
                : !model.inGame ? stripHeight
                : (model.portrait ? barHeight : 0)
            let viewportH = max(1, geo.size.height - bottomReserved - kbd)

            VStack(spacing: 0) {
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical]) {
                            ConsoleCanvas(model: model)
                                .frame(width: CGFloat(model.cols) * model.cellW,
                                       height: CGFloat(model.rows) * model.cellH)
                                .overlay(alignment: .topLeading) {
                                    // Zero-size anchor at the grid origin.
                                    Color.clear.frame(width: 1, height: 1).id("origin")
                                }
                        }
                        // Leaving a menu (where the wide grid was scrolled right)
                        // would otherwise strand the game off-screen — the D-pad
                        // eats drags so there's no way to scroll back. Snap to the
                        // top-left when the overlay closes.
                        .onChange(of: model.menuOpen) { _, open in
                            if !open { proxy.scrollTo("origin", anchor: .topLeading) }
                        }
                        // Rotation reflows the grid to a new size; the old scroll
                        // offset would otherwise leave the map shifted/cut off.
                        .onChange(of: model.cols) { proxy.scrollTo("origin", anchor: .topLeading) }
                        .onChange(of: model.rows) { proxy.scrollTo("origin", anchor: .topLeading) }
                    }
                    // Touch D-pad: shown in-game while no menu/prompt overlay is
                    // open. Gating on the stable menuOpen signal (not the
                    // per-turn waiting_for_command flicker) keeps gestures from
                    // being cancelled mid-press, and leaves menus fully
                    // scrollable underneath when one is open.
                    if model.inGame && !model.menuOpen {
                        TouchControlsOverlay(model: model)
                    }
                    // Landscape: the assignable bar floats over the right map edge.
                    if model.inGame && !model.portrait && keyboardDown {
                        InGameControls(model: model, portrait: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .padding(.trailing, 6)
                    }
                }
                .frame(width: geo.size.width, height: viewportH)
                .background(Color.black)

                // Title strip stays in-flow. The in-game portrait bar is a bottom
                // overlay (below) so the expanded 3rd row can grow up over the game.
                if keyboardDown && !model.inGame {
                    ControlStrip(model: model)
                        .frame(width: geo.size.width, height: stripHeight)
                }

                Spacer(minLength: 0)   // reserves the keyboard region
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .background(KeyboardInputView(model: model))   // invisible responder
            // In-game portrait bar: bottom-anchored overlay. Collapsed it fills the
            // reserved barHeight; expanded it grows upward over the gameplay area.
            .overlay(alignment: .bottom) {
                if keyboardDown && model.inGame && model.portrait {
                    InGameBar(model: model, expanded: $barExpanded)
                }
            }
            // Size the engine grid to the ACTUAL visible viewport so the message
            // log (bottom rows) isn't laid out below the fold. The reserve differs
            // by state (title strip vs in-game bar; landscape bar floats), so
            // resize when inGame/portrait change too — not just on rotation.
            .onAppear { resizeEngine(geo) }
            .onChange(of: geo.size) { resizeEngine(geo) }
            .onChange(of: model.inGame) { resizeEngine(geo) }
            .onChange(of: model.portrait) { resizeEngine(geo) }
        }

        // Esc lives up in the top safe-area band, beside the Dynamic Island/notch
        // (portrait: to its right; landscape: top-leading). It ignores the top
        // inset so it sits level with the island rather than below the game.
        if model.inGame {
            EscButton(model: model)
                .frame(maxWidth: .infinity,
                       alignment: model.portrait ? .trailing : .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)   // clear the screen-corner curve
                .ignoresSafeArea(.container, edges: .top)
        }
      }
      .ignoresSafeArea(.keyboard)        // we size the game above the keyboard ourselves
      .background(Color.black.ignoresSafeArea())   // full-bleed background
    }

    // Bottom space reserved by the bar/strip (keyboard excluded — its show/hide
    // intentionally doesn't resize the engine, just shrinks the scroll viewport).
    private func engineReserve() -> CGFloat {
        !model.inGame ? stripHeight : (model.portrait ? barHeight : 0)
    }

    private func resizeEngine(_ geo: GeometryProxy) {
        model.setEngineGrid(width: geo.size.width,
                            height: max(1, geo.size.height - engineReserve()))
    }
}

struct ConsoleCanvas: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Canvas { ctx, _ in
            let cw = model.cellW, ch = model.cellH
            let cols = model.cols, rows = model.rows
            let font = Font.custom("Menlo", fixedSize: model.fontSize)

            for y in 0..<rows {
                for x in 0..<cols {
                    var u: UInt32 = 0, fg: UInt8 = 0, bg: UInt8 = 0
                    ios_console_get(Int32(x), Int32(y), &u, &fg, &bg)
                    let rect = CGRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch,
                                      width: cw, height: ch)
                    if bg != 0 {
                        ctx.fill(Path(rect), with: .color(palette[Int(bg & 15)]))
                    }
                    if u != 0, u != 32, let scalar = Unicode.Scalar(u) {
                        let text = Text(String(scalar))
                            .font(font)
                            .foregroundColor(palette[Int(fg & 15)])
                        ctx.draw(text, at: CGPoint(x: rect.minX, y: rect.minY),
                                 anchor: .topLeading)
                    }
                }
            }
        }
        .background(Color.black)
    }
}

// Floating controls shown when the software keyboard is down.
struct ControlStrip: View {
    @ObservedObject var model: GameModel

    var body: some View {
        let _ = model.tick                       // refresh as engine state changes
        let inGame = ios_console_in_game() != 0
        return HStack(spacing: 8) {
            // In-game: just Esc (cancel/back out). On the title/menu screens,
            // offer the documented Ctrl-P (view rc/log) and Tab for navigation;
            // both are hidden in-game.
            if inGame {
                keyButton("Esc") { ios_push_key_esc() }
            } else {
                keyButton("Ctrl-P") { ios_console_push_key(16) }   // ^P
                keyButton("Tab") { ios_push_key_tab() }
            }
            Spacer()
            // Move the selection and confirm on the title/menu screens.
            keyButton("↑") { ios_push_key_up() }
            keyButton("↓") { ios_push_key_down() }
            keyButton("⏎") { ios_push_key_enter() }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.12))
        // Grabber hint: swipe up anywhere on the strip to raise the keyboard.
        .overlay(alignment: .top) {
            Capsule().fill(Color(white: 0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 5)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -24 { model.wantsKeyboard = true }
                }
        )
    }

    private func keyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(white: 0.25))
                .cornerRadius(8)
        }
    }
}

// MARK: - In-game assignable button bar

// Portrait bottom bar. Collapsed: two rows of primary shortcuts. Grabber gesture
// is staged: swipe up once → reveal a 3rd row of less-used shortcuts (overlaying
// the game); swipe up again → raise the keyboard; swipe down → collapse. When a
// menu is open it shows the nav cluster instead and a swipe up raises the keyboard.
struct InGameBar: View {
    @ObservedObject var model: GameModel
    @Binding var expanded: Bool

    private let collapsedHeight: CGFloat = 92
    private let expandedHeight: CGFloat = 134   // + one more row

    var body: some View {
        let showExpanded = expanded && !model.menuOpen
        VStack(spacing: 3) {
            Capsule().fill(Color(white: 0.5)).frame(width: 36, height: 4).padding(.top, 3)
            if model.menuOpen {
                MenuNavCluster(model: model, portrait: true)
            } else {
                CommandGrid(model: model, portrait: true, rows: showExpanded ? 3 : 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: showExpanded ? expandedHeight : collapsedHeight, alignment: .top)
        .background(Color(white: 0.12))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    if v.translation.height < -24 {              // swipe up
                        if model.menuOpen {
                            model.wantsKeyboard = true
                        } else if !expanded {
                            withAnimation(.easeOut(duration: 0.15)) { expanded = true }
                        } else {
                            expanded = false; model.wantsKeyboard = true
                        }
                    } else if v.translation.height > 24 {        // swipe down
                        if expanded { withAnimation(.easeOut(duration: 0.15)) { expanded = false } }
                    }
                }
        )
    }
}

// Picks the command grid or the menu-nav cluster based on menuOpen. In landscape
// it floats dim-but-readable over the map; portrait gets its panel from InGameBar.
struct InGameControls: View {
    @ObservedObject var model: GameModel
    let portrait: Bool

    var body: some View {
        let _ = model.tick                       // refresh labels as state changes
        Group {
            if model.menuOpen {
                MenuNavCluster(model: model, portrait: portrait)
            } else {
                CommandGrid(model: model, portrait: portrait)
            }
        }
        .modifier(FloatBacking(active: !portrait))
    }
}

// Translucent backing + reduced opacity for the floating landscape cluster.
private struct FloatBacking: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.45)))
                .opacity(0.65)
        } else {
            content
        }
    }
}

struct CommandGrid: View {
    @ObservedObject var model: GameModel
    let portrait: Bool
    var rows: Int = 2          // portrait row count (2 collapsed, 3 expanded)

    var body: some View {
        if portrait {
            VStack(spacing: 5) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(0..<5, id: \.self) { col in
                            SlotButton(model: model, bar: model.bar, slot: row * 5 + col, portrait: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        } else {
            // Landscape: three columns of five (room on the wide screen).
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { col in
                    VStack(spacing: 5) {
                        ForEach(0..<5, id: \.self) { row in
                            SlotButton(model: model, bar: model.bar, slot: col * 5 + row, portrait: false)
                        }
                    }
                }
            }
            .frame(width: 196)
        }
    }
}

// One assignable slot. Assigned: tap fires (gated on !menuOpen), long-press =
// assign menu. Empty: shows '+', tap opens the assign menu.
struct SlotButton: View {
    @ObservedObject var model: GameModel
    @ObservedObject var bar: ButtonBarModel   // observe the bar so assigns refresh
    let slot: Int
    let portrait: Bool

    private var cmd: GameCommand? { bar.command(at: slot, portrait: portrait) }

    var body: some View {
        let _ = model.tick
        Group {
            if let cmd {
                Button {
                    ios_console_push_key(cmd.key); model.haptic()
                } label: { face(cmd) }
                .disabled(model.menuOpen)
                .contextMenu { assignMenu() }
            } else {
                Menu { assignMenu() } label: { face(nil) }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 34, maxHeight: .infinity)
    }

    @ViewBuilder private func face(_ cmd: GameCommand?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(white: cmd == nil ? 0.18 : 0.28))
            if let cmd {
                Text(cmd.label)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.55).padding(.horizontal, 3)
                Text(SlotButton.keyGlyph(cmd.key))
                    .font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
            } else {
                Image(systemName: "plus").foregroundColor(.white.opacity(0.35))
            }
        }
        .frame(minHeight: 34, maxHeight: .infinity)
        .opacity(cmd != nil && model.menuOpen ? 0.35 : 1)
    }

    @ViewBuilder private func assignMenu() -> some View {
        if cmd != nil {
            Button(role: .destructive) {
                bar.clear(slot: slot, portrait: portrait)
            } label: { Label("Clear slot", systemImage: "xmark.circle") }
        }
        ForEach(CommandCatalog.categories) { cat in
            Menu(cat.name) {
                ForEach(cat.commands) { c in
                    Button {
                        bar.assign(token: c.name, slot: slot, portrait: portrait)
                    } label: {
                        if c.id == cmd?.id { Label(c.label, systemImage: "checkmark") }
                        else { Text(c.label) }
                    }
                }
            }
        }
    }

    // Compact glyph for a keystroke shown in the button corner.
    static func keyGlyph(_ key: Int32) -> String {
        switch key {
        case 9:  return "⇥"
        case 13: return "⏎"
        case 27: return "esc"
        case 32: return "␣"
        default:
            if key >= 33 && key < 127, let s = Unicode.Scalar(UInt32(key)) { return String(s) }
            if key >= 1 && key <= 26, let s = Unicode.Scalar(UInt32(key + 64)) { return "^\(s)" }
            return ""
        }
    }
}

// Menu navigation cluster shown when a menu/prompt is open (replaces the grid).
struct MenuNavCluster: View {
    @ObservedObject var model: GameModel
    let portrait: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    navButton("⇞") { ios_push_key_pgup() }
                    navButton("↑") { ios_push_key_up() }
                    navButton("⇟") { ios_push_key_pgdn() }
                }
                HStack(spacing: 6) {
                    navButton("←") { ios_push_key_left() }
                    navButton("↓") { ios_push_key_down() }
                    navButton("→") { ios_push_key_right() }
                }
            }
            navButton("⏎ Enter") { ios_push_key_enter() }
        }
        .padding(.horizontal, 8)
    }

    private func navButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action(); model.haptic()
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 40, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.28)))
        }
    }
}

// Esc button anchored by the notch (in-game only).
struct EscButton: View {
    @ObservedObject var model: GameModel
    var body: some View {
        Button {
            ios_push_key_esc(); model.haptic()
        } label: {
            Text("Esc")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color(white: 0.25)))
        }
    }
}

// MARK: - Touch D-pad overlay (Android-style 3x3)

// A faint 3x3 movement overlay shown over the dungeon. It flashes in then fades
// (on entering the game and on keyboard show/hide) but the zones stay tappable.
// Directions send vi-keys (tap = one step, hold = auto-walk); center taps wait
// (s) and holds rest (5). Haptic feedback on each press.
struct TouchControlsOverlay: View {
    @ObservedObject var model: GameModel
    @State private var opacity: Double = 0

    // (row, col) -> (vi-key, arrow glyph); the centre cell is nil.
    private static let cells: [[(key: Character, glyph: String)?]] = [
        [("y", "\u{2196}"), ("k", "\u{2191}"), ("u", "\u{2197}")],
        [("h", "\u{2190}"),  nil,              ("l", "\u{2192}")],
        [("b", "\u{2199}"), ("j", "\u{2193}"), ("n", "\u{2198}")],
    ]

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width / 3, ch = geo.size.height / 3
            ZStack {
                ForEach(0..<3, id: \.self) { row in
                    ForEach(0..<3, id: \.self) { col in
                        cell(row, col)
                            .frame(width: cw, height: ch)
                            .position(x: cw * (CGFloat(col) + 0.5),
                                      y: ch * (CGFloat(row) + 0.5))
                    }
                }
            }
        }
        .onChange(of: model.hintsToken, initial: true) {
            opacity = 0.5
            withAnimation(.easeOut(duration: 1.6).delay(1.0)) { opacity = 0 }
        }
    }

    @ViewBuilder
    private func cell(_ row: Int, _ col: Int) -> some View {
        if let c = Self.cells[row][col] {
            DirZone(model: model, key: c.key, glyph: c.glyph, hintOpacity: opacity)
        } else {
            CenterZone(model: model, hintOpacity: opacity)
        }
    }
}

private struct DirZone: View {
    @ObservedObject var model: GameModel
    let key: Character
    let glyph: String
    let hintOpacity: Double
    @State private var timer: Timer?
    @State private var pressing = false

    var body: some View {
        Color.clear
            .overlay(
                Text(glyph)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white).opacity(hintOpacity).shadow(radius: 2)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        model.haptic()
                        send()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.18,
                                                     repeats: true) { _ in send() }
                    }
                    .onEnded { _ in
                        pressing = false
                        timer?.invalidate(); timer = nil
                    }
            )
            // If the overlay is torn down mid-hold (e.g. a menu opens while
            // auto-walking), stop the repeat and clear the press latch.
            .onDisappear { pressing = false; timer?.invalidate(); timer = nil }
    }

    private func send() { ios_console_push_key(Int32(key.asciiValue ?? 0)) }
}

private struct CenterZone: View {
    @ObservedObject var model: GameModel
    let hintOpacity: Double
    @State private var holdTimer: Timer?
    @State private var pressing = false
    @State private var rested = false

    var body: some View {
        Color.clear
            .overlay(
                VStack(spacing: 2) {
                    Text("wait").font(.system(size: 15, weight: .bold))
                    Text("hold = rest").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white).opacity(hintOpacity).shadow(radius: 2)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true; rested = false
                        model.haptic()
                        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.45,
                                                         repeats: false) { _ in
                            rested = true
                            model.haptic(strong: true)
                            ios_console_push_key(Int32(Character("5").asciiValue!)) // rest
                        }
                    }
                    .onEnded { _ in
                        pressing = false
                        holdTimer?.invalidate(); holdTimer = nil
                        if !rested { ios_console_push_key(Int32(Character("s").asciiValue!)) } // wait
                    }
            )
            .onDisappear { pressing = false; holdTimer?.invalidate(); holdTimer = nil }
    }
}
