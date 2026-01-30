import SwiftUI

@main
struct ScreenshotSorterApp: App {
    @StateObject private var viewModel = CollectionsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Save snapshot when app goes to background
                viewModel.saveStateSnapshot()
            }
        }
    }
}
