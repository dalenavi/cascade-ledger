# Transaction Management

## ADDED Requirements

### Requirement: Transaction Detail View
Users SHALL be able to view complete details for any transaction.

#### Scenario: Open Transaction Details
Given a transaction in the transaction list
When the user clicks on it
Then a detail view opens
And shows all canonical fields (date, amount, description, type)
And shows all metadata fields as key-value pairs
And shows import lineage (source file, row number, parse plan version)
And shows reconciliation status

#### Scenario: View Source Data
Given a transaction detail view
When viewing lineage information
Then the user can see the original CSV row data
And can see which parse plan version was used
And can see the import batch it came from

### Requirement: Transaction Annotations
Users SHALL be able to add notes to transactions.

#### Scenario: Add Note to Transaction
Given a transaction detail view
When the user adds a note
Then the note is saved with timestamp
And the note appears in the transaction detail
And notes are searchable

#### Scenario: Edit Transaction Note
Given a transaction with an existing note
When the user edits the note
Then the updated note is saved
And edit history is preserved

### Requirement: Manual Categorization
Users SHALL be able to manually categorize transactions.

#### Scenario: Assign Category
Given a transaction without a category
When the user selects a category from a list
Then the category is saved to the transaction
And the transaction appears in category views

#### Scenario: Create Custom Category
Given a user categorizing a transaction
When they need a category that doesn't exist
Then they can create a new custom category
And the category is available for future use

### Requirement: Transaction Type Classification
The system SHALL support rich transaction type classification.

#### Scenario: Distinguish Transaction Types
Given imported transactions
When viewing the transaction list
Then transactions are clearly labeled:
- Stock Buy/Sell
- Dividends
- Interest
- Wire Transfers
- Credit Card Payments
- Salary Deposits
- Electronic Funds Transfer (EFT)
- Fees
- Tax Payments

#### Scenario: Filter by Transaction Type
Given a list of transactions
When the user filters by type
Then only transactions of that type are shown
And counts are displayed for each type

### Requirement: AI-Assisted Categorization
Claude SHALL help users categorize ambiguous transactions.

#### Scenario: Request Categorization Help
Given a transaction with unclear category
When the user asks "What category should this be?"
Then Claude analyzes:
- Transaction description
- Amount patterns
- Historical context
- Institution type
And suggests appropriate category with reasoning

#### Scenario: Batch Categorization
Given multiple similar transactions
When the user asks Claude to categorize them
Then Claude suggests categories for all
And user can review and approve in bulk

### Requirement: Smart EFT Classification
The system SHALL help identify the purpose of electronic transfers.

#### Scenario: Identify Rent Payment
Given an EFT transaction
When the description doesn't clearly indicate purpose
Then the user can add context (e.g., "Monthly rent to landlord")
And similar future transactions can be auto-categorized
And patterns are learned for suggestions

### Requirement: Trailing Field Handling
Parse plans SHALL gracefully handle CSVs with extra trailing fields.

#### Scenario: Ignore Trailing Legal Text
Given a CSV with legal disclaimer rows at the end
When parsing the file
Then non-data rows are detected and skipped
And only valid transaction rows are imported
And user is notified of skipped rows

#### Scenario: Handle Variable Column Counts
Given a CSV where some rows have more fields than headers
When parsing the file
Then extra fields are ignored
Or mapped to metadata if they contain data
And no parse errors are generated
