import AppKit
import SwiftUI

/// A small translucent panel in the style of the system volume HUD.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ event: HUDEvent, detail: String? = nil) {
        let (symbol, text) = Self.content(for: event, detail: detail)
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: HUDView(symbol: symbol, text: text))
        let size = host.fittingSize
        let effect = panel.contentView as! NSVisualEffectView
        effect.subviews.forEach { $0.removeFromSuperview() }
        host.frame = NSRect(origin: .zero, size: size)
        effect.addSubview(host)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 120)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        // The window shadow is computed from the window's pixels; recompute it for the new size.
        panel.invalidateShadow()

        hideWork?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }

        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (event == .toolbarMissing || event == .needsAccessibility ? 3.5 : 1.3),
                                      execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        // Round the corners with a mask, not layer.cornerRadius: the mask makes the window's
        // corners truly transparent, so the system shadow follows the rounded shape instead of
        // leaving dark square corners.
        effect.maskImage = Self.roundedMask(radius: 18)
        p.contentView = effect
        return p
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    static func content(for event: HUDEvent, detail: String?) -> (String, String) {
        switch event {
        case .pipOn: ("pip.enter", String(localized: "Picture in Picture"))
        case .pipOff: ("pip.exit", String(localized: "PiP off"))
        case .noVideo: ("video.slash", String(localized: "No video in this tab"))
        case .blocked: ("exclamationmark.triangle", String(localized: "This site blocked PiP"))
        case .playing: ("play.fill", String(localized: "Playing"))
        case .paused: ("pause.fill", String(localized: "Paused"))
        case .rate: ("gauge.with.dots.needle.67percent", detail ?? "")
        case .seek: (detail?.hasPrefix("+") == true ? "goforward" : "gobackward", detail ?? "")
        case .muted: ("speaker.slash.fill", String(localized: "Muted"))
        case .unmuted: ("speaker.wave.2.fill", String(localized: "Sound on"))
        case .safariClosed: ("safari", String(localized: "Safari isn't open"))
        case .extensionOff: ("puzzlepiece.extension", String(localized: "Turn on Floatr in Safari Settings"))
        case .toolbarMissing: ("hand.point.up.left", String(localized: "Add the Floatr button to Safari's toolbar"))
        case .needsAccessibility: ("lock.shield", String(localized: "Allow Floatr in Accessibility"))
        }
    }
}

private struct HUDView: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(height: 52)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(minWidth: 168, maxWidth: 260, minHeight: 150)
    }
}
