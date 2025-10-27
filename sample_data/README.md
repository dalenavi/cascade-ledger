# Sample Transaction Data

## Fidelity Sample Transactions

**File:** `fidelity_sample_transactions.csv`

**Format:** Fidelity brokerage account transaction history export

### Structure

**Columns:**
- Run Date - Transaction date
- Action - Type of transaction (YOU BOUGHT, YOU SOLD, DIVIDEND, etc.)
- Symbol - Asset ticker (SPY, VOO, QQQ, FBTC, etc.)
- Description - Full asset name
- Type - Account type (Cash, Margin)
- Quantity - Number of shares/units
- Price ($) - Price per unit
- Commission ($) - Trading commission
- Fees ($) - Additional fees
- Accrued Interest ($) - Interest
- Amount ($) - Dollar amount (signed)
- Cash Balance ($) - Running cash balance after transaction
- Settlement Date - When transaction settles

### Transaction Patterns

**1. Asset Purchase (Double-Entry)**
```csv
04/23/2024,YOU BOUGHT,SPY,...,Cash,4,504.81,...,-2019.24,2032.69,...
04/23/2024,,,,Cash,0,,,,,2032.69,2032.69,...
```
- Row 1: Asset row (qty=4, amount=-$2,019.24)
- Row 2: Settlement row (Action=blank, qty=0, amount=opposite)
- Cash Balance shows net result

**2. Asset Sale**
```csv
06/12/2024,YOU SOLD,QQQ,...,Cash,-8,492.42,...,3939.41,94884.95,...
06/12/2024,,,,Cash,0,,,,,-3939.41,94884.95,...
```
- Row 1: qty=-8 (negative = selling)
- Row 2: Settlement (cash reduction)

**3. Dividend - Cash Payment**
```csv
05/01/2024,DIVIDEND,SPY,SPDR S&P500 ETF TRUST DIVIDEND,Cash,0,,,,,52264,58394.38,...
```
- Single row (no settlement pair)
- qty=0, cash dividend
- Increases Cash Balance

**4. Dividend - Reinvestment**
```csv
04/30/2024,DIVIDEND,SPAXX,FIDELITY GOVERNMENT MONEY MARKET,Cash,0.29,1,...,-0.29,6030.67,...
04/30/2024,,,,Cash,0,,,,,0.29,6030.67,...
```
- Row 1: Adds shares (qty=0.29)
- Row 2: Settlement
- Net cash impact ≈ $0

**5. External Transfer**
```csv
08/23/2024,TRANSFERRED TO,VS,TRANSFERRED TO VS Z31...,Cash,0,,,,,,-4550,144218.26,...
```
- Single row
- Pure cash movement
- Reduces Cash Balance

### Accounting Rules

**USD Cash Balance:**
- Read from "Cash Balance ($)" column (authoritative)
- Or calculate: Only from rows with Action != blank
- Ignore settlement rows (Action=blank, qty=0)

**Asset Positions:**
- Sum quantities from rows with qty != 0
- Use Price ($) for cost basis

**Double-Entry Validation:**
```
For grouped rows with same date + Action:
  Σ(Amount) ≈ 0  (may have rounding)
  Asset row + Settlement row should offset
```

### Edge Cases Demonstrated

- **Margin trades:** Type="Margin" (row 14)
- **Multiple settlements:** Sometimes 2-3 settlement rows for one trade
- **Same-day multiple transactions:** Multiple unrelated trades same date
- **Fractional shares:** qty=0.29, 0.119, etc.
- **Large dividends:** qty=0, amount=$52,264
- **Zero-amount rows:** Reclassifications, transfers

### Usage

**Testing parse plans:**
1. Import this CSV
2. Ask Claude to create parse plan
3. Verify: 13 columns mapped correctly
4. Check: Settlement rows handled properly
5. Validate: Cash Balance matches USD calculation

**Testing transaction grouping:**
1. Group by Action != blank
2. Associate settlement rows with prior action
3. Verify double-entry balance
4. Extract net cash impact

### Known Issues to Handle

1. **Settlement rows:** Action=blank, should group with prior
2. **Multiple settlements:** 3-4 rows for one economic transaction
3. **Cash balance jumps:** Large dividends, transfers
4. **Description quality:** Many "No Description" entries
5. **Margin vs Cash:** Type column distinguishes (affects available cash)
