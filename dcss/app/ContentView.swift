//
//  ContentView.swift
//  dcss (ASCII/console target — Target B)
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var model: GameModel

    private let stripHeight: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            // When the keyboard is up, the accessory bar carries Esc/Tab/Hide,
            // so the floating strip hides; the scroll viewport shrinks above the
            // keyboard (the grid is unchanged — no resize, no blanking).
            let kbd = model.keyboardHeight
            let showStrip = kbd == 0
            let strip = showStrip ? stripHeight : 0
            let viewportH = max(1, geo.size.height - strip - kbd)

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
                }
                .frame(width: geo.size.width, height: viewportH)
                .background(Color.black)

                if showStrip {
                    ControlStrip(model: model)
                        .frame(width: geo.size.width, height: stripHeight)
                }

                Spacer(minLength: 0)   // reserves the keyboard region
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .background(KeyboardInputView(model: model))   // invisible responder
            .onAppear {
                model.setEngineGrid(width: geo.size.width,
                                    height: max(1, geo.size.height - stripHeight))
            }
            .onChange(of: geo.size) {
                model.setEngineGrid(width: geo.size.width,
                                    height: max(1, geo.size.height - stripHeight))
            }
        }
        .ignoresSafeArea(.keyboard)        // we size the game above the keyboard ourselves
        .background(Color.black.ignoresSafeArea())   // full-bleed background
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
