import SwiftUI

// MARK: - Content View (Router + FaceID Gate)

struct ContentView: View {
    @EnvironmentObject var biometricService: BiometricService
    @EnvironmentObject var storageService: StorageService

    var body: some View {
        Group {
            if !storageService.hasStoredProfile {
                // First-time user: go straight to input, no lock gate needed
                InputView()
            } else if biometricService.isLocked {
                LockScreen()
            } else {
                HomeView()
            }
        }
        .animation(.smooth, value: biometricService.isLocked)
        .animation(.smooth, value: storageService.hasStoredProfile)
    }
}

// MARK: - Lock Screen

struct LockScreen: View {
    @EnvironmentObject var biometricService: BiometricService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("ContextKey")
                    .font(.largeTitle.bold())

                Text("Your AI identity, protected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await biometricService.authenticate()
                }
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

            Spacer()
                .frame(height: 40)
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
