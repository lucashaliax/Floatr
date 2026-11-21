import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, automation, sites, players, about
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .automation: "Automation"
        case .sites: "Sites"
        case .players: "Player buttons"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .automation: "wand.and.stars"
        case .sites: "globe"
        case .players: "rectangle.bottomthird.inset.filled"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pane: SettingsPane? = .shortcuts
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            Group {
                switch pane ?? .shortcuts {
                case .general: GeneralPane(showOnboarding: $showOnboarding)
                case .shortcuts: ShortcutsPane()
                case .automation: AutomationPane()
                case .sites: SitesPane()
                case .players: PlayersPane()
                case .about: AboutPane()
                }
            }
            .navigationTitle(pane?.title ?? "Floatr")
        }
        .frame(minWidth: 680, minHeight: 460)
        .onAppear { if !model.settings.onboardingDone { showOnboarding = true } }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
                .environmentObject(model)
        }
    }
}

/// Green/orange banner used at the top of panes.
struct StatusBanner: View {
    let ok: Bool
    let text: LocalizedStringKey
    var action: (title: LocalizedStringKey, run: () -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .font(.title3)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let action { Button(action.title, action: action.run) }
        }
        .padding(.vertical, 2)
    }
}
