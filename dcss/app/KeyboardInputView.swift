//
//  KeyboardInputView.swift
//  dcss (ASCII/console target — Target B)
//
//  The single UIKit bridge: a UIKeyInput-conforming UIView that raises the iOS
//  software keyboard and forwards raw keystrokes to the C backend. It carries
//  an input-accessory bar (Esc / Tab / Hide) pinned to the top of the keyboard
//  — mirroring the on-screen controls so they're reachable while typing, and
//  giving a reliable Hide button. Hardware keyboard arrows/Esc are mapped too.
//

import SwiftUI
import UIKit

struct KeyboardInputView: UIViewRepresentable {
    @ObservedObject var model: GameModel

    func makeUIView(context: Context) -> KeyCaptureView {
        let v = KeyCaptureView()
        v.onHide = { [weak model] in model?.wantsKeyboard = false }
        return v
    }

    func updateUIView(_ uiView: KeyCaptureView, context: Context) {
        let want = model.wantsKeyboard
        DispatchQueue.main.async {
            if want, !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !want, uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }
}

final class KeyCaptureView: UIView, UIKeyInput, UITextInputTraits {
    var onHide: (() -> Void)?

    // UITextInputTraits — keep the keyboard dumb (no autocorrect/suggestions).
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .asciiCapable

    override var canBecomeFirstResponder: Bool { true }

    // MARK: UIKeyInput
    var hasText: Bool { true }

    func insertText(_ text: String) {
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                ios_console_push_key(13)
            } else {
                ios_console_push_key(Int32(scalar.value))
            }
        }
    }

    func deleteBackward() { ios_console_push_key(0x7f) }

    // MARK: Accessory bar (Esc / Tab / Hide), pinned atop the keyboard.
    override var inputAccessoryView: UIView? { accessory }

    private lazy var accessory: UIToolbar = {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        bar.barStyle = .black
        bar.isTranslucent = false
        let esc = UIBarButtonItem(title: "Esc", style: .plain,
                                  target: self, action: #selector(tapEsc))
        let tab = UIBarButtonItem(title: "Tab", style: .plain,
                                  target: self, action: #selector(tapTab))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                                   target: nil, action: nil)
        let hide = UIBarButtonItem(title: "Hide ⌨", style: .done,
                                   target: self, action: #selector(tapHide))
        bar.items = [esc, tab, flex, hide]
        bar.tintColor = .white
        return bar
    }()

    @objc private func tapEsc()  { ios_push_key_esc() }
    @objc private func tapTab()  { ios_push_key_tab() }
    @objc private func tapHide() { resignFirstResponder(); onHide?() }

    // MARK: Hardware keyboard (Bluetooth / Magic Keyboard) extras.
    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow,    modifierFlags: [], action: #selector(hwUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow,  modifierFlags: [], action: #selector(hwDown)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow,  modifierFlags: [], action: #selector(hwLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(hwRight)),
            UIKeyCommand(input: UIKeyCommand.inputEscape,     modifierFlags: [], action: #selector(hwEsc)),
        ]
    }
    @objc private func hwUp()    { ios_push_key_up() }
    @objc private func hwDown()  { ios_push_key_down() }
    @objc private func hwLeft()  { ios_push_key_left() }
    @objc private func hwRight() { ios_push_key_right() }
    @objc private func hwEsc()   { ios_push_key_esc() }
}
