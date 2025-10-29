# Source Row Persistence

## ADDED Requirements

### Requirement: System SHALL persist every CSV row as a SourceRow entity
Every row from imported CSV files SHALL be stored as a persistent SourceRow object with full provenance.

#### Scenario: Import 100-row CSV file
- **Given** a CSV file with 100 data rows
- **When** the file is imported
- **Then** 100 SourceRow objects are created and persisted
- **And** each SourceRow links to the RawFile
- **And** each SourceRow has a unique globalRowNumber

#### Scenario: Multi-file import with overlapping row numbers
- **Given** File A with 50 rows and File B with 50 rows
- **When** both files are imported
- **Then** 100 SourceRow objects are created
- **And** globalRowNumbers are unique (1-100)
- **And** rowNumbers are per-file (1-50 for each)
- **And** each SourceRow correctly references its source file

### Requirement: SourceRow MUST store both raw and mapped CSV data
Each SourceRow MUST contain both the original CSV data and a standardized mapped representation.

#### Scenario: Store Fidelity CSV row with institution-specific fields
- **Given** a Fidelity CSV row with "Cash Balance ($)" field
- **When** SourceRow is created
- **Then** rawData contains original field names ("Cash Balance ($)")
- **And** mappedData contains standardized field (balance: 2032.69)
- **And** both are persisted in database

#### Scenario: Access mapped balance field
- **Given** a SourceRow with Cash Balance ($) = 2032.69
- **When** accessing mappedData.balance
- **Then** returns 2032.69 as Decimal
- **And** value is extracted using account's field mapping

### Requirement: SourceRow SHALL maintain provenance to source file
Every SourceRow SHALL maintain linkage to its source file and position with row numbers.

#### Scenario: Trace source row back to file
- **Given** a SourceRow with globalRowNumber 456
- **When** viewing source row details
- **Then** can see sourceFile.fileName
- **And** can see rowNumber (position in file)
- **And** can access rawFile.content
- **And** can reconstruct original CSV row
