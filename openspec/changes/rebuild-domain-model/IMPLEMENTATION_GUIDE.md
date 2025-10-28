# Implementation Guide for Domain Model Rebuild

## Overview
This is a complete domain model rewrite (Plan B). We're not preserving data or backward compatibility. Users will reimport their data after the upgrade.

## Critical Path

### Day 1: Foundation
**Morning: Setup**
```bash
git checkout -b domain-rewrite-v2
rm cascade-ledger/Models/LedgerEntry.swift
# Create REWRITE_LOG.md documenting decisions
```

**Afternoon: Core Models**
Start with these files in order:
1. `Models/Asset.swift` - Simple value type
2. `Models/Position.swift` - Depends on Asset
3. `Models/ImportSession.swift` - Replaces ImportBatch

### Day 2: Services
Build service layer with dependency injection:
1. `Services/AssetRegistry.swift` - Singleton with caching
2. `Services/PositionCalculator.swift` - Actor for async
3. `Services/ImportPipeline.swift` - Protocol definition

### Day 3-4: Import Pipeline
The complex part - institution-specific importers:
1. `ParseEngine/InstitutionDetector.swift`
2. `ParseEngine/SettlementDetector.swift`
3. `ParseEngine/FidelityImporter.swift`
4. Update `TransactionBuilder.swift` to use AssetRegistry

### Day 5: ParsePlan Reform
Fix the relationship model:
1. Create `Models/Institution.swift`
2. Update `ParsePlan.swift` relationships
3. Migrate existing plans to institutions

### Day 6-7: UI Updates
Update views to use new models:
1. `Views/PositionCenterView.swift` - New
2. `Views/ImportSessionView.swift` - New
3. Update existing transaction views

## Code Templates

### Asset Model Template
```swift
import Foundation
import SwiftData

@Model
final class Asset {
    let id: UUID
    let symbol: String  // Canonical symbol like "SPY"
    var name: String
    var assetClass: AssetClass
    var isCashEquivalent: Bool = false

    // Relationships
    @Relationship(inverse: \Position.asset)
    var positions: [Position]?

    @Relationship(inverse: \JournalEntry.asset)
    var journalEntries: [JournalEntry]?

    // Data source configuration
    var priceFeed: PriceFeed?

    init(symbol: String, name: String? = nil) {
        self.id = UUID()
        self.symbol = symbol.uppercased()
        self.name = name ?? symbol
        self.assetClass = AssetClass.infer(from: symbol)
        self.positions = []
        self.journalEntries = []
    }
}

enum AssetClass: String, Codable, CaseIterable {
    case stock = "stock"
    case etf = "etf"
    case mutualFund = "mutual_fund"
    case crypto = "crypto"
    case cash = "cash"
    case commodity = "commodity"

    static func infer(from symbol: String) -> AssetClass {
        // Simple heuristics
        if symbol == "USD" || symbol.hasSuffix("XX") { return .cash }
        if ["BTC", "ETH", "SOL"].contains(symbol) { return .crypto }
        if symbol.hasSuffix("X") { return .mutualFund }
        return .stock  // Default
    }
}

enum PriceFeed: Codable {
    case yahoo(symbol: String)
    case coinGecko(id: String)
    case manual
    case none
}
```

### AssetRegistry Template
```swift
import Foundation
import SwiftData

@MainActor
class AssetRegistry: ObservableObject {
    static let shared = AssetRegistry()

    private var canonicalCache: [String: Asset] = [:]
    private var institutionMappings: [String: [String: String]] = [:]
    private let modelContext: ModelContext

    private init() {
        // Initialize with model context
        self.modelContext = // Get from container
        loadCache()
    }

    func findOrCreate(
        symbol: String,
        name: String? = nil,
        institution: String? = nil
    ) -> Asset {
        let normalized = symbol.uppercased().trimmingCharacters(in: .whitespaces)

        // Check cache first for performance
        if let cached = canonicalCache[normalized] {
            return cached
        }

        // Check database
        let descriptor = FetchDescriptor<Asset>(
            predicate: #Predicate { $0.symbol == normalized }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            canonicalCache[normalized] = existing
            return existing
        }

        // Create new asset
        let asset = Asset(symbol: normalized, name: name)
        modelContext.insert(asset)
        canonicalCache[normalized] = asset

        // Save immediately for consistency
        try? modelContext.save()

        return asset
    }

    private func loadCache() {
        let descriptor = FetchDescriptor<Asset>()
        guard let assets = try? modelContext.fetch(descriptor) else { return }

        for asset in assets {
            canonicalCache[asset.symbol] = asset
        }
    }
}
```

### PositionCalculator Template
```swift
import Foundation

actor PositionCalculator {
    private var queue: Set<PositionTask> = []
    private var isProcessing = false

    struct PositionTask: Hashable {
        let accountId: UUID
        let priority: Priority

        enum Priority: Int {
            case low = 0
            case normal = 1
            case high = 2
        }
    }

    func scheduleRecalculation(for account: Account, priority: PositionTask.Priority = .normal) async {
        let task = PositionTask(accountId: account.id, priority: priority)
        queue.insert(task)

        if !isProcessing {
            await processQueue()
        }
    }

    private func processQueue() async {
        isProcessing = true
        defer { isProcessing = false }

        // Sort by priority
        let sorted = queue.sorted { $0.priority.rawValue > $1.priority.rawValue }
        queue.removeAll()

        for task in sorted {
            await recalculatePosition(for: task.accountId)
        }
    }

    private func recalculatePosition(for accountId: UUID) async {
        // 1. Fetch account and transactions
        // 2. Group by asset
        // 3. Calculate quantities
        // 4. Update or create Position records
        // 5. Remove zero positions

        print("Recalculating positions for account \(accountId)")

        // Implementation here
        try? await Task.sleep(nanoseconds: 100_000_000) // Simulate work
    }
}
```

### Test Templates

```swift
// AssetTests.swift
import XCTest
@testable import CascadeLedger

final class AssetTests: XCTestCase {

    func test_symbolNormalization() {
        let asset1 = Asset(symbol: "spy")
        let asset2 = Asset(symbol: "SPY")
        let asset3 = Asset(symbol: " SPY ")

        XCTAssertEqual(asset1.symbol, "SPY")
        XCTAssertEqual(asset2.symbol, "SPY")
        XCTAssertEqual(asset3.symbol, "SPY")
    }

    func test_assetClassInference() {
        XCTAssertEqual(Asset(symbol: "BTC").assetClass, .crypto)
        XCTAssertEqual(Asset(symbol: "SPAXX").assetClass, .cash)
        XCTAssertEqual(Asset(symbol: "VOO").assetClass, .stock)
    }

    func test_cashEquivalentFlag() {
        let spaxx = Asset(symbol: "SPAXX")
        spaxx.isCashEquivalent = true
        XCTAssertTrue(spaxx.isCashEquivalent)
    }
}

// PositionTests.swift
final class PositionTests: XCTestCase {

    func test_positionCalculation() {
        let account = TestHelpers.createAccount()
        let asset = Asset(symbol: "SPY")
        let position = Position(account: account, asset: asset)

        let transactions = [
            TestHelpers.createBuyTransaction(asset: asset, quantity: 100),
            TestHelpers.createBuyTransaction(asset: asset, quantity: 50),
            TestHelpers.createSellTransaction(asset: asset, quantity: 30)
        ]

        position.recalculate(from: transactions)

        XCTAssertEqual(position.quantity, 120) // 100 + 50 - 30
    }

    func test_zeroPositionRemoval() {
        // Test that positions with 0 quantity are deleted
    }
}

// ImportPipelineTests.swift
final class ImportPipelineTests: XCTestCase {

    func test_fidelitySettlementGrouping() async {
        let csv = TestFixtures.fidelityCSV
        let pipeline = FidelityImporter()

        let groups = try await pipeline.parseAndTransform(csv)

        // Verify settlement rows group with main transactions
        XCTAssertEqual(groups[0].rows.count, 2) // Main + settlement
        XCTAssertTrue(groups[0].rows[0].contains("YOU BOUGHT"))
        XCTAssertTrue(groups[0].rows[1]["Action"]?.isEmpty ?? false)
    }

    func test_endToEndImport() async {
        // Full pipeline test
        let csv = TestFixtures.fidelityCSV
        let account = TestHelpers.createAccount()
        let pipeline = ImportPipeline()

        let session = try await pipeline.import(csv, into: account)

        XCTAssertGreaterThan(session.transactions.count, 0)
        XCTAssertNotNil(session.dataStartDate)
        XCTAssertNotNil(session.dataEndDate)
    }
}
```

## Testing Strategy

### Unit Test Coverage Goals
- Domain models: 90%+ coverage
- Services: 80%+ coverage
- Import pipeline: 70%+ coverage
- UI: Manual testing only

### Test Data Fixtures
Create `Tests/Fixtures/` directory with:
- `fidelity_sample.csv` - Real Fidelity format
- `coinbase_sample.csv` - Real Coinbase format
- `edge_cases.csv` - Problematic data

### Property-Based Tests
```swift
func test_positionConservation() {
    // Property: sum of transaction quantities = position quantity
    check(forAll: Gen.arrayOf(transactionGen)) { transactions in
        let calculated = Position.calculate(from: transactions)
        let summed = transactions.reduce(0) { $0 + $1.netQuantity }
        return abs(calculated.quantity - summed) < 0.001
    }
}
```

## Common Pitfalls to Avoid

### 1. Asset Identity
❌ **Wrong**: Creating new assets for each import
✅ **Right**: Always use AssetRegistry.findOrCreate()

### 2. Position Updates
❌ **Wrong**: Recalculating on every query
✅ **Right**: Cache positions, update async

### 3. Settlement Rows
❌ **Wrong**: Generic detection logic
✅ **Right**: Institution-specific detectors

### 4. Parse Plans
❌ **Wrong**: Accounts owning plans
✅ **Right**: Institutions own plans, accounts select

### 5. Testing
❌ **Wrong**: Testing SwiftUI layouts
✅ **Right**: Testing domain logic heavily

## Validation Checkpoints

### After Each Day
Run these checks to ensure you're on track:

**Day 1 Checkpoint:**
```bash
swift test --filter "AssetTests|PositionTests|ImportSessionTests"
# Should see 10+ tests passing
```

**Day 3 Checkpoint:**
```bash
# Test import with sample CSV
swift run cascade-ledger import --dry-run --file Tests/Fixtures/fidelity_sample.csv
# Should parse without errors
```

**Day 5 Checkpoint:**
```bash
# All domain tests should pass
swift test --filter "Domain"
# 50+ tests passing
```

**Day 7 Checkpoint:**
```bash
# Full integration test
swift test
# 100+ tests passing
```

## Performance Targets

These must be met before shipping:

- Asset lookup: < 1ms (via cache)
- Position calculation: < 100ms per 1000 transactions
- Import speed: < 5 seconds for 1000 rows
- UI responsiveness: 60fps during import
- Memory: < 200MB for typical usage

## Migration Checklist

Before deploying:

- [ ] All tests passing
- [ ] Performance targets met
- [ ] Manual testing of all workflows
- [ ] Parse plans exported as backup
- [ ] Documentation updated
- [ ] Rollback procedure tested

## Questions That May Arise

**Q: Why no backward compatibility?**
A: The old model has fundamental flaws. Clean break is simpler and safer.

**Q: What about existing user data?**
A: Users reimport CSVs. Parse plans are preserved as JSON.

**Q: Why Actor for PositionCalculator?**
A: Thread-safe async processing without locks.

**Q: Why separate Asset from Position?**
A: Asset is identity, Position is state. Different concerns.

**Q: Can we merge FBTC and BTC?**
A: No. They're different assets with different prices. User can view "Bitcoin exposure" in analytics layer later.

## Emergency Rollback

If things go wrong:
```bash
git checkout main
git branch -D domain-rewrite-v2
# Restore from backup/previous-release
```

## Success Criteria

You've succeeded when:
1. Can import Fidelity CSV without errors
2. Positions calculate correctly
3. Multi-account aggregation works
4. All tests pass
5. Performance meets targets
6. UI feels responsive

Good luck! This is a big refactor but the architecture will be much cleaner.