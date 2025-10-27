# Price Data System Design

## Problem Statement

**Transaction prices are insufficient:**
```
Oct 1:  Buy 100 SPY @ $450  → Price known
Oct 15: (no transaction)    → Price unknown, but SPY = $475
Oct 30: (no transaction)    → Price unknown, but SPY = $440
Nov 1:  Sell 50 SPY @ $445  → Price known
```

**To show market value on Oct 15, Oct 30:**
- Need daily price data
- Independent of transactions
- For each asset held

## Data Model

### AssetPrice Model

```swift
@Model
final class AssetPrice {
    var id: UUID
    var assetId: String        // SPY, FBTC, etc.
    var date: Date             // Price date (daily granularity)
    var price: Decimal         // Price per unit
    var source: PriceSource    // Where price came from
    var createdAt: Date

    // Composite unique constraint
    // Only one price per asset per day
}

enum PriceSource: String, Codable {
    case transaction    // From buy/sell transactions
    case csvImport      // From price data CSV
    case api            // From Yahoo Finance, etc.
    case manual         // User entered
}
```

### Price Data CSV Format

**Upload separate price history files:**
```csv
Date,Symbol,Close
2024-01-01,SPY,475.32
2024-01-02,SPY,476.18
2024-01-03,SPY,474.55
...
2024-01-01,FBTC,52.10
2024-01-02,FBTC,51.85
```

**Or use multi-column:**
```csv
Date,SPY,VOO,QQQ,FBTC
2024-01-01,475.32,520.10,425.80,52.10
2024-01-02,476.18,521.35,426.20,51.85
```

## Price Data Sources

### Source 1: Transaction Prices (Already Have)

**Automatic:**
- Every buy/sell captures price
- Stored in `LedgerEntry.pricePerUnit`
- Sparse but accurate

**Implementation:**
```swift
// After creating ledger entry
if let price = ledgerEntry.pricePerUnit {
    let assetPrice = AssetPrice(
        assetId: ledgerEntry.assetId,
        date: ledgerEntry.date,
        price: price,
        source: .transaction
    )
    // Check if price for this date exists, if not insert
}
```

### Source 2: Price Data CSV Import (New Feature)

**Dedicated price import:**
```
Parse Studio → [Import Prices] button
- Upload CSV with Date, Symbol, Price columns
- Creates AssetPrice records
- Daily prices for backtesting
```

**Use case:**
- Download SPY historical prices from Yahoo Finance
- Import once
- Have complete price history

### Source 3: API Integration (Future)

**Fetch current prices:**
```swift
class PriceService {
    func fetchLatestPrices(for assets: [String]) async throws {
        // Call Yahoo Finance API
        // Store in AssetPrice table
    }

    func fetchHistoricalPrices(
        asset: String,
        from: Date,
        to: Date
    ) async throws {
        // Backfill missing dates
    }
}
```

### Source 4: Manual Entry (Admin)

**For illiquid assets:**
- User can add price manually
- Good for private holdings

## Market Value Calculation

### Current Holdings with Prices

```swift
func calculateMarketValue(
    assetId: String,
    date: Date,
    quantity: Decimal
) throws -> Decimal {
    // Find nearest price on or before date
    let price = try getPrice(assetId: assetId, on: date)
    return quantity * price
}

func getPrice(assetId: String, on date: Date) throws -> Decimal {
    let descriptor = FetchDescriptor<AssetPrice>(
        predicate: #Predicate { price in
            price.assetId == assetId &&
            price.date <= date
        },
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    )

    guard let latestPrice = try modelContext.fetch(descriptor).first else {
        throw PriceError.noPriceAvailable
    }

    return latestPrice.price
}
```

### Time Series Market Value

```swift
// For each time period
let positions = calculatePositionsAtDate(date)  // Qty of each asset
let prices = getPricesAtDate(date)             // Price of each asset

var totalMarketValue: Decimal = 0
for (assetId, quantity) in positions {
    let price = prices[assetId] ?? 0
    totalMarketValue += quantity * price
}
```

## UI Design

### Positions View Enhanced

```
┌─────────────────────────┬──────────────────────────┐
│ POSITIONS               │   VALUE OVER TIME        │
│                         │                          │
│ Show: [●Qty] [○Value]   │  $300K ┤      ╱────      │
│                         │        │     ╱            │
│ ☑ SPY    222 shares     │  $250K ┤    ╱             │
│   Value: $117,882       │        │   ╱              │
│   Cost: $118,000        │  $200K ┤  ╱               │
│   P&L: -$118 (-0.1%)    │        │ ╱                │
│                         │        └─────────────     │
│ ☑ FBTC   320 BTC        │         Oct   Nov   Dec  │
│   Value: $158,000       │                          │
│   Cost: $95,000         │  [Total] [SPY] [FBTC]    │
│   P&L: +$63k (+66%)     │                          │
│                         │                          │
│ Total: $385,000         │                          │
│ Gain: +$55,000 (+16.7%) │                          │
└─────────────────────────┴──────────────────────────┘
```

### New: Portfolio Value View

```
┌─────────────────────────────────────────────────┐
│ Portfolio Value                                 │
├─────────────────────────────────────────────────┤
│ Current Value: $385,000                         │
│ Cost Basis: $330,000                            │
│ Total Gain: +$55,000 (+16.7%)                   │
│                                                 │
│ [Chart: Total portfolio value over time]        │
│                                                 │
│ Allocation:                                     │
│ ████████████░░░░░░░░ FBTC 41% ($158k)          │
│ ██████████░░░░░░░░░░ SPY 31% ($118k)           │
│ ████████░░░░░░░░░░░░ VOO 17% ($67k)            │
│ ████░░░░░░░░░░░░░░░░ SCHD 11% ($42k)           │
└─────────────────────────────────────────────────┘
```

## Implementation Priority

### Must Have (Phase 1):
1. **Extract `pricePerUnit` from CSV** - Already have Price column!
2. **Store in LedgerEntry** - Simple field addition
3. **Calculate market value** - quantity × price
4. **Show in Positions cards** - Add value/P&L

### Should Have (Phase 2):
1. **AssetPrice model** - Separate price storage
2. **Price CSV import** - Bulk historical prices
3. **Market value chart** - USD value over time
4. **Price interpolation** - Fill gaps between transactions

### Nice to Have (Phase 3):
1. **API price fetching** - Yahoo Finance integration
2. **Real-time updates** - Current prices
3. **Price alerts** - Notify on thresholds
4. **Performance analytics** - CAGR, Sharpe ratio

## Recommendation

**Start with Phase 1:**
- Your CSVs have "Price ($)" column
- Extract it during parse
- Show market value in Positions
- Gives you 80% of value with 20% of work

**Then:**
- Separate price import for backfill
- API integration for current prices

**Should I implement price extraction from your CSV?**
