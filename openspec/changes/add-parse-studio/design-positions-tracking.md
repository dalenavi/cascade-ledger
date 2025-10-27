# Position Tracking Design

## Problem Statement

**Current Balance view is USD-centric:**
- Shows dollar amounts only
- Holdings mode tracks cost basis ($12,500 in SPY)
- Doesn't show actual units (100 shares of SPY)

**Need: Asset-native unit tracking**
- SPY: 100 shares
- FBTC: 0.5 BTC
- VOO: 50 shares
- USD: $12,500

## Proposed: Positions View

### Data Model Enhancement

**Add to LedgerEntry:**
```swift
@Model
final class LedgerEntry {
    // Existing fields...
    var amount: Decimal              // Dollar amount (always USD)

    // NEW: Quantity tracking
    var quantity: Decimal?           // Units of the asset
    var quantityUnit: String?        // "shares", "BTC", "ETH", etc.

    // Computed
    var pricePerUnit: Decimal? {
        guard let quantity = quantity, quantity != 0 else { return nil }
        return abs(amount) / abs(quantity)
    }
}
```

**Examples:**
```
Buy 100 shares SPY @ $450/share:
- amount: -$45,000 (cash out)
- quantity: 100
- quantityUnit: "shares"
- assetId: "SPY"

Buy 0.5 BTC @ $60,000/BTC:
- amount: -$30,000 (cash out)
- quantity: 0.5
- quantityUnit: "BTC"
- assetId: "FBTC"

Dividend $25.50:
- amount: $25.50
- quantity: nil
- assetId: "SPY" (from which stock)
```

### Positions View Layout

```
┌─────────────────────────┬───────────────────────────────────┐
│ POSITIONS               │        QUANTITY OVER TIME         │
│                         │                                   │
│ ☑ SPY         100 shares│  120 ┤                           │
│   Cost: $45,000         │      │      ╱─────────            │
│   Avg: $450/share       │  100 ┤     ╱                      │
│                         │      │    ╱                       │
│ ☑ FBTC        0.5 BTC   │   80 ┤   ╱                        │
│   Cost: $30,000         │      │  ╱                         │
│   Avg: $60,000/BTC      │   60 ┤ ╱                          │
│                         │      │╱                           │
│ ☑ VOO         50 shares │      └─────────────────────       │
│   Cost: $12,500         │       Oct 1   Oct 15   Oct 31    │
│   Avg: $250/share       │                                   │
│                         │  [SPY] [FBTC] [VOO]               │
│ ☐ USD         $12,500   │                                   │
│   Cash                  │                                   │
│                         │                                   │
│ [Select All]            │                                   │
│ [Deselect All]          │                                   │
└─────────────────────────┴───────────────────────────────────┘
```

### Unit Types

**Stocks/ETFs:**
- Unit: "shares"
- Display: "100 shares"
- Price: $/share

**Crypto:**
- Unit: "BTC", "ETH", "FBTC"
- Display: "0.5 BTC"
- Price: $/BTC

**Cash:**
- Unit: "USD" (or other currency)
- Display: "$12,500"
- Price: N/A

**Commodities (future):**
- Unit: "oz" (gold), "bbl" (oil)
- Display: "10 oz"

### Parse Plan Updates

**Claude needs to extract quantity:**
```json
{
  "fields": [
    {"name": "Quantity", "type": "number", "mapping": "quantity"},
    {"name": "Symbol", "type": "string", "mapping": "assetId"},
    {"name": "Price", "type": "currency", "mapping": "metadata.price_per_share"},
    {"name": "Amount", "type": "currency", "mapping": "amount"}
  ]
}
```

**For CSV without quantity:**
- Can be calculated: quantity = amount / price (if price available)
- Or left null (dividends, fees, etc.)

### Position Calculation

**Cumulative quantity over time:**
```
Starting position: 0 shares SPY

Oct 1:  Buy 50 shares → Position: 50 shares
Oct 5:  Buy 30 shares → Position: 80 shares
Oct 10: Sell 20 shares → Position: 60 shares
Oct 15: Buy 40 shares → Position: 100 shares

Current: 100 shares SPY
```

**Chart Y-axis:**
- Not dollars
- Actual units (shares, BTC, etc.)
- Mixed units on same chart (with separate scales if needed)

### View Comparison

| View | Measures | Units | Use Case |
|------|----------|-------|----------|
| **Balance** | Cash flow | USD | Account balance over time |
| **Positions** | Asset quantities | Shares, BTC, USD | What you actually own |
| **Analytics** | Activity | USD | Spending/income analysis |

### Questions

**1. Quantity in CSV:**
- Is quantity usually present? (Quantity, Shares columns?)
- Or need to calculate from Amount/Price?

**2. Mixed units on chart:**
- Show all on same chart (100 shares, 0.5 BTC, $12,500)?
- Or separate charts per unit type?
- Recommendation: Same chart, different scales if needed

**3. Price tracking:**
- Store price per unit in metadata?
- Calculate average cost basis?
- Show current market value vs cost? (future feature)

**4. Unit standardization:**
- Auto-detect unit from asset? (SPY → "shares", FBTC → "BTC")
- Or let user configure?

## Implementation Plan

1. Add `quantity` and `quantityUnit` to LedgerEntry model
2. Update parse plan to extract quantity from CSV
3. Create Positions view with unit tracking
4. Calculate cumulative quantities over time
5. Display in asset-native units

**Should I proceed with implementation?**
