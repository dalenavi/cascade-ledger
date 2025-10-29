# CSV Field Mapping

## ADDED Requirements

### Requirement: Accounts SHALL support CSV field mapping configuration
Each account SHALL have configurable field mapping to handle institution-specific CSV formats.

#### Scenario: Configure Fidelity field mapping
- **Given** a Fidelity brokerage account
- **When** setting up CSV field mapping
- **Then** can configure balanceField = "Cash Balance ($)"
- **And** can configure amountField = "Amount ($)"
- **And** mapping is persisted with account
- **And** mapping is used for all imports to this account

#### Scenario: Use different CSV formats for different accounts
- **Given** Account A (Fidelity) with balanceField = "Cash Balance ($)"
- **And** Account B (Generic Bank) with balanceField = "Balance"
- **When** importing CSVs to each account
- **Then** each uses its own field mapping
- **And** both extract balance correctly

### Requirement: System SHALL auto-detect CSV field names from headers
System SHALL automatically detect field mapping from CSV headers on first import.

#### Scenario: Auto-detect Fidelity CSV format
- **Given** CSV with headers including "Cash Balance ($)"
- **When** importing to new account
- **Then** auto-detects balanceField = "Cash Balance ($)"
- **And** auto-detects other standard fields
- **And** suggests detected mapping to user
- **And** user can approve or modify

#### Scenario: Auto-detect with multiple balance field candidates
- **Given** CSV with both "Balance" and "Ending Balance" columns
- **When** auto-detecting field mapping
- **Then** chooses most specific match ("Ending Balance")
- **And** provides confidence score
- **And** allows user to override choice

### Requirement: System SHALL map CSV rows to standardized structure
Every CSV row SHALL be transformed into a standardized MappedRowData structure regardless of source format.

#### Scenario: Map Fidelity row to standard format
- **Given** CSV row: {"Cash Balance ($)": "2032.69", "Amount ($)": "2019.24", "Run Date": "04/23/2024"}
- **When** applying Fidelity field mapping
- **Then** MappedRowData has balance = 2032.69
- **And** MappedRowData has amount = 2019.24
- **And** MappedRowData has date = 2024-04-23
- **And** all amounts are Decimal type (not strings)

#### Scenario: Handle missing optional fields
- **Given** CSV row without "Settlement Date" field
- **When** mapping to MappedRowData
- **Then** MappedRowData.settlementDate = nil
- **And** mapping succeeds without errors
- **And** other fields are populated correctly
