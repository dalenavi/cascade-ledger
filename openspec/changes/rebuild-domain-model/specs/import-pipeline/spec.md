# Import Pipeline Capability

## ADDED Requirements

### Pipeline Stages
The import process shall follow explicit, testable pipeline stages.

#### Scenario: Five-stage pipeline execution
Given a CSV file to import
When processing through the pipeline
Then the following stages execute in order:
1. detectInstitution() identifies source as "fidelity"
2. parseCSV() extracts structured data
3. transform() applies ParsePlan mappings
4. materialize() creates Transaction and JournalEntry objects
5. updatePositions() recalculates affected positions
And errors at any stage halt the pipeline with clear messaging

#### Scenario: Stage isolation
Given a failure in the transform stage
When the error occurs
Then:
- Previous stages' work is preserved
- The error includes stage context
- Recovery can resume from the failed stage
- No partial data is committed

### Institution-Specific Handling
Each institution shall have tailored import logic.

#### Scenario: Fidelity settlement row grouping
Given a Fidelity CSV with pattern:
- Row 1: "YOU BOUGHT 100 SPY"
- Row 2: "" (empty action, settlement)
When processed by FidelityImporter
Then rows group into one Transaction
And the settlement is not a separate transaction
And the Transaction has balanced journal entries

#### Scenario: Coinbase simple transactions
Given a Coinbase CSV with one row per transaction
When processed by CoinbaseImporter
Then each row becomes one Transaction
And no settlement grouping occurs
And amounts are properly signed

### Settlement Detection
Settlement rows shall be detected using institution-specific patterns.

#### Scenario: Pluggable settlement detection
Given different institutions have different settlement patterns
When processing rows
Then:
- FidelitySettlementDetector checks for empty Action + Symbol + zero Quantity
- CoinbaseSettlementDetector returns false (no settlements)
- SchwabSettlementDetector uses different pattern
And each detector is isolated and testable

## MODIFIED Requirements

### ParseEngine Consolidation
ParseEngine and ParseEngineV2 shall be merged into a single, clean implementation.

#### Scenario: Single parse engine
Given the current dual ParseEngine situation
When rebuilding
Then:
- Only one ParseEngine exists
- It uses the double-entry model exclusively
- Legacy single-entry code is removed
- The API is simplified

### Transaction Building
TransactionBuilder shall use AssetRegistry for all asset resolution.

#### Scenario: Asset resolution during import
Given a CSV row with symbol "AAPL"
When TransactionBuilder processes it
Then:
- AssetRegistry.findOrCreate("AAPL") is called
- The returned Asset is used in JournalEntry
- No string symbols are stored (except for compatibility)
- The same Asset instance is reused for all AAPL references