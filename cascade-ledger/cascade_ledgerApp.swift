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
            // Categorization models
            CategorizationAttempt.self,
            CategorizationPrompt.self,
            CategorizationSession.self,
            CategorizationBatch.self,
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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
