# Account Management

## ADDED Requirements

### Requirement: Account Creation
The system SHALL allow users to create financial accounts tied to specific institutions.

#### Scenario: Create Fidelity Investment Account
Given a user in the app
When they create a new account named "Fidelity Investments"
Then the account is persisted with a unique ID
And the account has no assigned parser template initially

#### Scenario: Create Account During Import
Given a user uploading a CSV in Parse Studio
When no existing account matches the data
Then they can create a new account inline
And proceed with the import workflow
And the account is available for future imports

### Requirement: Institution Management
Accounts SHALL be associated with financial institutions for parser reuse.

#### Scenario: Select Known Institution
Given a user creating an account
When selecting the institution
Then they can choose from a predefined list (Fidelity, Vanguard, Chase, etc.)
Or enter a custom institution name
And the institution helps identify compatible parse plans

#### Scenario: Detect Institution from CSV
Given a CSV file being imported
When the file contains institution-specific patterns
Then the system suggests the likely institution
And the user can confirm or override
And compatible parse plans are highlighted

### Requirement: Account Parser Association
Accounts SHALL support association with a parse plan for consistent imports.

#### Scenario: Assign Parser to Account
Given an account without a parser
When a parse plan is successfully used for an import
Then the user can save that parse plan to the account
And future imports default to that parse plan

### Requirement: Multiple Import Support
Accounts SHALL support multiple independent import batches.

#### Scenario: Import Multiple Statements
Given an account with existing imports
When a user imports a new CSV file
Then the import is tracked separately with its own timestamp
And the imports can be viewed chronologically

### Requirement: Unified Transaction View
The system SHALL combine all imports for an account into a single transaction log.

#### Scenario: View Consolidated Transactions
Given an account with multiple imports
When viewing the account's transaction history
Then all transactions appear in a unified chronological list
And duplicate transactions are detected and flagged

### Requirement: Account Selection Workflow
The system SHALL provide clear workflows for selecting accounts during import.

#### Scenario: Select Existing Account
Given a user starting an import in Parse Studio
When prompted to select an account
Then they see a list of existing accounts with institution labels
And can search/filter by name or institution
And select the target account for import

#### Scenario: Quick Account Switch
Given a user in Parse Studio with an account selected
When they want to import to a different account
Then they can switch accounts via dropdown/selector
And the relevant parse plans update accordingly
And the context switches without losing work

### Requirement: Parse Plan Discovery
The system SHALL help users find compatible parse plans for their accounts.

#### Scenario: Suggest Compatible Parse Plans
Given an account from Fidelity institution
When starting a new import
Then the system shows parse plans used by other Fidelity accounts
And marks the most recently successful plan
And allows trying any compatible plan

#### Scenario: No Compatible Parse Plan
Given an account with no existing parse plans
When importing a CSV for the first time
Then Parse Studio opens with blank parse plan
And the agent offers to analyze the CSV structure
And suggests initial mapping configuration