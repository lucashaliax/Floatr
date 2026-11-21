import Foundation

/// A keyboard shortcut stored as a virtual key code plus Carbon modifier flags,
/// which is exactly what `RegisterEventHotKey` takes.
struct Shortcut: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    // Carbon modifier bits (Events.h), repeated here so Shared code needs no Carbon import.
    static let cmd: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    /// A global shortcut needs at least one of ⌘ ⌃ ⌥, otherwise it would swallow plain typing.
    var isValidGlobal: Bool {
        modifiers & (Self.cmd | Self.control | Self.option) != 0
    }

    var modifierSymbols: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.cmd != 0 { s += "⌘" }
        return s
    }
}

extension Shortcut {
    // ANSI virtual key codes (Events.h kVK_*).
    enum Key {
        static let p: UInt32 = 35, returnKey: UInt32 = 36, l: UInt32 = 37, j: UInt32 = 38
        static let k: UInt32 = 40, comma: UInt32 = 43, n: UInt32 = 45, m: UInt32 = 46, period: UInt32 = 47
    }

    private static let ctrlOpt = control | option

    /// Defaults follow YouTube's J/K/L convention, all behind ⌃⌥ to stay clear of app shortcuts.
    /// (⌃⌥Space is avoided on purpose: macOS uses it to switch input sources.)
    static let defaults: [PiPCommand: Shortcut] = [
        .toggle: Shortcut(keyCode: Key.p, modifiers: ctrlOpt),
        .focusTab: Shortcut(keyCode: Key.returnKey, modifiers: ctrlOpt),
        .nextVideo: Shortcut(keyCode: Key.n, modifiers: ctrlOpt),
        .playPause: Shortcut(keyCode: Key.k, modifiers: ctrlOpt),
        .seekBack: Shortcut(keyCode: Key.j, modifiers: ctrlOpt),
        .seekForward: Shortcut(keyCode: Key.l, modifiers: ctrlOpt),
        .slower: Shortcut(keyCode: Key.comma, modifiers: ctrlOpt),
        .faster: Shortcut(keyCode: Key.period, modifiers: ctrlOpt),
        .mute: Shortcut(keyCode: Key.m, modifiers: ctrlOpt),
    ]
}
