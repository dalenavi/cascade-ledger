# Parse Plan Reform Capability

## MODIFIED Requirements

### Institution Ownership
Parse plans shall belong to institutions rather than accounts.

#### Scenario: Institution to parse plan relationship
Given Institution "Fidelity"
When viewing its configuration
Then it has multiple ParsePlans:
- "Fidelity Transactions v2" (default)
- "Fidelity Legacy Format"
- "Fidelity Custom"
And all Fidelity accounts can use any of these plans
And new Fidelity accounts default to the institution's default plan

#### Scenario: Account selects parse plan
Given an Account linked to Fidelity institution
When importing a CSV
Then:
- Account can choose from Fidelity's parse plans
- The selection is remembered for future imports
- Account can override with custom plan if needed
- The ParsePlanVersion used is recorded in ImportSession

### Parse Plan Versioning
Parse plans shall maintain immutable versions with clear commit semantics.

#### Scenario: Working copy to version commit
Given a ParsePlan with working copy modifications
When user commits the changes
Then:
- A new ParsePlanVersion is created
- Version number increments
- Working copy changes are snapshot in the version
- Commit message describes the changes
- Previous versions remain unchanged
And future imports can use any committed version

#### Scenario: Parse plan forking
Given an institution ParsePlan "Fidelity Standard"
When a user needs customization
Then they can:
- Fork the plan to create "Fidelity Custom"
- The fork copies all settings
- Modifications don't affect the original
- The fork maintains its own version history

### Agent Integration
The agent shall provide structured assistance for parse plan creation.

#### Scenario: Structured parse plan suggestions
Given a CSV sample with headers and 5 rows
When requesting agent assistance
Then the agent:
- Receives a structured prompt with expected schema
- Identifies date columns and formats
- Detects amount sign conventions
- Recognizes settlement row patterns
- Returns valid ParsePlanDefinition JSON
And the response is validated before use

#### Scenario: Agent validation of mappings
Given a ParsePlan and sample CSV data
When requesting validation
Then the agent:
- Checks if transformations produce expected output
- Identifies missing or incorrect mappings
- Suggests specific fixes
- Returns structured validation results
And errors are actionable

## REMOVED Requirements

### Direct Account-ParsePlan Association
The direct relationship between accounts and parse plans shall be removed.

#### Scenario: No direct account ownership
Given the current model where accounts own parse plans
When migrating to the new model
Then:
- ParsePlans belong to Institutions
- Accounts select from available plans
- No ParsePlan.account relationship exists
- This simplifies plan sharing and updates