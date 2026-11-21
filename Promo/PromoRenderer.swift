// Generates Floatr's promotional images (2880×1800 PNG).
// Run from the repository root:
//   swiftc -O -swift-version 5 Promo/PromoRenderer.swift -o build/promo-render && build/promo-render
import AppKit
import SwiftUI

// MARK: - Palette (from the app icon: indigo → teal, with the warm "picture")

let canvas = CGSize(width: 1440, height: 900)
let ink = Color.white
let inkSecondary = Color(white: 0.66)
let indigo = Color(red: 0.24, green: 0.30, blue: 0.85)
let teal = Color(red: 0.16, green: 0.66, blue: 0.74)
let coral = Color(red: 0.98, green: 0.50, blue: 0.40)
let amber = Color(red: 1.00, green: 0.78, blue: 0.42)

let appIcon = NSImage(contentsOfFile: "docs/icon.png") ?? NSImage()

struct Backdrop: View {
    var glows: [(Color, CGPoint, CGFloat)] = [
        (indigo, CGPoint(x: 0.12, y: 0.10), 620),
        (teal, CGPoint(x: 0.95, y: 0.35), 520),
        (coral, CGPoint(x: 0.70, y: 1.05), 480),
    ]
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.13), Color(red: 0.02, green: 0.02, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
            ForEach(Array(glows.enumerated()), id: \.offset) { _, g in
                Circle().fill(g.0)
                    .frame(width: g.2, height: g.2)
                    .position(x: g.1.x * canvas.width, y: g.1.y * canvas.height)
                    .blur(radius: 150)
                    .opacity(0.5)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }
}

struct Glass: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                shape.fill(Color(white: 0.15).opacity(0.72))
                shape.fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.40), .white.opacity(0.06), .white.opacity(0.16)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
    }
}

extension View {
    func glass(_ radius: CGFloat) -> some View { modifier(Glass(radius: radius)) }
}

// MARK: - Pieces

/// A physical-looking key.
struct Keycap: View {
    var label: String
    var size: CGFloat = 64
    var accent = false
    var body: some View {
        Text(label)
            .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
            .foregroundStyle(accent ? Color(red: 0.15, green: 0.10, blue: 0.08) : ink)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, label.count > 2 ? size * 0.18 : 0)
            .background {
                let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                ZStack {
                    shape.fill(accent
                               ? LinearGradient(colors: [amber, coral], startPoint: .top, endPoint: .bottom)
                               : LinearGradient(colors: [Color(white: 0.30), Color(white: 0.17)], startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(.white.opacity(accent ? 0.5 : 0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.5), radius: 0, y: size * 0.06)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            }
    }
}

struct Keys: View {
    var keys: [String]
    var size: CGFloat = 64
    var accentLast = true
    var body: some View {
        HStack(spacing: size * 0.16) {
            ForEach(Array(keys.enumerated()), id: \.offset) { i, k in
                Keycap(label: k, size: size, accent: accentLast && i == keys.count - 1)
            }
        }
    }
}

/// The warm landscape used as "video" in every mockup (same motif as the icon).
struct VideoScene: View {
    var radius: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [amber, coral, Color(red: 0.80, green: 0.32, blue: 0.48)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 1, green: 0.95, blue: 0.82).opacity(0.95))
                    .frame(width: h * 0.34, height: h * 0.34)
                    .position(x: w * 0.62, y: h * 0.50)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.70))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.62), control1: CGPoint(x: w * 0.30, y: h * 0.48), control2: CGPoint(x: w * 0.62, y: h * 0.88))
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                }
                .fill(Color(red: 0.30, green: 0.16, blue: 0.36).opacity(0.9))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.84))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.80), control1: CGPoint(x: w * 0.4, y: h * 0.72), control2: CGPoint(x: w * 0.7, y: h * 0.95))
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                }
                .fill(Color(red: 0.17, green: 0.09, blue: 0.22))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The floating Picture in Picture window.
struct PiPWindow: View {
    var width: CGFloat = 380
    var controls = true
    var body: some View {
        ZStack(alignment: .bottom) {
            VideoScene(radius: 14)
            if controls {
                HStack(spacing: 26) {
                    Image(systemName: "gobackward.10")
                    Image(systemName: "pause.fill").font(.system(size: 22))
                    Image(systemName: "goforward.10")
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 9)
                .background(Capsule().fill(.black.opacity(0.35)))
                .padding(.bottom, 14)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
    }
}

/// A Safari-like browser window (generic, no real site).
struct BrowserWindow<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    var address = "video.example.com"
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 10))
                    Text(address).font(.system(size: 13))
                }
                .foregroundStyle(inkSecondary)
                .frame(width: width * 0.42, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.10)).frame(width: 30, height: 26)
                    Image(systemName: "pip").font(.system(size: 14)).foregroundStyle(ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color(white: 0.16))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.08))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 24)
    }
}

/// The page while the video floats: the player shows a placeholder, like Safari does.
struct PlayerPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13))
                VStack(spacing: 10) {
                    Image(systemName: "pip").font(.system(size: 40, weight: .light))
                    Text("Playing in Picture in Picture").font(.system(size: 15))
                }
                .foregroundStyle(inkSecondary)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.18)).frame(width: 360, height: 16)
            RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.09)).frame(width: 240, height: 12)
        }
        .padding(28)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct HUDMock: View {
    var symbol: String
    var text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 46)).symbolRenderingMode(.hierarchical)
            Text(text).font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(ink)
        .frame(width: 180, height: 164)
        .glass(22)
    }
}

struct Pill: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 15, weight: .medium)).foregroundStyle(ink)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .glass(20)
    }
}

struct Title: View {
    var text: String
    var size: CGFloat = 72
    var body: some View {
        Text(text).font(.system(size: size, weight: .bold)).tracking(-1.5).foregroundStyle(ink)
    }
}

// MARK: - Slides

struct HeroSlide: View {
    var body: some View {
        ZStack {
            Backdrop()
            HStack(spacing: 56) {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 14) {
                        Image(nsImage: appIcon).resizable().frame(width: 64, height: 64)
                        Text("Floatr").font(.system(size: 30, weight: .semibold)).foregroundStyle(ink)
                    }
                    Text("Any video.\nFloating.\nOne shortcut.")
                        .font(.system(size: 76, weight: .bold)).tracking(-2).lineSpacing(-4)
                        .foregroundStyle(ink)
                    Text("Picture in Picture for every video in Safari,\nright from your keyboard.")
                        .font(.system(size: 23)).foregroundStyle(inkSecondary).lineSpacing(4)
                    Keys(keys: ["⌃", "⌥", "P"], size: 72).padding(.top, 10)
                }
                .frame(width: 500, alignment: .leading)

                ZStack(alignment: .bottomTrailing) {
                    BrowserWindow(width: 620, height: 460) { PlayerPlaceholder() }
                        .padding(.trailing, 70).padding(.bottom, 80)
                    PiPWindow(width: 360)
                }
            }
            .padding(.horizontal, 90)
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

struct StepCard: View {
    var number: Int
    var title: String
    var detail: String
    var art: AnyView
    var body: some View {
        VStack(spacing: 22) {
            art.frame(height: 130)
            Text("\(number)")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Color(red: 0.15, green: 0.10, blue: 0.08))
                .frame(width: 30, height: 30)
                .background(Circle().fill(LinearGradient(colors: [amber, coral], startPoint: .top, endPoint: .bottom)))
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(ink)
            Text(detail).font(.system(size: 19)).foregroundStyle(inkSecondary)
                .multilineTextAlignment(.center).lineSpacing(3).frame(width: 330)
        }
        .padding(.vertical, 44)
        .frame(width: 400)
        .glass(34)
    }
}

struct HowSlide: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 56) {
                VStack(spacing: 16) {
                    Title(text: "Press. Float. Keep working.", size: 66)
                    Text("Floatr finds the video and puts it on top of everything.")
                        .font(.system(size: 23)).foregroundStyle(inkSecondary)
                }
                HStack(spacing: 34) {
                    StepCard(number: 1, title: "Press the shortcut",
                             detail: "From Safari or from any other app. Change it to any keys you like.",
                             art: AnyView(Keys(keys: ["⌃", "⌥", "P"], size: 62)))
                    StepCard(number: 2, title: "The video floats",
                             detail: "Floatr picks the one that's playing, even inside embedded players.",
                             art: AnyView(PiPWindow(width: 220, controls: false)))
                    StepCard(number: 3, title: "Control it anywhere",
                             detail: "Pause, skip and change speed without going back to Safari.",
                             art: AnyView(HStack(spacing: 10) { Keycap(label: "J", size: 58); Keycap(label: "K", size: 58, accent: true); Keycap(label: "L", size: 58) }))
                }
                HStack(spacing: 14) {
                    ForEach(["YouTube", "Vimeo", "Twitch", "Netflix", "Prime Video", "Disney+", "Embedded players", "Any HTML5 video"], id: \.self) { Pill(text: $0) }
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

struct ShortcutRow: View {
    var keys: [String]
    var label: String
    var body: some View {
        HStack(spacing: 18) {
            Keys(keys: keys, size: 46, accentLast: true).frame(width: 190, alignment: .leading)
            Text(label).font(.system(size: 21, weight: .medium)).foregroundStyle(ink)
            Spacer()
        }
    }
}

struct ShortcutsSlide: View {
    var body: some View {
        ZStack {
            Backdrop(glows: [(teal, CGPoint(x: 0.1, y: 0.2), 560), (indigo, CGPoint(x: 0.9, y: 0.1), 560), (coral, CGPoint(x: 0.85, y: 0.95), 420)])
            VStack(spacing: 50) {
                VStack(spacing: 16) {
                    Title(text: "Your video, on your keys.", size: 66)
                    Text("Global shortcuts that work in any app while the video floats.")
                        .font(.system(size: 23)).foregroundStyle(inkSecondary)
                }
                HStack(alignment: .center, spacing: 60) {
                    HStack(alignment: .top, spacing: 50) {
                        VStack(alignment: .leading, spacing: 26) {
                            ShortcutRow(keys: ["⌃", "⌥", "P"], label: "Enter / exit PiP")
                            ShortcutRow(keys: ["⌃", "⌥", "K"], label: "Play / pause")
                            ShortcutRow(keys: ["⌃", "⌥", "J"], label: "Skip back 10 s")
                            ShortcutRow(keys: ["⌃", "⌥", "L"], label: "Skip forward 10 s")
                            ShortcutRow(keys: ["⌃", "⌥", "↩"], label: "Go to the video's tab")
                        }
                        .frame(width: 430)
                        VStack(alignment: .leading, spacing: 26) {
                            ShortcutRow(keys: ["⌃", "⌥", ","], label: "Slower")
                            ShortcutRow(keys: ["⌃", "⌥", "."], label: "Faster")
                            ShortcutRow(keys: ["⌃", "⌥", "M"], label: "Mute")
                            ShortcutRow(keys: ["⌃", "⌥", "N"], label: "Next video")
                        }
                        .frame(width: 360)
                    }
                    .padding(44)
                    .glass(34)
                    VStack(spacing: 22) {
                        HUDMock(symbol: "gauge.with.dots.needle.67percent", text: "1.5×")
                        HUDMock(symbol: "pip.enter", text: "Picture in Picture")
                    }
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

struct SettingsMock: View {
    struct Row: Identifiable { let id = UUID(); let symbol: String; let label: String; let keys: String? }
    let pip = [Row(symbol: "pip", label: "Enter / exit PiP", keys: "⌃⌥P"),
               Row(symbol: "arrow.uturn.backward.square", label: "Go to the video's tab", keys: "⌃⌥↩"),
               Row(symbol: "forward.end", label: "Next video on the page", keys: "⌃⌥N")]
    let controls = [Row(symbol: "playpause", label: "Play / pause", keys: "⌃⌥K"),
                    Row(symbol: "gobackward.10", label: "Skip back", keys: "⌃⌥J"),
                    Row(symbol: "goforward.10", label: "Skip forward", keys: "⌃⌥L"),
                    Row(symbol: "hare", label: "Faster", keys: "⌃⌥."),
                    Row(symbol: "speaker.slash", label: "Mute", keys: nil)]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12)
                    Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12)
                    Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12)
                }
                .padding(.bottom, 22)
                ForEach([("gearshape", "General"), ("keyboard", "Shortcuts"), ("wand.and.stars", "Automation"),
                         ("globe", "Sites"), ("rectangle.bottomthird.inset.filled", "Player buttons"), ("info.circle", "About")], id: \.1) { s, t in
                    Label(t, systemImage: s)
                        .font(.system(size: 15))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7).fill(t == "Shortcuts" ? indigo.opacity(0.8) : .clear))
                }
                Spacer()
            }
            .padding(18)
            .frame(width: 210)
            .background(Color(white: 0.13))

            VStack(alignment: .leading, spacing: 14) {
                Text("Shortcuts").font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Extension is on in Safari").foregroundStyle(ink)
                    Spacer()
                }
                .font(.system(size: 14)).padding(12).background(group)
                Text("Picture in Picture").font(.system(size: 13, weight: .semibold)).foregroundStyle(inkSecondary)
                rows(pip)
                Text("Floating video controls").font(.system(size: 13, weight: .semibold)).foregroundStyle(inkSecondary)
                rows(controls)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(white: 0.09))
        }
        .frame(width: 760, height: 620)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 24)
    }

    private var group: some View {
        RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.07)))
    }

    private func rows(_ items: [Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { r in
                HStack {
                    Label(r.label, systemImage: r.symbol).font(.system(size: 14)).foregroundStyle(ink)
                    Spacer()
                    Text(r.keys ?? "Record shortcut")
                        .font(r.keys == nil ? .system(size: 13) : .system(size: 13, design: .monospaced))
                        .foregroundStyle(r.keys == nil ? inkSecondary : ink)
                        .frame(minWidth: 128).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.20)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(r.label == "Enter / exit PiP" ? amber : .white.opacity(0.12),
                                                                                lineWidth: r.label == "Enter / exit PiP" ? 1.5 : 1))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                if r.id != items.last?.id { Divider().overlay(.white.opacity(0.06)) }
            }
        }
        .background(group)
    }
}

struct ControlSlide: View {
    let points: [(String, String, String)] = [
        ("keyboard", "Any shortcut", "Record your own keys. Floatr warns you about conflicts."),
        ("scope", "The right video", "Playing beats paused, big beats small, embeds included."),
        ("lock.open", "Unblocks PiP", "Works on sites that try to turn Picture in Picture off."),
        ("rectangle.on.rectangle", "Auto PiP", "Switch tabs and the video keeps floating. Per site."),
        ("eye.slash", "Stays out of the way", "No Dock icon, no menu bar icon unless you want one."),
    ]
    var body: some View {
        ZStack {
            Backdrop(glows: [(indigo, CGPoint(x: 0.85, y: 0.15), 600), (teal, CGPoint(x: 0.05, y: 0.85), 520), (coral, CGPoint(x: 0.5, y: 1.1), 380)])
            HStack(spacing: 70) {
                VStack(alignment: .leading, spacing: 30) {
                    Title(text: "You're in control.", size: 62)
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(points, id: \.1) { s, t, d in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: s).font(.system(size: 22)).foregroundStyle(amber).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t).font(.system(size: 21, weight: .semibold)).foregroundStyle(ink)
                                    Text(d).font(.system(size: 17)).foregroundStyle(inkSecondary)
                                }
                            }
                        }
                    }
                }
                .frame(width: 470, alignment: .leading)
                SettingsMock()
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

// MARK: - Rendering

@MainActor func render<V: View>(_ view: V, _ path: String) {
    let r = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    r.scale = 2
    guard let img = r.cgImage else { fatalError("could not render \(path)") }
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("ok \(path) \(img.width)×\(img.height)")
}

MainActor.assumeIsolated {
    render(HeroSlide(), "Promo/01-hero.png")
    render(HowSlide(), "Promo/02-how-it-works.png")
    render(ShortcutsSlide(), "Promo/03-shortcuts.png")
    render(ControlSlide(), "Promo/04-control.png")
}
