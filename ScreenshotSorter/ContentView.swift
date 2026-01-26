import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CollectionsViewModel()
    @State private var showSplash = true
    @State private var hasCompletedOnboarding = OnboardingKeys.hasCompletedOnboarding

    var body: some View {
        ZStack {
            // Main app content
            NavigationStack {
                if !viewModel.hasPhotoAccess {
                    PhotoAccessView(viewModel: viewModel)
                } else {
                    CollectionsView(viewModel: viewModel)
                }
            }

            // Onboarding overlay (first time only)
            if !hasCompletedOnboarding && !showSplash {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
                    .zIndex(2)
            }

            // Splash screen overlay
            if showSplash {
                SplashScreen()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
                // Check for new screenshots after splash (only if onboarding is done)
                if viewModel.hasPhotoAccess && hasCompletedOnboarding {
                    viewModel.checkForNewScreenshots()
                }
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed && viewModel.hasPhotoAccess {
                viewModel.checkForNewScreenshots()
            }
        }
    }
}

// MARK: - Splash Screen

struct SplashScreen: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SemanticColor.primary.gradient
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .symbolEffect(.bounce, value: isAnimating)

                Text("What the Screen?")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)

                Text("Loading your screenshots...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Processing screenshots...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Photo Access View

struct PhotoAccessView: View {
    @ObservedObject var viewModel: CollectionsViewModel
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 80))
                .foregroundStyle(SemanticColor.primary.gradient)
                .symbolEffect(.pulse, options: .repeating.speed(0.5), value: isAnimating)

            VStack(spacing: 12) {
                Text("Welcome to")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text("What the Screen?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(SemanticColor.primary.gradient)

                Text("We need access to your photo library to organize your screenshots into smart collections.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

            Button(action: {
                HapticManager.shared.lightTap()
                viewModel.requestPhotoAccess()
            }) {
                Text("Grant Access")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(SemanticColor.primary.gradient)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .accessibilityLabel("Grant photo library access")
            .accessibilityHint("Double-tap to allow the app to access your photo library")
        }
        .padding()
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}
