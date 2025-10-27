# Parse Engine

## ADDED Requirements

### Requirement: Parse Plan Creation
Parse plans SHALL define how to transform raw data to canonical schema.

#### Scenario: Define Parse Rules
Given a CSV with specific column structure
When creating a parse plan
Then the plan specifies dialect (delimiter, encoding)
And field mappings to canonical schema
And transformation rules using JSONata/JOLT

### Requirement: Parse Plan Versioning
Parse plans SHALL maintain version history with lineage through explicit commits.

#### Scenario: Update Parse Plan
Given an existing parse plan v1
When modifications are made to improve parsing
Then changes remain in a working copy
And a new version v2 is created only on commit
And v2 references v1 as parent
And existing imports retain their original version

#### Scenario: Working Copy Management
Given a parse plan being edited
When changes are made without committing
Then a working copy maintains all modifications
And preview operations use the working copy
And no version number is assigned until commit

### Requirement: Frictionless Standards Support
Parse plans SHALL use Frictionless Data specifications.

#### Scenario: Configure CSV Dialect
Given a CSV with semicolon delimiters and ISO-8859-1 encoding
When defining the parse plan
Then Frictionless Table Dialect captures these settings
And the parser correctly reads the file structure

### Requirement: Transform Execution
The system SHALL execute JSONata/JOLT transforms to convert data to canonical format.

#### Scenario: Transform Transaction Fields
Given raw CSV with "Trade Date" and "Quantity" columns
When applying JSONata transform
Then fields map to canonical "date" and "quantity"
And data types are converted appropriately

### Requirement: Validation Rules
Parse plans SHALL include validation to ensure data quality.

#### Scenario: Validate Required Fields
Given a parse plan with date and amount as required
When processing rows missing these fields
Then validation errors are generated
And the specific failures are reported

### Requirement: Lineage Tracking
The system SHALL track lineage so each output row traces back to its source.

#### Scenario: Trace Transaction Origin
Given a ledger entry from an import
When inspecting its lineage
Then the source file, row number, and transform are visible
And the original raw data can be retrieved