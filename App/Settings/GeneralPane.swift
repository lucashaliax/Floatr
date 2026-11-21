import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showOnboarding: Bool

    var body: some View {
        Form {
            Section("Safari") {
                StatusBanner(ok: model.extensionEnabled == true,
                             text: model.extensionEnabled == true ? "Extension is on" : "Extension is off",
                             action: ("Open Safari Settings", SafariBridge.openExtensionSettings))
                LabeledContent("Safari toolbar button") {
                    Text("Right-click the toolbar → Customize Toolbar")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Picker("Language", selection: $model.settings.language) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.label).tag($0) }
                }
                if model.settings.language != model.launchedLanguage {
                    HStack {
                        Text("Floatr needs to relaunch to change the language.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch now") { model.relaunch() }
                    }
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin },
                                                                  set: { model.setLaunchAtLogin($0) }))
                Toggle("Show icon in the menu bar", isOn: $model.settings.showMenuBarIcon)
                Toggle("Show on-screen confirmation (HUD)", isOn: $model.settings.showHUD)
            }

            Section {
                Toggle("Click the toolbar button when Safari requires it", isOn: $model.settings.toolbarFallback)
                Toggle("Always use the toolbar button", isOn: $model.settings.alwaysPressToolbar)
                    .disabled(!model.settings.toolbarFallback)
                StatusBanner(ok: model.accessibilityTrusted,
                             text: model.accessibilityTrusted ? "Accessibility allowed" : "Accessibility not allowed",
                             action: model.accessibilityTrusted ? nil : ("Allow…", {
                                 AccessibilityPresser.requestTrust()
                                 AccessibilityPresser.openAccessibilitySettings()
                             }))
            } header: {
                Text("When Safari requires a click")
            } footer: {
                Text("Some sites only allow PiP after a click. In that case Floatr presses its own button in Safari's toolbar for you. This needs the Accessibility permission, and the button has to be visible in the toolbar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Show introduction") { showOnboarding = true }
                    Spacer()
                    Button("Quit Floatr", role: .destructive) { NSApp.terminate(nil) }
                }
            } footer: {
                Text("Floatr runs without a Dock icon. To come back to this window, open Floatr again from Spotlight or Launchpad.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
