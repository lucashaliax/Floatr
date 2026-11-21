import Foundation

/// Identifiers and message names shared by the app, the Safari extension and content.js.
enum Floatr {
    static let appBundleID = "app.floatr.Floatr"
    static let extensionBundleID = "app.floatr.Floatr.Extension"

    /// App Group id, read from Info.plist (`FloatrAppGroup` = `$(TeamIdentifierPrefix)app.floatr.shared`)
    /// so it always carries the signing team's prefix.
    static var appGroupID: String {
        Bundle.main.object(forInfoDictionaryKey: "FloatrAppGroup") as? String ?? "app.floatr.shared"
    }

    /// Label of the toolbar item; the app looks for a button with this title when it
    /// has to press the toolbar item through Accessibility.
    static let toolbarLabel = "Floatr"
}

/// Commands sent app → extension → page. Raw values are the message names content.js understands.
enum PiPCommand: String, CaseIterable, Codable, CodingKeyRepresentable {
    case toggle
    case playPause
    case seekBack
    case seekForward
    case slower
    case faster
    case mute
    case nextVideo
    case focusTab   // handled by the extension itself (activates the PiP tab)
}

/// Messages content.js sends to the extension.
enum ScriptMessage: String {
    case hello          // content script loaded; asks for settings
    case videoCheck     // {found: Bool}
    case pipState       // {active: Bool, title: String, host: String, time: Double, duration: Double, rate: Double}
    case result         // {event: String, title: String?} -> HUD
    case needsGesture   // PiP refused without a user gesture -> app presses the toolbar button
}

/// Events shown in the HUD. Raw values are what content.js sends in `result.event`.
enum HUDEvent: String, Codable {
    case pipOn, pipOff, noVideo, blocked, playing, paused, rate, seek, muted, unmuted
    // raised by the app itself
    case safariClosed, extensionOff, toolbarMissing, needsAccessibility
}

/// Darwin notifications (no payload; payload goes through the shared defaults).
enum DarwinName {
    static let event = "app.floatr.event"            // extension -> app: show HUD
    static let needsGesture = "app.floatr.needsGesture" // extension -> app: press toolbar button
    static let settingsChanged = "app.floatr.settingsChanged" // app -> extension
}

enum Darwin {
    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }
}
