# Transaction Activation Model

## The Core Problem

**You have:**
- Raw CSV data (immutable)
- Multiple categorization sessions (v1, v2, v3...)
- Each session produces different transactions from same CSV rows
- App needs to know: **"Which transactions are real right now?"**

## Design Options

### Option A: Active Pointer (Git-like)
```
Account {
  categorizationSessions: [v1, v2, v3]
  activeSessionId: UUID  ← Points to v1, v2, or v3
}

All views filter:
  transactions.filter { $0.categorizationSession?.id == account.activeSessionId }
```

**Pros:**
- Simple pointer flip
- Non-destructive (all versions kept)
- Switch instantly

**Cons:**
- Every query needs filtering
- Transactions from inactive sessions clutter database

### Option B: Materialization (Deploy Model)
```
CategorizationSession {
  transactions: [Transaction]  // Staged, not materialized
  isDeployed: Bool
}

When user clicks "Deploy v2":
1. Delete all transactions where account.id == this account
2. Deep copy v2.transactions → new Transaction records
3. Mark v2 as deployed
```

**Pros:**
- Clean transaction table (only active transactions)
- No filtering needed in queries
- Clear "source of truth"

**Cons:**
- Destructive (old deployed version's transactions deleted)
- Slower to switch
- Need to track history

### Option C: Workspace Model (Multiple Namespaces)
```
Transaction {
  account: Account
  workspace: Workspace?  // null = materialized, UUID = preview
}

Account {
  activeWorkspace: UUID?  // null = show materialized only
}

Views filter:
  if account.activeWorkspace == nil:
    show transactions.filter { $0.workspace == nil }
  else:
    show transactions.filter { $0.workspace == account.activeWorkspace }
```

**Pros:**
- Can preview without deploying
- Multiple "branches" can coexist
- Flexible

**Cons:**
- Complex
- workspace concept might confuse

## Recommended: **Option A with Cleanup**

```swift
@Model
class Account {
    var activeCategorizationSessionId: UUID?

    var activeTransactions: [Transaction] {
        guard let activeId = activeCategorizationSessionId else {
            return []  // No active categorization
        }

        return categorizationSessions
            .first { $0.id == activeId }?
            .transactions ?? []
    }
}

// In TransactionsView, PositionsView, etc:
let transactions = account.activeTransactions
```

**Switching versions:**
```swift
func activateSession(_ session: CategorizationSession) {
    account.activeCategorizationSessionId = session.id
    try modelContext.save()

    // All @Query views auto-refresh
}
```

**Cleanup old sessions:**
```swift
func cleanupInactiveSessions() {
    // Keep active + last 3 versions, delete rest
    let toDelete = account.categorizationSessions
        .sorted { $0.versionNumber > $1.versionNumber }
        .dropFirst(4)  // Keep active + 3 backups

    for session in toDelete {
        modelContext.delete(session)  // Cascade deletes batches, transactions
    }
}
```

## UI Flow

```
Parse Studio:
┌────────────────────────────────────┐
│ Categorization Sessions            │
│                                    │
│ 🧠 v3 [Full] ✓ Active             │ ← Green badge
│    465 rows → 237 txns             │
│    [Deactivate]                    │
│                                    │
│ 🧠 v2 [Full]                       │
│    465 rows → 235 txns             │
│    [Activate] [Delete]             │
│                                    │
│ 🧠 v1 [Full]                       │
│    465 rows → 240 txns             │
│    [Activate] [Delete]             │
└────────────────────────────────────┘

Transactions View:
Shows: account.activeTransactions
(Automatically updates when you activate different session)
```

## Implementation

```swift
// Account.swift
@Model
class Account {
    var activeCategorizationSessionId: UUID?

    var activeSession: CategorizationSession? {
        categorizationSessions.first { $0.id == activeCategorizationSessionId }
    }

    func activate(_ session: CategorizationSession) {
        activeCategorizationSessionId = session.id
    }

    func deactivate() {
        activeCategorizationSessionId = nil
    }
}

// TransactionsView.swift
struct TransactionsView: View {
    let account: Account

    private var transactions: [Transaction] {
        account.activeSession?.transactions ?? []
    }

    var body: some View {
        if let active = account.activeSession {
            Text("Showing \(transactions.count) transactions from v\(active.versionNumber)")
        } else {
            Text("No active categorization - activate a session in Parse Studio")
        }

        List(transactions) { txn in
            // ...
        }
    }
}
```

## Benefits

1. **Clear mental model:** One active version at a time
2. **Fast switching:** Just pointer flip
3. **Non-destructive:** Keep old versions
4. **Automatic updates:** All views reactive to activeSessionId
5. **Simple queries:** `account.activeSession?.transactions`
6. **Cleanup strategy:** Keep recent N versions

## Migration

**Current sessions:**
- First session auto-activated
- Or prompt user: "Activate a categorization to see transactions"

**Going forward:**
- New session created → Auto-activate
- Or: "Preview first, then activate"
