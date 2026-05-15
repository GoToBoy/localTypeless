import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let modelStatusStore: ModelStatusStore
    /// The current engine's required models. Drives the rows in the Advanced
    /// tab's Models section, so each build only shows the models it actually
    /// uses.
    let requiredModelKinds: [ModelKind]
    /// `false` on builds without an LLM polish step — hides the Prompts tab,
    /// since there's nothing for the prompt to drive.
    let polishAvailable: Bool
    let onDownload: (ModelKind) -> Void
    let firstRunState: FirstRunState
    let onReopenOnboarding: () -> Void

    var body: some View {
        TabView {
            SettingsGeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
            if polishAvailable {
                SettingsPromptsTab(settings: settings)
                    .tabItem { Label("Prompts", systemImage: "text.quote") }
            }
            SettingsAdvancedTab(settings: settings,
                                 modelStatusStore: modelStatusStore,
                                 requiredModelKinds: requiredModelKinds,
                                 polishAvailable: polishAvailable,
                                 onDownload: onDownload,
                                 firstRunState: firstRunState,
                                 onReopenOnboarding: onReopenOnboarding)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
