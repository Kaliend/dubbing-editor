import SwiftUI

struct MenuShortcutSpec {
    let key: KeyEquivalent
    let modifiers: EventModifiers
}

func shortcutDisplayString(_ rawShortcut: String) -> String {
    guard let parsed = parseShortcutTokens(rawShortcut) else {
        return rawShortcut
    }

    var modifierSymbols = ""
    if parsed.modifiers.contains("cmd") { modifierSymbols += "⌘" }
    if parsed.modifiers.contains("option") { modifierSymbols += "⌥" }
    if parsed.modifiers.contains("ctrl") { modifierSymbols += "⌃" }
    if parsed.modifiers.contains("shift") { modifierSymbols += "⇧" }

    let keySymbol: String
    switch parsed.key {
    case "space":
        keySymbol = "Space"
    case "enter", "return":
        keySymbol = "↩"
    case "up", "uparrow":
        keySymbol = "↑"
    case "down", "downarrow":
        keySymbol = "↓"
    case "left", "leftarrow":
        keySymbol = "←"
    case "right", "rightarrow":
        keySymbol = "→"
    case "tab":
        keySymbol = "⇥"
    case "esc", "escape":
        keySymbol = "⎋"
    default:
        guard parsed.key.count == 1 else { return rawShortcut }
        keySymbol = parsed.key.uppercased()
    }

    return modifierSymbols + keySymbol
}

func shortcutHint(_ title: String, _ rawShortcut: String) -> String {
    let display = shortcutDisplayString(rawShortcut)
    if display.isEmpty || display == rawShortcut {
        return title
    }
    return "\(title) (\(display))"
}

func menuShortcutSpec(from rawShortcut: String) -> MenuShortcutSpec? {
    guard let parsed = parseShortcutTokens(rawShortcut) else {
        return nil
    }

    var modifiers: EventModifiers = []
    if parsed.modifiers.contains("cmd") { modifiers.insert(.command) }
    if parsed.modifiers.contains("option") { modifiers.insert(.option) }
    if parsed.modifiers.contains("ctrl") { modifiers.insert(.control) }
    if parsed.modifiers.contains("shift") { modifiers.insert(.shift) }

    let key: KeyEquivalent
    switch parsed.key {
    case "space":
        key = .space
    case "enter", "return":
        key = .return
    case "up", "uparrow":
        key = .upArrow
    case "down", "downarrow":
        key = .downArrow
    case "left", "leftarrow":
        key = .leftArrow
    case "right", "rightarrow":
        key = .rightArrow
    case "tab":
        key = .tab
    case "esc", "escape":
        key = .escape
    default:
        guard parsed.key.count == 1, let char = parsed.key.first else { return nil }
        key = KeyEquivalent(char)
    }

    return MenuShortcutSpec(key: key, modifiers: modifiers)
}

extension View {
    @ViewBuilder
    func keyboardShortcutIfValid(_ rawShortcut: String) -> some View {
        if let spec = menuShortcutSpec(from: rawShortcut) {
            keyboardShortcut(spec.key, modifiers: spec.modifiers)
        } else {
            self
        }
    }
}

private struct ParsedShortcutTokens {
    let modifiers: Set<String>
    let key: String
}

private func parseShortcutTokens(_ rawShortcut: String) -> ParsedShortcutTokens? {
    let normalized = rawShortcut
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
    guard !normalized.isEmpty else { return nil }

    let tokens = normalized.split(separator: "+").map(String.init)
    guard let keyToken = tokens.last, !keyToken.isEmpty else {
        return nil
    }

    var modifiers: Set<String> = []
    for token in tokens.dropLast() {
        switch token {
        case "cmd", "command", "meta", "⌘":
            modifiers.insert("cmd")
        case "option", "alt", "⌥":
            modifiers.insert("option")
        case "ctrl", "control", "⌃":
            modifiers.insert("ctrl")
        case "shift", "⇧":
            modifiers.insert("shift")
        default:
            return nil
        }
    }

    return ParsedShortcutTokens(modifiers: modifiers, key: keyToken)
}
