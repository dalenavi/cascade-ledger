# Domain Model Rebuild Design

## Architecture Philosophy

### Three Layers of Truth
```
Source Layer    →    Domain Layer    →    View Layer
(what came in)      (canonical model)     (optimized display)

ImportSession        Transaction            PortfolioSummary
RawCSV              Position               AggregatePosition
ParsedRows          Asset                  ChartData
```

## Core Design Decisions

### Asset Identity Management

**Decision**: Each unique symbol is a distinct Asset. No automatic aliasing.

```swift
// FBTC and BTC are different assets
Asset(symbol: "FBTC", name: "Fidelity Wise Origin Bitcoin Fund")  // ~$90/share
Asset(symbol: "BTC", name: "Bitcoin")  // ~$90,000/coin
```

**Rationale**:
- Different prices, different tax treatment, different data sources
- Aliasing belongs in analytics layer, not core domain
- Prevents calculation errors from conflation

**Implementation**:
```swift
class AssetRegistry {
    // Two-level cache for performance
    private var canonicalCache: [String: Asset] = [:]
    private var institutionMappings: [String: [String: Asset]] = [:]

    func resolveSymbol(_ symbol: String, institution: String) -> Asset {
        // 1. Check institution-specific mapping
        if let mapped = institutionMappings[institution]?[symbol] {
            return mapped
        }
        // 2. Check canonical cache
        if let canonical = canonicalCache[symbol.uppercased()] {
            return canonical
        }
        // 3. Create new asset
        return createAsset(symbol: symbol)
    }
}
```

### Position as Materialized View

**Decision**: Positions are cached calculations, not computed on-demand.

**Rationale**:
- Computing from thousands of transactions is slow
- Positions change only when transactions added
- Enables instant multi-account aggregation

**Trade-offs**:
- Storage: ~100 bytes per position (acceptable)
- Consistency: Eventually consistent during recalculation
- Complexity: Need PositionCalculator service

**Implementation**:
```swift
actor PositionCalculator {
    private var queue: Set<PositionTask> = []

    func scheduleRecalculation(for account: Account) async {
        queue.insert(PositionTask(account: account))
        if !isProcessing {
            await processQueue()
        }
    }

    private func processQueue() async {
        // Batch process for efficiency
        // Prevents recalculation storms
    }
}
```

### ParsePlan Ownership

**Decision**: ParsePlans belong to Institutions, not Accounts.

**Current Problem**:
```
Account → ParsePlan → Version  // Confusing
```

**New Design**:
```
Institution → ParsePlan → Version
     ↑
  Account (selects plan for import)
```

**Benefits**:
- Fidelity plans work for all Fidelity accounts
- Share improvements across users
- Clear upgrade path for plans

### Import Pipeline Stages

**Decision**: Explicit pipeline stages instead of monolithic transform.

```swift
protocol ImportPipeline {
    // Stage 1: Detect source
    func detectInstitution(csv: Data) -> Institution

    // Stage 2: Parse structure
    func parseCSV(data: Data, dialect: CSVDialect) -> CSVData

    // Stage 3: Transform to canonical
    func transform(csv: CSVData, plan: ParsePlan) -> [TransactionGroup]

    // Stage 4: Create domain models
    func materialize(groups: [TransactionGroup]) -> [Transaction]

    // Stage 5: Update derived data
    func updatePositions(transactions: [Transaction]) async
}
```

**Benefits**:
- Testable stages
- Clear error boundaries
- Pluggable implementations

### Settlement Row Handling

**Decision**: Per-institution settlement detectors.

**Problem**: Generic detection is fragile:
```swift
// Current brittle approach
let isSettlement = type.isEmpty && symbol.isEmpty && quantity == 0
```

**Solution**: Explicit institution patterns:
```swift
protocol SettlementDetector {
    func isSettlement(row: ParsedRow) -> Bool
    func shouldGroup(with previous: ParsedRow) -> Bool
}

class FidelitySettlementDetector: SettlementDetector {
    func isSettlement(row: ParsedRow) -> Bool {
        // Fidelity-specific logic
        return row["Action"].isEmpty &&
               row["Symbol"].isEmpty &&
               row["Quantity"] == "0"
    }

    func shouldGroup(with previous: ParsedRow) -> Bool {
        // Settlement follows main transaction on same date
        return row.date == previous.date &&
               isSettlement(row) &&
               !isSettlement(previous)
    }
}
```

### Agent Integration Improvements

**Decision**: Structured prompts with validation.

**Current Problem**: Vague prompts produce inconsistent results
**Solution**: Type-safe prompt building with expected schema

```swift
actor ParseAssistant {
    func suggestParsePlan(sample: CSVSample) async throws -> ParsePlanDefinition {
        let prompt = StructuredPrompt {
            SystemMessage("""
                You are analyzing CSV financial data.
                Respond with valid JSON matching the schema.
                """)

            UserMessage {
                Text("Analyze this CSV sample:")
                Code(sample.rows, language: "csv")

                Text("Identify:")
                List {
                    "Date column and format"
                    "Amount column and sign convention"
                    "Symbol/ticker column"
                    "Transaction type/action column"
                    "Settlement rows (if present)"
                }
            }

            Schema(ParsePlanDefinition.self)
        }

        let response = try await claude.complete(prompt)
        return try validateAndParse(response)
    }
}
```

## Data Migration Strategy

Since we're not preserving data:

1. **Export Critical Configuration**
   ```swift
   // Save parse plans as JSON
   let plans = try exportParsePlans()
   save(plans, to: "parse_plans_backup.json")
   ```

2. **Document Custom Mappings**
   ```swift
   // Extract any user customizations
   let customMappings = extractCustomMappings()
   document(customMappings)
   ```

3. **Clean Slate Import**
   ```swift
   // Users reimport their CSVs
   // New system creates clean data
   ```

## Testing Strategy

### Domain Model Tests (Heavy)
```swift
class AssetTests: XCTestCase {
    func test_symbol_normalization() { }
    func test_equality_semantics() { }
    func test_cash_equivalent_flag() { }
}

class PositionTests: XCTestCase {
    func test_calculation_accuracy() { }
    func test_lot_tracking_stub() { }
    func test_zero_position_removal() { }
}

class TransactionTests: XCTestCase {
    func test_must_balance() { }
    func test_rounding_tolerance() { }
    func test_journal_entry_signs() { }
}
```

### Service Integration Tests
```swift
class ImportPipelineTests: XCTestCase {
    func test_fidelity_end_to_end() { }
    func test_settlement_row_grouping() { }
    func test_duplicate_detection() { }
}
```

### Property-Based Tests
```swift
func test_position_conservation() {
    // Property: sum(transactions) == final position
    check(forAll: Gen.transactions()) { txs in
        let calculated = Position.calculate(from: txs)
        let summed = txs.sum(\.netQuantity)
        return calculated.quantity == summed
    }
}
```

### What NOT to Test
- UI layout code
- SwiftUI view updates
- Simple getters/setters
- Third-party libraries

## Performance Considerations

### Caching Strategy
- **Assets**: Full in-memory cache (~1000 records max)
- **Positions**: Database-backed, cached per session
- **Transactions**: No cache, always fetch fresh
- **Parse Plans**: Cached on first use

### Batch Processing
- Position updates batched per account
- Import creates all transactions before position calc
- Bulk asset creation during first import

### Async/Await Usage
- PositionCalculator is an actor (thread-safe)
- Import pipeline async for progress updates
- Price fetching concurrent per asset

## Risk Mitigation

### Data Loss
- Force export before upgrade
- Keep old branch accessible
- Document rollback procedure

### Performance Regression
- Benchmark key operations
- Profile memory usage
- Monitor position calculation time

### Import Accuracy
- Comprehensive test fixtures
- Side-by-side comparison option
- Detailed import logs

## Future Extensibility Hooks

### Cost Basis (Stubbed)
```swift
struct Lot {
    let purchaseDate: Date
    let quantity: Decimal
    let costPerUnit: Decimal
    // Implement later
}
```

### Multi-Currency (Stubbed)
```swift
struct Money {
    let amount: Decimal
    let currency: String = "USD"  // Default for now
    // Implement conversion later
}
```

### Corporate Actions (Stubbed)
```swift
enum CorporateAction {
    case split(ratio: Decimal)
    case merger(into: Asset)
    case spinoff(newAsset: Asset)
    // Implement later
}
```

## Architecture Validation Checklist

- [ ] No circular dependencies between layers
- [ ] Domain models have no UI dependencies
- [ ] Services are testable in isolation
- [ ] Clear boundaries between institutions
- [ ] Position calculations are deterministic
- [ ] Import pipeline is resumable
- [ ] Asset identity is unambiguous
- [ ] Parse plans are versioned properly