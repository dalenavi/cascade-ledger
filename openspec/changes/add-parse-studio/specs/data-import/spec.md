# Data Import

## ADDED Requirements

### Requirement: CSV File Upload
The system SHALL allow users to upload CSV files from financial institutions.

#### Scenario: Upload Bank Statement
Given a user with a CSV export from their bank
When they select and upload the file
Then the raw file is stored with SHA256 checksum
And the file content is preserved immutably

### Requirement: Raw Data Persistence
The system SHALL store all uploaded files permanently for audit trail.

#### Scenario: Retrieve Original Import
Given a previously imported file
When viewing import history
Then the original raw file can be accessed
And its checksum verifies integrity

### Requirement: Import Batch Tracking
The system SHALL create a tracked batch for each import operation.

#### Scenario: Track Import Session
Given a new CSV upload
When starting the parse process
Then an ImportBatch is created with timestamp
And it links the raw file, account, and parse plan version

### Requirement: Partial Import Success
The system SHALL support partial import success with error reporting.

#### Scenario: Import With Some Invalid Rows
Given a CSV with 100 rows where 5 have parsing errors
When processing the import
Then 95 valid rows are imported successfully
And 5 failed rows are flagged with error details
And the user can review and fix failed rows

### Requirement: Commit-Required Persistence
Parsed data SHALL only be persisted after the parse plan is committed.

#### Scenario: Persist After Commit
Given successfully parsed data in preview
When the user commits the parse plan
Then a new parse plan version is created
And the parsed data is persisted with version reference
And the import batch records the specific version used

#### Scenario: Preview Without Persistence
Given a working parse plan with successful preview
When the parse plan is not yet committed
Then parsed data remains in preview only
And no ledger entries are created
And the user must commit before final import

### Requirement: Commit Parse Plan
Users SHALL explicitly commit parse plans before importing data.

#### Scenario: Commit Working Copy
Given a parse plan with field mappings in working copy
When the user clicks "Commit Parse Plan"
Then the user can enter an optional commit message
And a new immutable version is created
And the version number increments
And the "Import Data" button becomes enabled

#### Scenario: Prevent Import Without Commit
Given a parse plan that hasn't been committed
When viewing the preview
Then the "Import Data" button is disabled
And a message explains commit is required

### Requirement: Full Data Import
Users SHALL execute full imports after committing parse plans.

#### Scenario: Execute Full Import
Given a committed parse plan version
When the user clicks "Import Data"
Then the full CSV is processed (not just preview sample)
And all rows are transformed using the committed version
And ledger entries are created for valid rows
And progress is displayed during import
And import batch is updated with final statistics

#### Scenario: Import Progress Display
Given a large CSV import in progress
When rows are being processed
Then a progress bar shows percentage complete
And current row count is displayed
And estimated time remaining is shown
And user can cancel if needed

#### Scenario: Import Completion
Given a completed import
When all rows are processed
Then success message shows final statistics
And user can view imported transactions
And import appears in history
And duplicate detection results are shown