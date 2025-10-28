# Position Tracking Capability

## ADDED Requirements

### Materialized Positions
The system shall maintain materialized position records for performance.

#### Scenario: Position calculation from transactions
Given an account with transactions:
- Buy 100 SPY on 2024-01-01
- Buy 50 SPY on 2024-02-01
- Sell 30 SPY on 2024-03-01
When positions are calculated
Then Position.quantity equals 120
And Position.lastTransactionDate equals 2024-03-01
And the position is persisted to database

#### Scenario: Zero position handling
Given a Position with 50 shares of AAPL
When a sell transaction for 50 shares is added
Then Position.quantity becomes 0
And the Position record is deleted
And historical transactions remain intact

### Asynchronous Position Updates
Position calculations shall happen asynchronously to prevent UI blocking.

#### Scenario: Batch import position update
Given an import of 500 transactions
When the import completes
Then PositionCalculator schedules one batch recalculation
And intermediate states are not calculated
And UI shows "calculating positions" indicator
And positions update when complete

#### Scenario: Manual position refresh
Given positions marked as stale
When user clicks "Refresh Positions"
Then PositionCalculator processes all pending accounts
And progress is shown during calculation
And lastCalculated timestamp updates on completion

### Multi-Account Aggregation
Positions shall be aggregatable across accounts without recalculation.

#### Scenario: Cross-account aggregation
Given:
- Account A has Position(SPY, quantity: 100)
- Account B has Position(SPY, quantity: 200)
When viewing portfolio summary
Then aggregate shows SPY: 300
And drill-down shows per-account breakdown
And aggregation completes in < 100ms

#### Scenario: Asset class grouping
Given positions in multiple assets:
- SPY (ETF): 100 shares
- VOO (ETF): 50 shares
- AAPL (Stock): 25 shares
When grouping by asset class
Then ETF group shows total 150 shares across 2 assets
And Stock group shows 25 shares in 1 asset
And groups are expandable to show details

## MODIFIED Requirements

### Transaction to Position Flow
Transactions shall trigger position recalculation through the PositionCalculator service.

#### Scenario: Transaction triggers update
Given a new Transaction is saved
When the transaction contains asset journal entries
Then PositionCalculator.scheduleRecalculation(account) is called
And the account is queued for processing
And existing queue entries are deduplicated