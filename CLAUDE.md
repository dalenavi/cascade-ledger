<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

## Development Workflow

- Use `xcodebuild` to build and check for compilation errors
- DO NOT use `open` to launch the app - the user will run it themselves
- Build tests are sufficient for validation

## CLI Transaction Mapping Guide

### Workflow
1. Create account → 2. Create mapping → 3. Upload CSV → 4. Map rows → 5. Validate → 6. Activate

### Double-Entry Rules (CRITICAL)

**Buy security**: Asset DR, Cash CR
```bash
--entries "SPY:DR:2019.24,Cash:CR:2019.24"
```

**Sell security**: Cash DR, Asset CR
```bash
--entries "Cash:DR:800,SPY:CR:800"
```

**Income**: Cash DR, Source CR
```bash
--entries "Cash:DR:5000,Payroll:CR:5000"
```

**Expense/Transfer out**: Expense DR, Cash CR
```bash
--entries "VS-Transfer:DR:500,Cash:CR:500"
```

### Transaction Create

```bash
./cascade transaction create \
  --from-rows <row> \
  --date "MM/DD/YYYY" \
  --description "Brief desc" \
  --entries "Account1:DR:Amount,Account2:CR:Amount" \
  --mapping "name" \
  --category "path/to/category"
```

**Extract from CSV:**
- Run Date → --date
- Amount ($) → use ABSOLUTE value
- Action → determine account names
- Quantity → auto-extracted for securities

### Categories (Hierarchical)

Format: `primary/secondary/tertiary`

Common:
- `investment/equity` - Stocks/ETFs
- `investment/crypto` - FBTC
- `investment/commodities` - GLD
- `income/employment` - Payroll
- `income/investment/dividend` - Dividends
- `income/transfer-in` - Wires, checks, transfers IN
- `transfer/internal` - Transfers OUT
- `expense/personal` - Spending
- `expense/fees` - Margin, commissions

### Query System

```bash
./cascade query --asset SPY                    # Filter by asset
./cascade query --category investment          # Filter by category
./cascade query --from "05/01/2024"            # Date range
./cascade query --positions                    # Show holdings
./cascade query --positions --category investment/equity
```

### Validation

```bash
./cascade validate "mapping-name"
```

Shows: Coverage %, unmapped rows, balance discrepancies, category coverage

### Key Commands

```bash
./cascade account create "Name"
./cascade mapping create "name" --account "Name"
./cascade source add file.csv --mapping "name"
./cascade rows file.csv --range 1-10
./cascade transaction create ... (see above)
./cascade validate "name"
./cascade query --positions
./cascade mapping activate "name"
```