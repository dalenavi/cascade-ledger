# Import Session Capability

## ADDED Requirements

### Import Session Semantics
The system shall track imports as discrete sessions with full lifecycle management.

#### Scenario: Session creation with metadata
Given a CSV file "fidelity_jan_2024.csv" with transactions from 2024-01-01 to 2024-01-31
When importing the file
Then ImportSession is created with:
- fileName: "fidelity_jan_2024.csv"
- fileHash: SHA256 of file contents
- dataStartDate: 2024-01-01
- dataEndDate: 2024-01-31
- parsePlanVersion: snapshot used for import
And all created Transactions link to this session

#### Scenario: Duplicate file detection
Given a file with SHA256 "abc123..." was previously imported
When attempting to import the same file
Then system detects duplicate via fileHash
And warns "This file was already imported on [date]"
And allows override with reason

### Session Rollback
Import sessions shall support complete rollback of all changes.

#### Scenario: Rollback import session
Given an ImportSession with 100 transactions across 5 accounts
When rollback() is called
Then all 100 transactions are deleted
And positions for all 5 accounts are recalculated
And session.status changes to .rolledBack
And audit log records the rollback with timestamp and user

#### Scenario: Cascading rollback
Given an ImportSession with transactions that have:
- Related journal entries
- Triggered position updates
- Generated categorizations
When rolling back the session
Then all related data is cleaned up
And no orphaned records remain
And positions reflect pre-import state

### Session Reprocessing
Import sessions shall support reprocessing with different parse plans.

#### Scenario: Reprocess with updated parse plan
Given an ImportSession that had 10 parsing errors
When reprocessing with an updated ParsePlan
Then:
- Original session remains unchanged
- New ImportSession is created with same source file
- Link exists between original and reprocessed sessions
- User can compare results and choose which to keep

## MODIFIED Requirements

### ImportBatch Replacement
ImportBatch shall be replaced with ImportSession throughout the system.

#### Scenario: Migration of existing imports
Given existing ImportBatch records
When migrating to ImportSession
Then:
- All ImportBatch data transfers to ImportSession
- Date ranges are inferred from associated transactions
- File hash is null for historical imports
- Rollback capability is added but marked as "legacy - use with caution"

## REMOVED Requirements

### ParseRun Concept
The separate ParseRun entity shall be removed and merged into ImportSession.

#### Scenario: Unified import tracking
Given an import operation
When processing
Then ImportSession tracks everything (no separate ParseRun)
And parsing errors are stored on ImportSession
And success/failure stats are on ImportSession
And this simplifies the model