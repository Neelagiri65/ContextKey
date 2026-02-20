import SwiftUI

@main
struct ContextKeyV2App: App {
    @StateObject private var biometricService = BiometricService()
    @StateObject private var storageService = StorageService()
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(biometricService)
                .environmentObject(storageService)
                .onChange(of: scenePhase) { _, newPhase in
                    // Only lock when going to background if there's data to protect
                    if (newPhase == .background || newPhase == .inactive),
                       storageService.hasStoredProfile {
                        biometricService.lock()
                    }
                }
        }
    }
}
