import SwiftUI

@main
struct ScreenshotSorterApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Background task handlers must be registered before launch completes
        BackgroundAnalysisManager.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .tint(Palette.brand)
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.handleScenePhase(newPhase)
        }
    }
}
