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
                    if newPhase == .background || newPhase == .inactive {
                        biometricService.lock()
                    }
                }
        }
    }
}
