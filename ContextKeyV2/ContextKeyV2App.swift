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

        let schema = Schema([
            RawExtraction.self,
            ImportedConversation.self,
            CanonicalEntity.self,
            BeliefScore.self,
            ContextCard.self,
            CitationReference.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        // Tier 1 — try normal init (handles lightweight migrations)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("[ModelContainer] Tier 1 failed: \(error). Deleting store and retrying.")
            // Tier 2 — store is corrupt/incompatible, delete and recreate fresh
            do {
                let storeURL = config.url
                let storePath = storeURL.path()
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(atPath: storePath + suffix)
                }
                modelContainer = try ModelContainer(for: schema, configurations: [config])
                UserDefaults.standard.set(true, forKey: "storeWasReset")
            } catch {
                fatalError("Unrecoverable store failure: \(error)")
            }
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
