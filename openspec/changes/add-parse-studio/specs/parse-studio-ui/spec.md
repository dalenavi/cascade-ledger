# Parse Studio UI

## ADDED Requirements

### Requirement: Three-Panel Interface
Parse Studio SHALL provide a visual interface for data transformation.

#### Scenario: Interactive Parse Session
Given a CSV file to import
When opening Parse Studio
Then three panels display: raw data, parse rules, and results
And changes to rules immediately update the results preview

### Requirement: Account Context Bar
Parse Studio SHALL display and allow selection of the target account.

#### Scenario: Display Current Account
Given Parse Studio is open
When viewing the interface
Then the current account and institution are displayed prominently
And the user can see which account will receive the import
And the account's existing parse plans are accessible

#### Scenario: Change Account In Studio
Given a user working in Parse Studio
When they need to switch accounts
Then they can select a different account from a dropdown
Or create a new account without leaving Parse Studio
And the parse plan suggestions update for the new account

### Requirement: Live Preview
Rule changes SHALL trigger immediate recomputation.

#### Scenario: Modify Field Mapping
Given a parse plan mapping "Amount" to "quantity"
When changing the mapping to "amount"
Then the results panel updates within 500ms
And only affected columns recompute

### Requirement: Error Highlighting
Parse failures SHALL be visually indicated.

#### Scenario: Show Parse Errors
Given rows that fail validation
When viewing the results panel
Then failed rows are highlighted in red
And hovering shows the specific error message
And clicking navigates to the source row

### Requirement: Sample-Based Preview
Live preview SHALL use a data sample for performance.

#### Scenario: Preview Large File
Given a CSV with 50,000 rows
When editing parse rules
Then preview shows first 100 rows
And full import processes all rows

### Requirement: Parse Plan Persistence
Users SHALL be able to save successful parse plans.

#### Scenario: Save Parse Configuration
Given a working parse plan in the editor
When user clicks "Save Parse Plan"
Then the plan is versioned and stored
And associated with the current account
And available for future imports

### Requirement: Agent Chat Interface
Parse Studio SHALL include an interactive chat interface for agent collaboration.

#### Scenario: Chat With Parse Agent
Given a user working in Parse Studio
When they open the chat panel
Then they can type natural language requests
And see agent responses and suggestions
And view a log of all agent actions on the parse plan

#### Scenario: Apply Agent Suggestion
Given an agent suggestion in the chat
When the user approves the suggestion
Then the working parse plan is updated (not versioned)
And the changes are reflected in live preview
And the action is logged in the chat history

### Requirement: Commit-Based Versioning
Parse plan changes SHALL remain in working state until explicitly committed.

#### Scenario: Work With Draft Changes
Given multiple edits to a parse plan
When making changes without committing
Then changes apply to the working copy only
And no new version is created
And preview shows results with working changes

#### Scenario: Commit Parse Plan Version
Given a working parse plan with changes
When user clicks "Commit Parse Plan"
Then a new version is created with unique ID
And the version becomes immutable
And data can now be persisted with this version reference

### Requirement: CSV Table View
Raw data panel SHALL support both text and table view modes.

#### Scenario: Switch to Table View
Given a CSV file loaded
When user selects "Table" tab
Then data displays in a grid with columns
And headers are shown
And data is scrollable horizontally and vertically

#### Scenario: Switch to Raw View
Given a CSV file in table view
When user selects "Raw" tab
Then data displays as plain text
And preserves original formatting

### Requirement: Agent Chat Persistence
Agent chat SHALL minimize to a button and remain accessible.

#### Scenario: Minimize Chat Window
Given an open agent chat window
When user closes the chat
Then the window minimizes to a button labeled "Agent"
And the button appears in bottom-right corner
And chat history is preserved

#### Scenario: Reopen Chat
Given a minimized agent chat
When user clicks the "Agent" button
Then the chat window reopens
And previous conversation is visible
And user can continue the conversation

### Requirement: Draggable Chat Window
The agent chat window SHALL be repositionable.

#### Scenario: Drag Chat Window
Given an open chat window
When user drags the window header
Then the window moves with the cursor
And stays within the Parse Studio bounds
And position is remembered during session

### Requirement: Complete Results Display
Results panel SHALL show all parsed data, not just samples.

#### Scenario: View All Results
Given a CSV with 1000 rows
When parse preview is generated
Then all 1000 rows are available for viewing
And results are paginated or virtualized for performance
And user can scroll through all data

### Requirement: Field Extensibility
The system SHALL support custom metadata fields beyond canonical schema.

#### Scenario: Custom Field Mapping
Given a CSV with institution-specific columns
When creating a parse plan
Then custom fields can be mapped to transaction metadata
And metadata is preserved as key-value pairs
And metadata fields are searchable