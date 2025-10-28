//
//  AssetRegistry.swift
//  cascade-ledger
//
//  Singleton service for managing asset identity and deduplication
//

import Foundation
import SwiftData

@MainActor
class AssetRegistry {
    static let shared = AssetRegistry()

    // Two-level cache
    private var canonicalCache: [String: Asset] = [:]  // symbol -> Asset
    private var institutionMappings: [String: [String: String]] = [:]  // institution -> [alias -> canonical]

    private var modelContext: ModelContext?

    private init() {}

    /// Initialize or update the registry with a ModelContext
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadCache()
    }

    /// Find or create an asset, with optional institution-specific mapping
    func findOrCreate(
        symbol: String,
        name: String? = nil,
        institution: String? = nil
    ) -> Asset {
        guard let modelContext = modelContext else {
            fatalError("AssetRegistry not configured with ModelContext")
        }

        // Normalize symbol
        let normalized = normalizeSymbol(symbol)

        // Check institution mapping first
        if let institution = institution,
           let mapping = institutionMappings[institution],
           let canonical = mapping[normalized] {
            // Use canonical symbol from institution mapping
            if let cached = canonicalCache[canonical] {
                return cached
            }
        }

        // Check canonical cache
        if let cached = canonicalCache[normalized] {
            return cached
        }

        // Query database
        let descriptor = FetchDescriptor<Asset>(
            predicate: #Predicate<Asset> { asset in
                asset.symbol == normalized
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            canonicalCache[normalized] = existing
            return existing
        }

        // Create new asset
        let asset = Asset(symbol: normalized, name: name)
        modelContext.insert(asset)
        canonicalCache[normalized] = asset

        return asset
    }

    /// Register an institution-specific symbol mapping
    func registerMapping(institution: String, alias: String, canonical: String) {
        let normalizedAlias = normalizeSymbol(alias)
        let normalizedCanonical = normalizeSymbol(canonical)

        if institutionMappings[institution] == nil {
            institutionMappings[institution] = [:]
        }
        institutionMappings[institution]?[normalizedAlias] = normalizedCanonical
    }

    /// Normalize symbol: uppercase, trimmed, handle special cases
    private func normalizeSymbol(_ symbol: String) -> String {
        symbol
            .uppercased()
            .trimmingCharacters(in: .whitespaces)
    }

    /// Load all assets into cache from database
    private func loadCache() {
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<Asset>()

        guard let assets = try? modelContext.fetch(descriptor) else {
            return
        }

        for asset in assets {
            canonicalCache[asset.symbol] = asset
        }
    }

    /// Clear cache (useful for testing)
    func clearCache() {
        canonicalCache.removeAll()
    }

    /// Get all cached assets
    var allAssets: [Asset] {
        Array(canonicalCache.values)
    }
}
