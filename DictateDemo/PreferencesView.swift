import SwiftUI

struct PreferencesView: View {
    @AppStorage("autoInject") private var autoInject = true

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Auto-paste after transcription", isOn: $autoInject)
            }

            Section("Hotkey") {
                Text("Ctrl + Option + D (hold to record)")
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
