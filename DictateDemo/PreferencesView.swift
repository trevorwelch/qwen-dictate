import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @AppStorage("autoInject") private var autoInject = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Auto-paste after transcription", isOn: $autoInject)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Hotkey") {
                Text("Double-tap Right Option to start. Tap Right Option again to stop and paste.")
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                Text("This app requires Accessibility and Input Monitoring permissions.")
                    .foregroundStyle(.secondary)
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Open Input Monitoring Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 350)
    }
}
