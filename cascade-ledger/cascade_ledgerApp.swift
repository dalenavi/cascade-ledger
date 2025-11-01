//
//  cascade_ledgerApp.swift
//  cascade-ledger
//
//  Created by Dale Navi on 26/10/2025.
//

import SwiftUI
import SwiftData

@main
struct cascade_ledgerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Core models
            Account.self,
            Institution.self,
            ParsePlan.self,
            ParsePlanVersion.self,
            RawFile.self,
            // New domain models
            Asset.self,
            Position.self,
            ImportSession.self,
            // Double-entry models
            Transaction.self,
            JournalEntry.self,
            // Mapping system
            Mapping.self,
            // Source provenance
            SourceRow.self,
            // Categorization models
            CategorizationAttempt.self,
            CategorizationPrompt.self,
            CategorizationSession.self,
            CategorizationBatch.self,
            // Job management
            Job.self,
            JobExecution.self,
            // Legacy models
            ImportBatch.self,
            ParseRun.self,
            // Price data
            AssetPrice.self,
            // View preferences
            ViewPreferences.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Set up persistent store remote change notification
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { notification in
            print("📡 Remote change detected, refreshing data...")
            // The SwiftUI views with @Query will automatically refresh
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
