import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let modelStatusStore: ModelStatusStore
    let onDownloadAsr: () -> Void
    let onDownloadPolish: () -> Void
    let firstRunState: FirstRunState
    let onReopenOnboarding: () -> Void

    var body: some View {
        TabView {
            SettingsGeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
            SettingsPromptsTab(settings: settings)
                .tabItem { Label("Prompts", systemImage: "text.quote") }
            SettingsAdvancedTab(settings: settings,
                                 modelStatusStore: modelStatusStore,
                                 onDownloadAsr: onDownloadAsr,
                                 onDownloadPolish: onDownloadPolish,
                                 firstRunState: firstRunState,
                                 onReopenOnboarding: onReopenOnboarding)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
