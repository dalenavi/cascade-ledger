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
            ImportBatch.self,
            RawFile.self,
            ParsePlan.self,
            ParsePlanVersion.self,
            LedgerEntry.self,
            ParseRun.self,
            // Categorization models
            CategorizationAttempt.self,
            CategorizationPrompt.self,
            // Price data
            AssetPrice.self,
            // View preferences
            ViewPreferences.self,
            // Keep Item for now (can remove later)
            Item.self
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
