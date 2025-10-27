//
//  ContentView.swift
//  cascade-ledger
//
//  Created by Dale Navi on 26/10/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        MainView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Account.self,
            Institution.self,
            ImportBatch.self,
            RawFile.self,
            ParsePlan.self,
            ParsePlanVersion.self,
            LedgerEntry.self,
            ParseRun.self
        ], inMemory: true)
}
