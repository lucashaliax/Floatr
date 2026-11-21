import SwiftUI

struct ShortcutsPane: View {
    @EnvironmentObject private var model: AppModel

    private let pipGroup: [PiPCommand] = [.toggle, .focusTab, .nextVideo]
    private let controlGroup: [PiPCommand] = [.playPause, .seekBack, .seekForward, .slower, .faster, .mute]

    var body: some View {
        Form {
            Section {
                StatusBanner(ok: model.extensionEnabled == true,
                             text: model.extensionEnabled == true
                                ? "Extension is on in Safari"
                                : "Turn on the Floatr extension in Safari Settings",
                             action: model.extensionEnabled == true ? nil : ("Open Safari Settings", SafariBridge.openExtensionSettings))
            }

            Section("Picture in Picture") {
                ForEach(pipGroup, id: \.self, content: row)
            }

            Section {
                ForEach(controlGroup, id: \.self, content: row)
            } header: {
                Text("Floating video controls")
            } footer: {
                Text("They work in any app while the video is in PiP.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Shortcuts work while Safari is in the background", isOn: $model.settings.hotkeysWhenSafariInBackground)
                Toggle("Show on-screen confirmation (HUD)", isOn: $model.settings.showHUD)
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore defaults") { model.settings.shortcuts = Shortcut.defaults }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ cmd: PiPCommand) -> some View {
        LabeledContent {
            ShortcutRecorder(shortcut: binding(cmd), conflict: conflict(cmd))
        } label: {
            Label(cmd.title, systemImage: symbol(for: cmd))
        }
    }

    private func symbol(for cmd: PiPCommand) -> String {
        switch cmd {
        case .seekBack: "gobackward.\(Int(model.settings.seekSeconds))"
        case .seekForward: "goforward.\(Int(model.settings.seekSeconds))"
        default: cmd.symbol
        }
    }

    private func binding(_ cmd: PiPCommand) -> Binding<Shortcut?> {
        Binding(get: { model.settings.shortcuts[cmd] },
                set: { model.settings.shortcuts[cmd] = $0 })
    }

    private func conflict(_ cmd: PiPCommand) -> LocalizedStringKey? {
        if model.duplicateShortcuts.contains(cmd) { return "Same shortcut as another action" }
        if model.takenShortcuts.contains(cmd) { return "Another app already uses this shortcut" }
        return nil
    }
}
