import SwiftUI

// MARK: - Automation

struct AutomationPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Enter PiP when switching tabs", isOn: $model.settings.autoPiPOnTabSwitch)
            } footer: {
                Text("If a video is playing and you switch tabs, it keeps floating. When you come back to the tab, it returns to the page. You can turn this on or off per site in Sites.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Allow PiP on sites that block it", isOn: $model.settings.unblockPiP)
            } footer: {
                Text("Removes the disablePictureInPicture attribute some sites put on videos.")
                    .foregroundStyle(.secondary)
            }

            Section("Controls") {
                Picker("Skip", selection: $model.settings.seekSeconds) {
                    ForEach([5.0, 10, 15, 30], id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
                Picker("Speed step", selection: $model.settings.rateStep) {
                    ForEach([0.1, 0.25, 0.5], id: \.self) { Text(String(format: "%.2g×", $0)).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sites

struct SitesPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: Set<SiteRule.ID> = []

    private static let rates: [Double?] = [nil, 1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table($model.settings.siteRules, selection: $selection) {
                TableColumn("Site") { $rule in
                    TextField("exemplo.com", text: $rule.host)
                        .textFieldStyle(.plain)
                }
                TableColumn("Buttons") { $rule in
                    triPicker($rule.buttons)
                }
                .width(110)
                TableColumn("Auto PiP") { $rule in
                    triPicker($rule.autoPiP)
                }
                .width(110)
                TableColumn("Speed") { $rule in
                    Picker("", selection: $rule.defaultRate) {
                        ForEach(Self.rates, id: \.self) { r in
                            Text(r.map { String(format: "%g×", $0) } ?? String(localized: "Site default")).tag(r)
                        }
                    }
                    .labelsHidden()
                }
                .width(100)
            }
            Divider()
            HStack(spacing: 0) {
                Button { addRule() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                Divider().frame(height: 16)
                Button { removeSelected() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .disabled(selection.isEmpty)
                Spacer()
                Text("Rules also apply to subdomains.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }
            .buttonStyle(.borderless)
            .padding(4)
        }
        .padding()
    }

    private func triPicker(_ value: Binding<TriState>) -> some View {
        Picker("", selection: value) {
            Text("Default").tag(TriState.inherit)
            Text("On").tag(TriState.on)
            Text("Off").tag(TriState.off)
        }
        .labelsHidden()
    }

    private func addRule() {
        let rule = SiteRule(host: "")
        model.settings.siteRules.append(rule)
        selection = [rule.id]
    }

    private func removeSelected() {
        model.settings.siteRules.removeAll { selection.contains($0.id) }
        selection = []
    }
}

// MARK: - Player buttons

struct PlayersPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Add a PiP button inside video players", isOn: $model.settings.playerButtons)
                Toggle("Show a floating button over any video", isOn: $model.settings.hoverButton)
            } footer: {
                Text("The floating button appears in the corner of a video when the pointer is over it. Useful for players Floatr doesn't know.")
                    .foregroundStyle(.secondary)
            }

            Section("Players") {
                ForEach(PlayerKind.allCases) { player in
                    Toggle(player.displayName, isOn: Binding(
                        get: { model.settings.enabledPlayers.contains(player) },
                        set: { on in
                            if on { model.settings.enabledPlayers.insert(player) }
                            else { model.settings.enabledPlayers.remove(player) }
                        }))
                }
            }
            .disabled(!model.settings.playerButtons)
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutPane: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Floatr").font(.largeTitle.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Picture in Picture for any video in Safari, with keyboard shortcuts.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            VStack(spacing: 2) {
                Text("Developed by").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: "Lucas Haliax").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Capsule().fill(.quaternary))
            Divider().frame(maxWidth: 320)
            VStack(alignment: .leading, spacing: 6) {
                Label("Global shortcut → Floatr → extension → page", systemImage: "keyboard")
                Label("Picks the playing video, or the largest visible one", systemImage: "scope")
                Label("Works inside iframes and embedded players", systemImage: "rectangle.on.rectangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
