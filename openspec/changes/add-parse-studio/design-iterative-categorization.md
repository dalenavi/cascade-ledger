# Iterative Categorization UX Design

## Problem Statement

Current workflow lacks real-time learning:
- Agent categorizes all 50 transactions at once
- User corrects errors after the fact
- Corrections update prompt for NEXT time
- No learning within the current session
- Poor UX for large batches

## Proposed: Conversational Pattern-Based Categorization

### High-Level Flow

```
User selects 50 uncategorized transactions

Agent: "I'll categorize these 50 transactions.
        Let me start with a sample to learn your patterns..."

[Agent categorizes first 10]

Agent: "Here are my first 10:
        • 8 high confidence
        • 2 uncertain

        Quick scan - do these look right? Any corrections?"

User: "The ACH transfers to SMITH should be Housing: Rent, not Transfers"

Agent: "Got it! Pattern learned:
        ACH to SMITH → Housing: Rent

        Applying this to remaining 40 transactions...
        Found 5 more matching this pattern, updating them now."

[Agent recategorizes affected transactions]

Agent: "Updated! Now categorizing remaining 35 with your feedback..."
```

### Interaction Model: Conversational Corrections

**Instead of form-based editing, natural language:**

```
User: "All coffee shop transactions should be Food: Coffee"

Agent:
- Scans for "coffee" in descriptions
- Identifies 12 matching transactions
- Recategorizes them
- Updates prompt
- Replies: "✓ Recategorized 12 coffee transactions as Food: Coffee"
```

```
User: "Recurring $50 debits are gym membership, Healthcare: Fitness"

Agent:
- Finds transactions: amount=$50, type=debit, recurring pattern
- Identifies 6 matches
- Recategorizes
- Replies: "✓ Found 6 recurring $50 debits, categorized as Healthcare: Fitness"
```

### Progressive Learning Workflow

**Phase 1: Sample + Learn (10 transactions)**
```
1. Agent categorizes first 10 chronologically
2. Shows high/medium/low confidence breakdown
3. User scans, finds patterns of errors
4. User describes pattern in chat
5. Agent updates prompt + recategorizes matches
```

**Phase 2: Apply + Refine (remaining 40)**
```
6. Agent categorizes next batch with updated knowledge
7. Shows results: "35 high confidence, 5 uncertain"
8. User corrects any remaining issues via chat
9. Agent applies final refinements
```

**Result:** 90%+ accuracy by end of session, not just future sessions

### UX Components

**Agent Chat Window (persistent across all views):**
```
┌─────────────────────────────────────────┐
│ Categorization Agent          [Haiku 4.5]│
├─────────────────────────────────────────┤
│ System: Starting categorization...       │
│                                          │
│ Agent: First batch (10 transactions):    │
│        • 8 high confidence ✓             │
│        • 2 uncertain ⚠️                   │
│                                          │
│        Quick review - any patterns wrong?│
│                                          │
│ You: ACH to SMITH should be rent        │
│                                          │
│ Agent: ✓ Pattern learned! Found 5 more   │
│        matching transactions.            │
│        Recategorizing...                 │
│                                          │
│ [Type message...]              [Send]    │
└─────────────────────────────────────────┘
```

**Transaction List (shows live updates):**
```
[Tentative ✨ 85%] → [Confirmed ✓]
(updates in real-time as agent recategorizes)
```

### Implementation Approach

**1. Streaming Recategorization:**
```swift
func recategorizeByPattern(
    pattern: String,
    userInstruction: String,
    transactions: [LedgerEntry]
) async throws {
    // Agent identifies matching transactions
    // Categorizes them with pattern context
    // Updates prompt
    // Returns which transactions were updated
}
```

**2. Chat Commands:**
```
"recategorize [pattern] as [category]"
"all [description contains X] should be [category]"
"fix the ACH transfers"
"these look wrong, let me explain..."
```

**3. Real-Time Updates:**
- CategorizationAttempt status changes
- UI updates immediately
- User sees tentative → confirmed
- Or tentative → corrected

### Conversation Examples

**Example 1: Pattern Recognition**
```
You: "Saturday morning transactions under $10 are usually coffee"

Agent: [Searches transactions]
        Found 8 matching:
        - Sat Oct 5, $4.50, STARBUCKS
        - Sat Oct 12, $5.25, BLUE BOTTLE
        ...

        Categorizing as Food: Coffee?

You: "yes"

Agent: ✓ Done! Pattern added to prompt.
```

**Example 2: Batch Correction**
```
You: "All the wire transfers to LANDLORD should be rent"

Agent: Found 3 wire transfers to payees containing "LANDLORD":
        • Oct 1: $1250
        • Nov 1: $1250
        • Dec 1: $1250

        Recategorizing as Housing: Rent with tag "Rent Payment"...
        ✓ Done!
```

**Example 3: Iterative Refinement**
```
Agent: Categorized 50 transactions.
       15 marked as "Transfers" - is this correct?

You: "Most are correct, but monthly $1250 ones are rent"

Agent: Found 3 monthly $1250 transfers.
       Recategorizing as Housing: Rent...
       ✓ Updated!

       Other transfers remain as general Transfers.
```

## Recommended Implementation

**Phase 1: Conversational Commands (MVP)**
- Add natural language pattern matching
- Commands like "recategorize X as Y"
- Agent identifies matching transactions
- Updates them in real-time

**Phase 2: Progressive Categorization**
- Sample first (10 transactions)
- Get feedback
- Apply to rest with learned patterns

**Phase 3: Active Dialog**
- Agent asks clarifying questions
- Stops when uncertain
- Conversational back-and-forth

**Start with Phase 1** - gives you instant feedback on pattern corrections without rebuilding the whole system.

## Answer to Your Question

**"How could it work to get instantly more intelligent?"**

**Conversational pattern updates:**
Instead of editing each transaction, you tell the agent patterns:
- "ACH to SMITH is rent" → Agent finds and fixes all matching
- "Coffee shops are Food" → Agent finds and fixes all matching
- Prompt updates in real-time
- Remaining uncategorized get re-evaluated with new knowledge

**This makes categorizing 151 transactions manageable:**
- Identify 3-4 common patterns
- Tell agent about them
- Agent handles bulk recategorization
- You only manually fix true exceptions

**Want me to implement the conversational pattern matching?**
