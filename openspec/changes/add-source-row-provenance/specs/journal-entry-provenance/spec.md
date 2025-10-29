# Journal Entry Provenance

## ADDED Requirements

### Requirement: Journal entries SHALL link to source rows
Every journal entry SHALL maintain many-to-many linkage to the source CSV rows it was derived from.

#### Scenario: Journal entry derived from single source row
- **Given** a journal entry for "DR: SPY $2,019.24"
- **When** entry is created from CSV row #455
- **Then** entry.sourceRows contains SourceRow #455
- **And** can navigate from entry to source row
- **And** can view original CSV data

#### Scenario: Journal entry derived from multiple source rows
- **Given** a combined transaction using rows #441, #442, #443
- **When** journal entry is created
- **Then** entry.sourceRows contains all three SourceRows
- **And** can trace entry back to all source rows
- **And** validates against sum of row amounts

#### Scenario: Source row used by multiple journal entries
- **Given** row #456 with balance information
- **When** referenced by multiple transactions (incorrect categorization)
- **Then** sourceRow.journalEntries shows all usages
- **And** can detect duplicate usage
- **And** can flag as over-grouping error

### Requirement: System SHALL validate journal entry amounts against CSV
Every journal entry amount SHALL be validated against the corresponding source row amount.

#### Scenario: Journal entry amount matches CSV
- **Given** journal entry "DR: Cash $2,032.69" from row #456
- **When** row #456 has Amount ($) = 2032.69
- **Then** entry.csvAmount = 2032.69
- **And** entry.amountDiscrepancy = 0
- **And** validation passes ✓

#### Scenario: Journal entry amount mismatches CSV
- **Given** journal entry "DR: SPY $2,019.24"
- **When** linked to row #456 (Amount = $2,032.69)
- **Then** entry.csvAmount = 2032.69
- **And** entry.amountDiscrepancy = -13.45
- **And** entry is flagged for review
- **And** indicates probable over-grouping

#### Scenario: Detect over-grouped transaction
- **Given** transaction using rows [#455, #456]
- **When** row #455 has Amount $2,019.24
- **And** row #456 has Amount $2,032.69
- **And** transaction only has entries totaling $2,019.24
- **Then** amount validation fails
- **And** transaction is flagged as over-grouped
- **And** suggests splitting into separate transactions

### Requirement: Journal entries MUST store expected CSV amount
Journal entries MUST record the expected CSV amount for validation purposes.

#### Scenario: Store CSV amount on creation
- **Given** AI categorization response with csvAmount per entry
- **When** journal entry is created
- **Then** entry.csvAmount is populated from response
- **And** entry.csvAmount persisted in database
- **And** can compare entry.amount vs entry.csvAmount
