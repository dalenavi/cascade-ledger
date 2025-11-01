//
//  ViewPreferences.swift
//  cascade-ledger
//
//  Persists user preferences for chart views
//

import Foundation
import SwiftData

@Model
final class ViewPreferences {
    var id: UUID
    var viewName: String  // "portfolio-value", "total-wealth", "positions", etc.

    @Relationship
    var account: Account?  // Preferences are per-account

    var assetOrder: [String]  // Ordered list of asset IDs
    var selectedAssets: [String]  // Which assets are selected/visible

    var createdAt: Date
    var updatedAt: Date

    init(viewName: String, account: Account? = nil) {
        self.id = UUID()
        self.viewName = viewName
        self.account = account
        self.assetOrder = []
        self.selectedAssets = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Update preferences
    func updateOrder(_ order: [String]) {
        self.assetOrder = order
        self.updatedAt = Date()
    }

    func updateSelection(_ selected: [String]) {
        self.selectedAssets = selected
        self.updatedAt = Date()
    }

    func updateBoth(order: [String], selected: [String]) {
        self.assetOrder = order
        self.selectedAssets = selected
        self.updatedAt = Date()
    }
}
