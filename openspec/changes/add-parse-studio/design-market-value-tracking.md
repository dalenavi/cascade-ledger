# Market Value Tracking Design

## Current State

**We track:**
- Quantity: 100 shares SPY
- Cost Basis: $45,000 invested

**We DON'T track:**
- Current market price
- Market value (100 shares × current price)
- Gains/losses

## Required Features

### 1. Price Extraction from CSV

**Your CSV has "Price ($)" column:**
```
Action: Buy, Symbol: SPY, Quantity: 100, Price: $450.00
```

**Extract and store:**
- Transaction has price per unit at time of trade
- Historical price points from each transaction

### 2. Market Value Calculation

**Formula:**
```
Market Value = Quantity Held × Last Known Price
```

**Example:**
- Hold 100 shares SPY
- Last transaction: $475/share
- Market Value: $47,500 (not $45,000 cost basis)
- Gain: $2,500

### 3. Portfolio Value Over Time

**Chart shows:**
- Not quantity (100 shares)
- Not cost basis ($45,000)
- But market value using prices at each point

## Data Model Options

### Option A: Store Price in Transaction (Simple)

```swift
@Model
final class LedgerEntry {
    var quantity: Decimal?
    var pricePerUnit: Decimal?  // NEW: Price at transaction time

    // Computed
    var transactionMarketValue: Decimal? {
        guard let qty = quantity, let price = pricePerUnit else { return nil }
        return abs(qty) * price
    }
}
```

**Extract from CSV:**
- Map "Price ($)" → `pricePerUnit`
- Store with each transaction
- Historical prices embedded in transaction history

### Option B: Separate Price Model (Complex, Future)

```swift
@Model
final class AssetPrice {
    var assetId: String
    var date: Date
    var price: Decimal
    var source: PriceSource // CSV, API, Manual
}
```

**More flexible but overkill for now**

## View Enhancements

### Positions View - Market Value Mode

**Add toggle:**
```
Mode: [Quantity] [Market Value]
```

**Quantity Mode (current):**
```
SPY: 100 shares
     Cost Basis: $45,000
```

**Market Value Mode (new):**
```
SPY: $47,500  (100 shares @ $475)
     Cost: $45,000
     Gain: +$2,500 (+5.6%)
```

**Chart:**
- Quantity mode: Y-axis = shares
- Market Value mode: Y-axis = USD

### Balance View - Market Value

**Holdings mode could show:**
```
Total Holdings: $250,000 (market value)

☑ SPY    $47,500  (100 shares)
☑ FBTC   $95,000  (1.5 BTC)
☑ VOO    $65,000  (150 shares)
```

**Chart:**
- Cumulative market value
- Not cost basis
- Shows actual portfolio worth

### Analytics - By Asset Value

**Group By: Asset (market value weighted)**
```
SPY: $47,500  (18.9% of portfolio)
FBTC: $95,000 (37.9% of portfolio)
VOO: $65,000  (25.9% of portfolio)
```

## Implementation Plan

### Phase 1: Extract Price from CSV

**Update parse engine:**
```swift
// Map "Price ($)" column
ledgerEntry.pricePerUnit = data["price"] as? Decimal

// Or calculate from amount/quantity if price column missing
if pricePerUnit == nil && quantity != nil {
    pricePerUnit = abs(amount) / abs(quantity)
}
```

**Update system prompt:**
```
Map "Price ($)" or "Price" column to metadata.price_per_unit
```

### Phase 2: Market Value Calculation

**Add to Positions view:**
```swift
func calculateMarketValue(_ entries: [LedgerEntry], assetId: String) -> [MarketValuePoint] {
    var position: Decimal = 0
    var lastPrice: Decimal = 0
    var points: [MarketValuePoint] = []

    for entry in entries.sorted(by: { $0.date < $1.date }) {
        // Update position
        position += entry.quantity ?? 0

        // Update price if transaction has one
        if let price = entry.pricePerUnit {
            lastPrice = price
        }

        // Calculate market value
        let marketValue = position * lastPrice

        points.append(MarketValuePoint(
            date: entry.date,
            quantity: position,
            price: lastPrice,
            marketValue: marketValue
        ))
    }

    return points
}
```

### Phase 3: UI Updates

**Positions View:**
- Add "Show: Quantity / Market Value" toggle
- Switch between share count and USD value
- Show gains in cards

**Balance View:**
- Market value instead of cost basis option
- Total portfolio value
- Percentage allocation

**New: Portfolio View (Future)**
- Pie chart of allocation
- Total market value
- Total gains/losses
- Performance over time

## Price Data Strategy

### For Historical Data:

**From transactions:**
- Each buy/sell has price
- Use last known price for periods between trades
- Approximate but accurate for your data

### For Current Prices (Future):

**API integration:**
- Fetch current prices from Yahoo Finance, etc.
- Update daily
- Show real-time gains

**For now:**
- Use prices from CSV only
- Market value = position × last transaction price
- Good enough for historical analysis

## Example: SPY Market Value Chart

**Positions:**
```
Apr 23: Buy 4 @ $450 = 4 shares, value $1,800
Apr 30: Buy 8 @ $455 = 12 shares, value $5,460  (12 × $455)
May 2:  Buy 8 @ $460 = 20 shares, value $9,200  (20 × $460)
May 6:  Buy 8 @ $465 = 28 shares, value $13,020 (28 × $465)
```

**Chart shows:**
- Line going from $1,800 → $13,020 (market value)
- Not 4 → 28 shares
- Shows actual portfolio value growth

## Questions

**1. Should market value be:**
- Separate view?
- Mode toggle in existing views?
- **Recommendation:** Toggle in Positions, mode in Balance

**2. Price source priority:**
- Use "Price ($)" from CSV?
- Calculate from amount/quantity if missing?
- **Recommendation:** Both (prefer CSV column, fall back to calculation)

**3. Current prices (no recent transactions):**
- Show last known price?
- Mark as stale ("> 30 days old")?
- **Recommendation:** Show last known, add staleness indicator

**Should I implement:**
1. Extract `pricePerUnit` from CSV
2. Add Market Value mode to Positions
3. Calculate USD value over time
4. Show gains/losses

?
