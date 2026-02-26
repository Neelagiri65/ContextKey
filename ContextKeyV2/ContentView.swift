import SwiftUI

// MARK: - Content View (Router)

struct ContentView: View {
    @EnvironmentObject var biometricService: BiometricService
    @EnvironmentObject var storageService: StorageService
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView {
                    // After onboarding, unlock immediately — no double FaceID
                    biometricService.unlockWithoutAuth()
                    hasCompletedOnboarding = true
                }
            } else if biometricService.isLocked {
                LockScreen()
            } else {
                HomeView()
            }
        }
        .animation(.smooth, value: biometricService.isLocked)
        .animation(.smooth, value: hasCompletedOnboarding)
    }
}

// MARK: - Lock Screen

struct LockScreen: View {
    @EnvironmentObject var biometricService: BiometricService
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasAttemptedAutoAuth = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 8) {
                Text("ContextKey")
                    .font(.largeTitle.bold())
                Text("Your AI identity, protected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await biometricService.authenticate() }
            } label: {
                Label(unlockLabel, systemImage: unlockIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            if let error = biometricService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer().frame(height: 40)
        }
        .onAppear {
            guard !hasAttemptedAutoAuth else { return }
            hasAttemptedAutoAuth = true
            Task { await biometricService.authenticate() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && biometricService.isLocked {
                // Reset so FaceID auto-triggers when returning from background
                hasAttemptedAutoAuth = false
                Task { await biometricService.authenticate() }
            }
        }
    }

    private var unlockLabel: String {
        switch biometricService.availableBiometric {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        default: return "Unlock with Passcode"
        }
    }

    private var unlockIcon: String {
        switch biometricService.availableBiometric {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.open"
        }
    }
}
