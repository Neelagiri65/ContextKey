import SwiftUI

@main
struct ContextKeyV2App: App {
    @StateObject private var biometricService = BiometricService()
    @StateObject private var storageService = StorageService()
    @Environment(\.scenePhase) var scenePhase

    init() {
        #if DEBUG
        // Enable V2 enhanced extraction in simulator for testing
        UserDefaults.standard.set(true, forKey: "v2EnhancedExtraction")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(biometricService)
                .environmentObject(storageService)
                .onChange(of: scenePhase) { _, newPhase in
                    // Only lock when going to background if there's data to protect
                    if newPhase == .background,
                       storageService.hasStoredProfile {
                        biometricService.lock()
                    }
                }
        }
    }
}
