import SwiftUI

// MARK: - Onboarding View
/// Three-page onboarding experience for first-time users
/// Explains AI categorization, swipe review, and privacy

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Background gradient
            SemanticColor.primary.gradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    OnboardingPage1()
                        .tag(0)

                    OnboardingPage2()
                        .tag(1)

                    OnboardingPage3()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: currentPage)

                // Bottom section
                VStack(spacing: 24) {
                    // Page indicators
                    PageIndicator(currentPage: currentPage, totalPages: 3)

                    // Button
                    if currentPage == 2 {
                        getStartedButton
                    } else {
                        nextButton
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }

    private var nextButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentPage += 1
            }
            HapticManager.shared.lightTap()
        }) {
            Text("Next")
                .font(.headline)
                .foregroundColor(SemanticColor.primary.solidColor)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.white)
                .cornerRadius(14)
        }
    }

    private var getStartedButton: some View {
        Button(action: {
            completeOnboarding()
        }) {
            Text("Get Started")
                .font(.headline)
                .foregroundColor(SemanticColor.primary.solidColor)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.white)
                .cornerRadius(14)
        }
    }

    private func completeOnboarding() {
        HapticManager.shared.success()
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        withAnimation(.easeOut(duration: 0.5)) {
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Page Indicator

struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? .white : .white.opacity(0.4))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }
}

// MARK: - Page 1: Smart Organization

struct OnboardingPage1: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 160, height: 160)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 70))
                    .foregroundColor(.white)
                    .symbolEffect(.bounce, options: .repeating.speed(0.5), value: isAnimating)
            }

            VStack(spacing: 16) {
                Text("Smart Organization")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("AI automatically categorizes your screenshots into 65+ categories like Messages, Receipts, Social Media, and more.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Category preview
            CategoryPreviewRow()
                .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}

struct CategoryPreviewRow: View {
    let categories = [
        ("message.fill", "Messages"),
        ("receipt.fill", "Receipts"),
        ("camera.fill", "Instagram"),
        ("doc.text.fill", "Documents")
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(categories, id: \.1) { icon, name in
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(.white.opacity(0.2), in: Circle())

                    Text(name)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }
}

// MARK: - Page 2: Quick Review

struct OnboardingPage2: View {
    @State private var isAnimating = false
    @State private var cardOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Animated swipe demo
            ZStack {
                // Background cards
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.1))
                    .frame(width: 180, height: 220)
                    .offset(x: 15, y: 10)
                    .rotationEffect(.degrees(5))

                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.15))
                    .frame(width: 180, height: 220)
                    .offset(x: -15, y: 10)
                    .rotationEffect(.degrees(-5))

                // Main card with swipe animation
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.25))
                        .frame(width: 180, height: 220)

                    VStack(spacing: 12) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.8))

                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                }
                .offset(x: cardOffset)
                .rotationEffect(.degrees(Double(cardOffset / 20)))
            }

            VStack(spacing: 16) {
                Text("Quick Review")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Swipe left to delete screenshots you don't need, swipe right to keep them. It's that simple!")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Swipe hints
            HStack(spacing: 60) {
                SwipeHintLabel(icon: "trash.fill", text: "Delete", color: .red)
                SwipeHintLabel(icon: "checkmark", text: "Keep", color: .green)
            }

            Spacer()
            Spacer()
        }
        .onAppear {
            if !reduceMotion {
                startSwipeAnimation()
            }
        }
    }

    private func startSwipeAnimation() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            cardOffset = 40
        }
    }
}

struct SwipeHintLabel: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(color)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Page 3: Privacy First

struct OnboardingPage3: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 160, height: 160)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.white)
                    .symbolEffect(.pulse, options: .repeating.speed(0.3), value: isAnimating)
            }

            VStack(spacing: 16) {
                Text("Your Privacy First")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("All processing happens on your device. Your screenshots never leave your phone and are never uploaded to any server.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Privacy features
            VStack(spacing: 16) {
                PrivacyFeatureRow(icon: "iphone", text: "On-device AI processing")
                PrivacyFeatureRow(icon: "xmark.icloud.fill", text: "No cloud uploads")
                PrivacyFeatureRow(icon: "eye.slash.fill", text: "Your data stays private")
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .onAppear {
            if !reduceMotion {
                isAnimating = true
            }
        }
    }
}

struct PrivacyFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 40)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Onboarding Keys

struct OnboardingKeys {
    static let hasSeenOnboarding = "hasSeenOnboarding"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenOnboarding) }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: hasSeenOnboarding)
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
