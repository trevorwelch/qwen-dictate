import ServiceManagement
import SwiftUI

@main
struct DictateDemoApp: App {
    @StateObject private var viewModel = DictateViewModel()

    init() {
        if !UserDefaults.standard.bool(forKey: "loginItemRegistered") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemRegistered")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DictateMenuView(viewModel: viewModel)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Dictate", id: "dictate-hud") {
            DictateHUDView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Settings {
            PreferencesView()
        }
    }

    private var menuBarIcon: String {
        if viewModel.isRecording { return "mic.fill" }
        if viewModel.isTranscribing { return "ellipsis.circle" }
        if viewModel.alwaysListening { return "ear.fill" }
        return "mic"
    }
}
