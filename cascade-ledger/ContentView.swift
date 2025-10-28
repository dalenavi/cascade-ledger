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
            ImportSession.self,
            RawFile.self,
            ParsePlan.self,
            ParsePlanVersion.self,
            Asset.self,
            Position.self,
            Transaction.self,
            JournalEntry.self
        ], inMemory: true)
}
