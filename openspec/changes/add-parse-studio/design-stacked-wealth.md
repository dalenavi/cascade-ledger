# Stacked Wealth Chart Design

## Visualization Goal

**Show cumulative wealth composition over time:**

```
$400K ┤                              ▓▓▓▓  ← Total wealth
      │                         ▓▓▓▓▓▓▓▓▓
$300K ┤                    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓
      │               ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
$200K ┤          ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  FBTC (top)
      │     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
$100K ┤▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  SPY
      │████████████████████████████████  VOO
      │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  SPAXX (bottom)
      └──────────────────────────────
       Apr    Jul    Oct    Dec
```

**Key features:**
- Each color = one asset
- Height = market value of that asset
- Top line = total portfolio value
- See both composition AND total

## Technical Challenge

**Stacked charts require aligned dates:**

**Current Portfolio Value (works):**
```
SPY:  [Oct 1: $45k, Oct 15: $47k, Nov 1: $67k]
FBTC: [Oct 5: $50k, Oct 20: $55k, Nov 10: $60k]
```
↑ Different dates, lines don't stack

**Stacked Chart (needs):**
```
SPY:  [Oct 1: $45k, Oct 5: $45k, Oct 15: $47k, Oct 20: $47k, Nov 1: $67k]
FBTC: [Oct 1: $0,   Oct 5: $50k, Oct 15: $50k, Oct 20: $55k, Nov 1: $50k]
```
↑ Same dates, can stack

## Implementation Approach

### Step 1: Create Unified Timeline

```swift
// Collect ALL price dates across all selected assets
let allPriceDates: Set<Date> = selectedAssets.flatMap { assetId in
    allPrices
        .filter { $0.assetId == assetId }
        .map { $0.date }
}

let sortedDates = allPriceDates.sorted()
```

### Step 2: Calculate Value for Each Asset at Each Date

```swift
struct WealthPoint {
    let date: Date
    var values: [String: Decimal]  // assetId → market value
}

var wealthPoints: [WealthPoint] = []

for date in sortedDates {
    var values: [String: Decimal] = [:]

    for assetId in selectedAssets {
        // Get quantity held on this date
        let quantity = getQuantityHeld(assetId: assetId, on: date)

        // Get price on this date
        let price = getPrice(assetId: assetId, on: date)

        // Calculate market value
        values[assetId] = quantity * price
    }

    wealthPoints.append(WealthPoint(date: date, values: values))
}
```

### Step 3: Convert to Stacked Chart Format

**Swift Charts needs:**
```swift
struct StackedWealthPoint: Identifiable {
    let id = UUID()
    let date: Date
    let assetId: String
    let value: Decimal
}

// Flatten for chart
var chartData: [StackedWealthPoint] = []
for point in wealthPoints {
    for (assetId, value) in point.values {
        chartData.append(StackedWealthPoint(
            date: point.date,
            assetId: assetId,
            value: value
        ))
    }
}

// Chart
Chart(chartData) { point in
    AreaMark(
        x: .value("Date", point.date),
        y: .value("Value", point.value)
    )
    .foregroundStyle(by: .value("Asset", point.assetId))
}
```

### Alternative: Pre-Stacked Values

**Swift Charts can stack automatically, or we can pre-stack:**

```swift
// Calculate cumulative offsets
var chartData: [StackedWealthPoint] = []
for point in wealthPoints {
    var cumulative: Decimal = 0

    // Bottom to top (consistent order)
    for assetId in selectedAssets.sorted() {
        let value = point.values[assetId] ?? 0
        let bottom = cumulative
        cumulative += value

        chartData.append(StackedWealthPoint(
            date: point.date,
            assetId: assetId,
            yStart: bottom,      // Where this asset starts
            yEnd: cumulative     // Where this asset ends
        ))
    }
}

// Chart with explicit stacking
Chart(chartData) { point in
    AreaMark(
        x: .value("Date", point.date),
        yStart: .value("Start", point.yStart),
        yEnd: .value("End", point.yEnd)
    )
    .foregroundStyle(by: .value("Asset", point.assetId))
}
```

## Performance Consideration

**With 500 price days × 8 assets = 4,000 data points**

**Optimization:**
- Apply granularity (weekly/monthly aggregation)
- Limit to selected time range
- Pre-calculate and cache

## View Design

```
┌────────────────────────────────────────────────┐
│ Total Wealth                                   │
├────────────────────────────────────────────────┤
│ Current: $385,000  •  Gain: +$55k (+16.7%)     │
│                                                │
│ [Stacked Area Chart]                           │
│ Shows composition and total                    │
│                                                │
│ ☑ Select assets to include                     │
│ ☑ FBTC    $158k  (41% - purple area)          │
│ ☑ SPY     $118k  (31% - blue area)            │
│ ☑ VOO     $65k   (17% - green area)           │
│ ☑ SPAXX   $4.5k  (1%  - gray area)            │
│ ☐ SCHD    (uncheck to remove from stack)      │
└────────────────────────────────────────────────┘
```

## Recommendation

**Create separate "Total Wealth" view:**
- Dedicated to stacked visualization
- Different from Portfolio Value (which shows individual lines)
- Shows composition over time
- Total value as top line

**Should I implement:**
1. Unified date alignment algorithm
2. Stacked area chart
3. Total Wealth view
4. Asset selection to customize stack

?
