# Automated Price Data Fetching

## Price Data Sources

### For Stocks/ETFs (SPY, VOO, QQQ, etc.)

**Option 1: Yahoo Finance (Recommended)**
- **Free, no API key needed**
- Endpoint: `https://query1.finance.yahoo.com/v8/finance/chart/{SYMBOL}`
- Historical data: Available
- Rate limits: Generous for personal use
- Coverage: All US stocks/ETFs

**Option 2: Alpha Vantage**
- Free API key required
- 25 requests/day free tier
- Good for small portfolios
- https://www.alphavantage.co/

**Option 3: Twelve Data**
- Free tier: 800 requests/day
- Good coverage
- https://twelvedata.com/

### For Crypto (FBTC, BTC, ETH)

**CoinGecko API (Recommended)**
- Free, no API key needed
- Endpoint: `https://api.coingecko.com/api/v3/simple/price`
- Historical: `https://api.coingecko.com/api/v3/coins/{id}/market_chart`
- Rate limits: 10-30 calls/minute free
- Supports BTC, ETH, etc.

**CoinMarketCap**
- API key required
- More crypto coverage
- Good for FBTC (bitcoin trust)

## Implementation Design

### PriceAPIService

```swift
class PriceAPIService {
    // Fetch latest prices for assets
    func fetchLatestPrices(for assets: [String]) async throws -> [String: Decimal]

    // Fetch historical prices for date range
    func fetchHistoricalPrices(
        asset: String,
        from: Date,
        to: Date
    ) async throws -> [(Date, Decimal)]

    // Backfill missing dates
    func backfillPrices(
        for assets: [String],
        from: Date,
        to: Date
    ) async throws -> Int
}
```

### Asset Type Detection

```swift
enum AssetType {
    case stock      // SPY, VOO, QQQ
    case crypto     // BTC, ETH
    case etf        // Same as stock
    case fund       // FXAIX, SPAXX

    var priceSource: PriceAPISource {
        switch self {
        case .stock, .etf, .fund:
            return .yahooFinance
        case .crypto:
            return .coinGecko
        }
    }
}

func detectAssetType(_ assetId: String) -> AssetType {
    let crypto = ["BTC", "ETH", "FBTC", "GBTC"]
    if crypto.contains(assetId) || assetId.contains("BTC") {
        return .crypto
    }
    return .stock
}
```

### Yahoo Finance Integration

```swift
class YahooFinanceService {
    func fetchHistoricalPrices(
        symbol: String,
        from: Date,
        to: Date
    ) async throws -> [(Date, Decimal)] {
        let url = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)"

        var components = URLComponents(string: url)!
        components.queryItems = [
            URLQueryItem(name: "period1", value: "\(Int(from.timeIntervalSince1970))"),
            URLQueryItem(name: "period2", value: "\(Int(to.timeIntervalSince1970))"),
            URLQueryItem(name: "interval", value: "1d")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Parse Yahoo Finance response
        let chart = json["chart"] as! [String: Any]
        let result = (chart["result"] as! [[String: Any]]).first!

        let timestamps = result["timestamp"] as! [Int]
        let quotes = result["indicators"] as! [String: Any]
        let quote = (quotes["quote"] as! [[String: Any]]).first!
        let closes = quote["close"] as! [Double?]

        var prices: [(Date, Decimal)] = []
        for (index, timestamp) in timestamps.enumerated() {
            if let close = closes[index] {
                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                prices.append((date, Decimal(close)))
            }
        }

        return prices
    }
}
```

### CoinGecko Integration

```swift
class CoinGeckoService {
    func fetchHistoricalPrices(
        coinId: String,  // "bitcoin", "ethereum"
        from: Date,
        to: Date
    ) async throws -> [(Date, Decimal)] {
        let url = "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart/range"

        var components = URLComponents(string: url)!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "from", value: "\(Int(from.timeIntervalSince1970))"),
            URLQueryItem(name: "to", value: "\(Int(to.timeIntervalSince1970))")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let pricesArray = json["prices"] as! [[Any]]
        return pricesArray.map { item in
            let timestamp = item[0] as! TimeInterval / 1000
            let price = item[1] as! Double
            return (Date(timeIntervalSince1970: timestamp), Decimal(price))
        }
    }

    func mapSymbolToCoinId(_ symbol: String) -> String {
        switch symbol {
        case "BTC", "FBTC", "GBTC": return "bitcoin"
        case "ETH": return "ethereum"
        default: return symbol.lowercased()
        }
    }
}
```

## UI Features

### Automatic Backfill

**In Price Data view:**
```
┌────────────────────────────────────────┐
│ Price Data                             │
├────────────────────────────────────────┤
│ SPY      1,250 days  ⚠️ Last: Oct 15   │
│ Missing: Oct 16 - Dec 31 (77 days)     │
│          [Fetch Missing]                │
│                                        │
│ FBTC     0 days      ⚠️ No data        │
│          [Fetch All]                   │
└────────────────────────────────────────┘
```

**Click [Fetch Missing]:**
- Detects gaps in price history
- Fetches from Yahoo Finance/CoinGecko
- Fills in missing dates
- Shows progress

### Smart Fetching

**On viewing Positions:**
```
System detects: You hold SPY but no prices in last 7 days

[Background notification]
"Fetching latest prices for your holdings..."

Updates AssetPrice table
Recalculates market values
```

### Settings Configuration

```
┌────────────────────────────────────────┐
│ Price Data Settings                    │
├────────────────────────────────────────┤
│ Auto-fetch prices:                     │
│ ☑ On app launch                        │
│ ☑ Daily at 4:00 PM (market close)      │
│ ☐ Every hour during market hours       │
│                                        │
│ Data Sources:                          │
│ ☑ Yahoo Finance (stocks/ETFs)          │
│ ☑ CoinGecko (crypto)                   │
│ ☐ Alpha Vantage (backup)               │
│                                        │
│ Cache Duration: [7 days ▼]             │
└────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Yahoo Finance (Stocks)
```swift
class YahooFinanceService {
    func fetchDailyPrices(symbol: String, days: Int = 365) async throws
    func fetchPriceRange(symbol: String, from: Date, to: Date) async throws
}
```

### Phase 2: CoinGecko (Crypto)
```swift
class CoinGeckoService {
    func fetchDailyPrices(coinId: String, days: Int = 365) async throws
    func fetchPriceRange(coinId: String, from: Date, to: Date) async throws
}
```

### Phase 3: Smart Backfill
```swift
class PriceBackfillService {
    // Find gaps in price data
    func findMissingDates(assetId: String, from: Date, to: Date) -> [Date]

    // Fill gaps
    func backfillAsset(assetId: String) async throws

    // Backfill all holdings
    func backfillPortfolio(account: Account) async throws
}
```

### Phase 4: Auto-Update
```swift
// On app launch or daily schedule
Task {
    let assets = getHeldAssets()  // SPY, FBTC, etc.
    for asset in assets {
        try await priceService.updateLatest(asset)
    }
}
```

## Example: Full Workflow

**1. User holds SPY, VOO, FBTC**

**2. Click "Fetch All Prices" in Price Data view:**
```
Fetching SPY...  ✓ 365 days imported
Fetching VOO...  ✓ 365 days imported
Fetching FBTC... ✓ 365 days imported

Total: 1,095 price points imported
```

**3. Positions view now shows:**
```
SPY: $117,882 (222 @ $531)
     Cost: $118,000
     Loss: -$118 (-0.1%)

Chart: Market value fluctuating daily
```

**4. Daily update (automatic):**
- Fetches today's closing prices
- Updates market values
- Shows current P&L

## Recommendation

**Start with:**
1. Yahoo Finance for stocks (SPY, VOO, QQQ, etc.)
2. CoinGecko for crypto (FBTC → Bitcoin prices)
3. Manual backfill trigger (user clicks button)

**Then add:**
1. Automatic updates on app launch
2. Scheduled daily fetches
3. Gap detection and auto-fill

**Should I implement:**
- Yahoo Finance service?
- CoinGecko service?
- "Fetch Prices" button in Price Data view?

This gives you complete daily price history for accurate market value tracking!