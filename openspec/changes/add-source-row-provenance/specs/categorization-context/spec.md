# Categorization Context

## ADDED Requirements

### Requirement: Accounts SHALL store categorization context
Each account SHALL maintain a persistent categorization context that informs AI how to categorize transactions for that specific account.

#### Scenario: Add categorization rule after discovering error
- **Given** transaction incorrectly grouped rows #455-456
- **When** user adds context: "Row #456 is always a separate funding transaction"
- **Then** context is appended to account.categorizationContext
- **And** context is persisted in database
- **And** future categorizations use this context

#### Scenario: Inject context into AI categorization prompt
- **Given** account with categorization context about dual-row patterns
- **When** running AI categorization
- **Then** context is injected into AI prompt
- **And** AI follows account-specific rules
- **And** categorization quality improves

### Requirement: System SHALL learn from categorization corrections
When user corrects categorization errors, system SHALL suggest context updates based on the correction pattern.

#### Scenario: Learn from transaction split
- **Given** over-grouped transaction using rows [#455, #456]
- **When** user splits into two transactions
- **Then** system suggests context update
- **And** user reviews suggested update
- **And** context is updated with pattern
- **And** similar transactions are categorized correctly

#### Scenario: View categorization context history
- **Given** account with multiple context updates
- **When** viewing categorization context
- **Then** can see all historical updates
- **And** can see when each was added
- **And** can see impact on categorization accuracy

### Requirement: Categorization context MUST be human-readable
Context MUST be clear, concise instructions that both humans and AI can understand.

#### Scenario: Format context for readability
- **Given** multiple categorization rules
- **When** viewing context
- **Then** formatted as bullet points
- **And** each rule is on separate line
- **And** rules are dated or versioned
- **And** can be edited as plain text
