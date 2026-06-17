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
                ScrollView([.horizontal, .vertical]) {
                    ConsoleCanvas(model: model)
                        .frame(width: CGFloat(model.cols) * model.cellW,
                               height: CGFloat(model.rows) * model.cellH)
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
        HStack(spacing: 8) {
            keyButton("Esc") { ios_push_key_esc() }
            keyButton("Tab") { ios_push_key_tab() }
            Spacer()
            keyButton("⌨ Keyboard") { model.wantsKeyboard.toggle() }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.12))
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
