import Foundation

/// Players that get an injected PiP button. Raw values match the ids in content.js.
enum PlayerKind: String, CaseIterable, Codable, Identifiable {
    case youtube, twitch, vimeo, netflix, prime, disney, max, videojs, jwplayer, plyr, wistia
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .twitch: "Twitch"
        case .vimeo: "Vimeo"
        case .netflix: "Netflix"
        case .prime: "Prime Video"
        case .disney: "Disney+"
        case .max: "Max"
        case .videojs: "Video.js"
        case .jwplayer: "JW Player"
        case .plyr: "Plyr"
        case .wistia: "Wistia"
        }
    }
}

/// Interface language. English is the default; Portuguese is optional.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case en, pt
    var id: String { rawValue }
    /// Shown in its own language, so anyone can find theirs.
    var label: String { self == .en ? "English" : "Português" }
    /// Value for the AppleLanguages default.
    var localeCode: String { self == .en ? "en" : "pt-BR" }
}

enum TriState: String, Codable, CaseIterable, Identifiable {
    case inherit, on, off
    var id: String { rawValue }
}

/// Per-site overrides. `host` matches the site and its subdomains ("youtube.com" matches "www.youtube.com").
struct SiteRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var host: String
    var buttons: TriState = .inherit
    var autoPiP: TriState = .inherit
    /// Playback rate applied when a video starts; nil leaves the site's own rate.
    var defaultRate: Double? = nil

    func matches(_ candidate: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: .whitespaces)
        let c = candidate.lowercased()
        return !h.isEmpty && (c == h || c.hasSuffix("." + h))
    }
}

/// Everything the user can change. Stored as one JSON blob in the App Group defaults
/// so the app and the extension always read a consistent snapshot.
struct FloatrSettings: Codable, Equatable {
    var shortcuts: [PiPCommand: Shortcut] = Shortcut.defaults
    var hotkeysWhenSafariInBackground = true
    var showHUD = true
    var showMenuBarIcon = false

    var unblockPiP = true
    var autoPiPOnTabSwitch = false
    var seekSeconds: Double = 10
    var rateStep: Double = 0.25

    var playerButtons = true
    var hoverButton = false
    var enabledPlayers: Set<PlayerKind> = Set(PlayerKind.allCases)

    var siteRules: [SiteRule] = [
        SiteRule(host: "youtube.com", autoPiP: .on),
    ]

    /// Press the Floatr toolbar button via Accessibility when Safari refuses PiP without a click.
    var toolbarFallback = true
    /// Skip the direct message and always press the toolbar button (set after the spike if
    /// direct messages never carry a user gesture).
    var alwaysPressToolbar = false

    var onboardingDone = false
    var checkForUpdates = true
    var language: AppLanguage = .en

    // Tolerant decoding: settings written by an older build keep working.
    init() {}
    init(from decoder: Decoder) throws {
        let d = FloatrSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        shortcuts = v(.shortcuts, d.shortcuts)
        hotkeysWhenSafariInBackground = v(.hotkeysWhenSafariInBackground, d.hotkeysWhenSafariInBackground)
        showHUD = v(.showHUD, d.showHUD)
        showMenuBarIcon = v(.showMenuBarIcon, d.showMenuBarIcon)
        unblockPiP = v(.unblockPiP, d.unblockPiP)
        autoPiPOnTabSwitch = v(.autoPiPOnTabSwitch, d.autoPiPOnTabSwitch)
        seekSeconds = v(.seekSeconds, d.seekSeconds)
        rateStep = v(.rateStep, d.rateStep)
        playerButtons = v(.playerButtons, d.playerButtons)
        hoverButton = v(.hoverButton, d.hoverButton)
        enabledPlayers = v(.enabledPlayers, d.enabledPlayers)
        siteRules = v(.siteRules, d.siteRules)
        toolbarFallback = v(.toolbarFallback, d.toolbarFallback)
        alwaysPressToolbar = v(.alwaysPressToolbar, d.alwaysPressToolbar)
        onboardingDone = v(.onboardingDone, d.onboardingDone)
        language = v(.language, d.language)
        checkForUpdates = v(.checkForUpdates, d.checkForUpdates)
    }

    /// The subset content.js needs, as plain property-list values.
    var scriptPayload: [String: Any] {
        [
            "unblockPiP": unblockPiP,
            "autoPiP": autoPiPOnTabSwitch,
            "seekSeconds": seekSeconds,
            "rateStep": rateStep,
            "playerButtons": playerButtons,
            "hoverButton": hoverButton,
            "players": enabledPlayers.map(\.rawValue),
            "siteRules": siteRules.map { r -> [String: Any] in
                var d: [String: Any] = ["host": r.host, "buttons": r.buttons.rawValue, "autoPiP": r.autoPiP.rawValue]
                if let rate = r.defaultRate { d["defaultRate"] = rate }
                return d
            },
        ]
    }
}

/// Reads and writes `FloatrSettings` in the App Group.
enum SettingsStore {
    private static let key = "settings.v1"
    private static let lastEventKey = "lastEvent"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: Floatr.appGroupID) ?? .standard
    }

    static func load() -> FloatrSettings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(FloatrSettings.self, from: data) else { return FloatrSettings() }
        return s
    }

    static func save(_ s: FloatrSettings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: key)
        Darwin.post(DarwinName.settingsChanged)
    }

    /// Last HUD event written by the extension (the Darwin notification carries no payload).
    struct Event: Codable {
        var event: HUDEvent
        var detail: String?
        var date: Date
    }

    static func writeEvent(_ e: Event) {
        if let data = try? JSONEncoder().encode(e) { defaults.set(data, forKey: lastEventKey) }
        Darwin.post(DarwinName.event)
    }

    static func readEvent() -> Event? {
        guard let data = defaults.data(forKey: lastEventKey) else { return nil }
        return try? JSONDecoder().decode(Event.self, from: data)
    }
}
