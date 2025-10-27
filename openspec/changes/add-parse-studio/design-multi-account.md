# Multi-Account Support Design

## Current State

**Single account context:**
- Views show data for `selectedAccount` only
- Sidebar shows list of accounts
- Click account → views update to show that account's data

## Proposed Multi-Account Features

### 1. Balance View (Already Implemented)

**Current capability:**
- Primary account shown by default
- "Accounts" menu button → add other accounts
- Chart shows multiple lines (one per account)
- Cumulative balance for each account
- Total balance sums all selected accounts

**UX:**
```
[Fidelity Account ▼]  [+Accounts (2)]
                       ├─ ✓ Fidelity Account
                       ├─ ✓ Chase Checking
                       └─ ○ Vanguard IRA

Chart: 2 lines (Fidelity + Chase)
Total: Sum of both accounts
```

### 2. Analytics View

**Proposed:**
- Add account selector (similar to Balance)
- Default: Current account only
- Can add multiple accounts
- Chart shows: Combined data across accounts
- Breakdown cards: Aggregate totals

**Use case:**
- Compare spending across checking vs credit card
- See total investment activity across all brokerage accounts

### 3. Timeline View

**Proposed:**
- Filter by account(s)
- Show transactions from selected accounts
- Cards aggregate across selected accounts

### 4. Transactions View

**Current:** Shows single account only

**Proposed Option A - Keep Simple:**
- Stay single-account focused
- Multi-account comparison happens in other views

**Proposed Option B - Add Filter:**
- Account selector checkbox list (like type filter)
- Can view/edit transactions across accounts
- Useful for reconciliation

**Recommendation:** Option A - keep Transactions single-account for clarity

## Implementation Plan

### Phase 1: Balance View (Complete ✅)
- Multi-account selector menu
- Per-account balance lines on chart
- Aggregate total balance

### Phase 2: Analytics View
- Add account selector menu
- Aggregate data across selected accounts
- Show which accounts are included

### Phase 3: Timeline View
- Add account filter
- Show combined transaction list
- Indicate which account each transaction belongs to

### Phase 4: Account Comparison View (Future)
- Dedicated view for comparing accounts
- Side-by-side metrics
- Relative performance

## Data Considerations

### Query Strategy

**Current:**
```swift
Query(filter: #Predicate { $0.account?.id == accountId })
```

**Multi-account:**
```swift
Query(filter: #Predicate { selectedAccountIds.contains($0.account?.id) })
```

### Aggregation

**Grouped by account:**
```swift
transactions
  .group(by: \.account)
  .map { (account, entries) in
      (account.name, entries.sum(\.amount))
  }
```

### UI State

**Add to views:**
```swift
@State private var selectedAccounts: Set<UUID> = []
@State private var primaryAccount: Account // Current context
```

## Multi-Account UX Patterns

### Pattern 1: Sidebar Selection (Current)
- Click account in sidebar → becomes primary
- All views show that account's data
- **Advantage:** Clear context
- **Disadvantage:** Can't compare across accounts

### Pattern 2: Additive Selection (Balance View)
- One primary account (from sidebar)
- "+" menu to add more accounts
- Chart shows multiple lines
- **Advantage:** Easy comparison
- **Disadvantage:** Can get crowded

### Pattern 3: Account Filter (Proposed for Analytics)
- Show all accounts by default
- Filter checkboxes to select subset
- Similar to type/category filters
- **Advantage:** Consistent with other filters
- **Disadvantage:** Less discoverable

### Recommendation: Hybrid Approach

**For analytical views (Analytics, Balance, Timeline):**
- Start with primary account (from sidebar)
- "+ Accounts" menu to add others
- Check/uncheck to toggle
- Primary account always stays checked

**For transactional views (Transactions, Parse Studio):**
- Stay single-account
- Clear which account you're working with
- Avoids confusion when editing

## Questions

1. **Should Analytics aggregate or overlay?**
   - Aggregate: Combine all accounts into single totals per category
   - Overlay: Show each account as separate line (like Balance view)
   - **Recommendation:** Aggregate for Analytics, Overlay for Balance

2. **How to handle account switching?**
   - Should selected accounts persist when you change primary account?
   - Or reset to show only new primary?
   - **Recommendation:** Reset to avoid confusion

3. **Net worth view?**
   - Sum all accounts for total net worth over time?
   - **Recommendation:** Yes, add as separate view or mode in Balance

4. **Account groups?**
   - Group accounts: "Retirement" (401k + IRA), "Checking" (multiple banks)
   - **Recommendation:** Future feature, not MVP

## Next Steps

1. ✅ Balance view with multi-account (complete)
2. Add multi-account to Analytics view
3. Add multi-account to Timeline view
4. Consider dedicated Net Worth view
5. Test performance with multiple accounts
