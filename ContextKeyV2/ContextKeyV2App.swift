import SwiftUI
import SwiftData

@main
struct ContextKeyV2App: App {
    @StateObject private var biometricService = BiometricService()
    @StateObject private var storageService = StorageService()
    @Environment(\.scenePhase) var scenePhase

    let modelContainer: ModelContainer

    init() {
        #if DEBUG
        // Enable V2 enhanced extraction in simulator for testing
        UserDefaults.standard.set(true, forKey: "v2EnhancedExtraction")
        #endif

        do {
            let schema = Schema([
                RawExtraction.self,
                ImportedConversation.self,
                CanonicalEntity.self,
                BeliefScore.self,
                ContextCard.self,
                CitationReference.self
            ])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(biometricService)
                .environmentObject(storageService)
                .modelContainer(modelContainer)
                .onChange(of: scenePhase) { _, newPhase in
                    // Only lock when going to background if there's data to protect
                    if newPhase == .background,
                       storageService.hasStoredProfile {
                        biometricService.lock()
                    }
                    // Decay pass on foreground if >24h since last run
                    if newPhase == .active {
                        let context = modelContainer.mainContext
                        do {
                            try BeliefEngine.decayPassIfNeeded(modelContext: context)
                        } catch {
                            print("[BeliefEngine] Decay pass failed: \(error)")
                        }
                    }
                }
        }
    }
}
