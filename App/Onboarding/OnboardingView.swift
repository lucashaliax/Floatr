import Combine
import SwiftUI

/// First-run checklist. Each step shows live status, so the user sees it turn green.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    var onDone: () -> Void

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Floatr").font(.title2.weight(.semibold))
                    Text("Three steps and the shortcut works.").foregroundStyle(.secondary)
                }
            }

            step(done: model.extensionEnabled == true,
                 title: "Turn on the extension in Safari",
                 detail: "Safari → Settings → Extensions → check Floatr and allow it on all websites.") {
                Button("Open Safari Settings", action: SafariBridge.openExtensionSettings)
            }

            step(done: nil,
                 title: "Keep the Floatr button in Safari's toolbar",
                 detail: "It's there by default. If you removed it, right-click the toolbar → Customize Toolbar.") {
                EmptyView()
            }

            step(done: model.accessibilityTrusted,
                 title: "Allow Accessibility (recommended)",
                 detail: "Some sites only allow PiP after a click. With this permission, Floatr clicks its own button for you.") {
                Button("Allow…") {
                    AccessibilityPresser.requestTrust()
                    AccessibilityPresser.openAccessibilitySettings()
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                Text("Open a video in Safari and press")
                Text(model.settings.shortcuts[.toggle]?.displayString ?? "—")
                    .font(.body.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            }
            .padding(.top, 4)

            HStack {
                Spacer()
                Button("Done") {
                    model.settings.onboardingDone = true
                    if !model.launchAtLogin { model.setLaunchAtLogin(true) }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .onAppear(perform: model.refreshExtensionState)
        .onReceive(timer) { _ in model.refreshExtensionState() }
    }

    @ViewBuilder
    private func step<A: View>(done: Bool?, title: LocalizedStringKey, detail: LocalizedStringKey,
                               @ViewBuilder action: () -> A) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done == true ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done == true ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                action().padding(.top, 2)
            }
        }
    }
}
