import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSplash = true
    @State private var hasCompletedOnboarding = OnboardingKeys.hasCompletedOnboarding
    @State private var path = NavigationPath()

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                if model.hasPhotoAccess {
                    CollectionsView(path: $path)
                } else {
                    PhotoAccessPromptView {
                        model.requestPhotoAccess()
                    }
                }
            }

            if !hasCompletedOnboarding && !showSplash {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .task {
            async let started: Void = model.start()
            // Keep the splash just long enough for its animation, then leave as soon as data is ready
            try? await Task.sleep(nanoseconds: 650_000_000)
            var waited = 0
            while model.hasPhotoAccess && !model.isLibraryLoaded && waited < 15 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            Motion.perform(Motion.gentle, reduceMotion: reduceMotion) {
                showSplash = false
            }
            await started
        }
    }
}
