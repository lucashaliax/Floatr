import AppKit
import ApplicationServices

/// Presses the Floatr button in Safari's toolbar through the Accessibility API.
///
/// Safari only allows Picture in Picture when the request comes from a user action.
/// A click on an extension's toolbar button counts as one (that is how PiPifier works),
/// so when a direct message is refused the app "clicks" the button for the user.
enum AccessibilityPresser {
    enum Outcome { case pressed, notTrusted, safariClosed, buttonNotFound }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func pressToolbarButton() -> Outcome {
        guard isTrusted else { return .notTrusted }
        guard let safari = SafariBridge.safariApp else { return .safariClosed }
        let app = AXUIElementCreateApplication(safari.processIdentifier)

        var windows: [AXUIElement] = []
        if let main: AXUIElement = attribute(app, kAXMainWindowAttribute) { windows.append(main) }
        if let all: [AXUIElement] = attribute(app, kAXWindowsAttribute) { windows.append(contentsOf: all) }

        for window in windows {
            if let button = findButton(in: window, depth: 0) {
                return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success ? .pressed : .buttonNotFound
            }
        }
        return .buttonNotFound
    }

    // MARK: - Tree search

    private static func findButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 9 else { return nil }
        let role: String? = attribute(element, kAXRoleAttribute)
        if role == kAXButtonRole || role == "AXMenuButton" {
            let labels: [String?] = [attribute(element, kAXDescriptionAttribute),
                                     attribute(element, kAXTitleAttribute),
                                     attribute(element, kAXHelpAttribute)]
            if labels.contains(where: { $0?.localizedCaseInsensitiveContains(Floatr.toolbarLabel) == true }) {
                return element
            }
        }
        // Web content is huge and never contains the toolbar; skip it.
        if role == "AXWebArea" || role == "AXScrollArea" && depth > 2 { return nil }
        guard let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return nil }
        for child in children {
            if let found = findButton(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
