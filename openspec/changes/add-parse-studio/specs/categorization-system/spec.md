# AI-Driven Categorization System

## ADDED Requirements

### Requirement: Categorization Prompt Management
The system SHALL maintain categorization prompts at global and account levels.

#### Scenario: Global Prompt
Given the categorization system
When initialized
Then a global prompt exists with universal rules
And the prompt contains patterns like "Dividends → Income: Dividend"
And the prompt is used for all accounts

#### Scenario: Account-Specific Prompt
Given an account
When categorization rules are learned
Then an account-specific prompt is created
And contains patterns specific to that account's usage
And is combined with global prompt during categorization

### Requirement: Agent Categorization
Claude SHALL categorize transactions with confidence scoring.

#### Scenario: Batch Categorization Request
Given uncategorized transactions
When user requests "Categorize my transactions"
Then Claude processes each transaction individually
And creates CategorizationAttempt for each
And assigns confidence score (0-1) per transaction
And proposals are marked as tentative

#### Scenario: Auto-Apply High Confidence
Given a categorization with confidence >= 0.9
When the attempt is created
Then the status is set to applied
And the transaction is updated immediately
And the attempt is still tracked for potential correction

#### Scenario: Tentative Low Confidence
Given a categorization with confidence < 0.9
When the attempt is created
Then the status is tentative
And the transaction is NOT updated
And user must review before applying

### Requirement: Bulk Review Interface
Users SHALL review categorization proposals in a scannable list.

#### Scenario: Display All Proposals
Given 15 categorization attempts
When user opens review interface
Then all attempts are displayed in a list
And each shows: transaction summary, proposed category/tags, confidence
And each has a checkbox (checked by default)
And each has an Edit button

#### Scenario: Selective Approval
Given the proposal list
When user scans and finds errors
Then user unchecks incorrect proposals
And clicks Edit to correct them
And clicks "Apply Checked" to apply the rest
And only checked proposals are applied

#### Scenario: Correct Individual Categorization
Given a categorization proposal
When user clicks Edit
Then a form shows proposed vs actual fields
And user can set correct category and tags
And user can choose "Update Prompt" or "Just fix this one"
And correction is saved as CategorizationAttempt with status=corrected

### Requirement: Prompt Learning from Corrections
The system SHALL refine prompts based on user corrections.

#### Scenario: Learn from Single Correction
Given a corrected categorization attempt
When user chooses "Update Prompt"
Then the system analyzes: proposed vs actual
And generates a concise pattern description
And appends to appropriate prompt (account or global)
And keeps prompt parsimonious

#### Scenario: Learn from Multiple Corrections
Given multiple corrections in a batch
When user completes review
Then the system distills common patterns
And updates prompt with consolidated learnings
And removes redundant or conflicting patterns

#### Scenario: Prompt Refinement
Given an existing prompt with learned patterns
When new corrections contradict old patterns
Then the system reconciles the conflict
And updates the prompt to be more specific
And maintains prompt clarity and brevity

### Requirement: Tentative State Display
Transactions SHALL visually indicate tentative categorizations.

#### Scenario: Show Tentative Badge
Given a transaction with tentative categorization
When displayed in transaction list
Then it shows a badge indicating "Proposed" or similar
And the category/tags are visible but marked as unconfirmed
And user can click to review

#### Scenario: Clear Tentative State
Given a transaction with tentative categorization
When user applies the categorization
Then the tentative badge is removed
And the categorization becomes permanent
And the attempt status changes to applied

### Requirement: Confidence-Based Behavior
The system SHALL use confidence levels to determine auto-apply thresholds.

#### Scenario: Configure Confidence Threshold
Given the categorization system
When processing attempts
Then confidence >= 0.9 auto-applies
And confidence 0.5-0.9 marks as tentative
And confidence < 0.5 may skip or flag for manual review

#### Scenario: Display Confidence
Given a categorization attempt
When shown to user
Then confidence is displayed as percentage
And color-coded: green (>90%), yellow (50-90%), red (<50%)

### Requirement: Prompt Viewing and Editing
Users SHALL be able to view and edit categorization prompts.

#### Scenario: View Account Prompt
Given an account with learned patterns
When user navigates to Settings → Categorization
Then account-specific prompt is displayed
And shows learned patterns with timestamps
And shows success/correction counts

#### Scenario: Manual Prompt Edit
Given a categorization prompt
When user edits it directly
Then changes are saved
And version number increments
And next categorization uses updated prompt

### Requirement: CSV Field Preservation
Raw CSV values SHALL be preserved for all classification fields.

#### Scenario: Preserve Raw Type
Given a CSV with "Type" column
When importing
Then rawTransactionType stores the CSV value
And transactionType stores the interpreted enum
And user can see both in transaction detail

#### Scenario: Type Override
Given a transaction with incorrect type
When user changes the type
Then userTransactionType stores the override
And effectiveTransactionType returns the override
And rawTransactionType remains unchanged for audit
