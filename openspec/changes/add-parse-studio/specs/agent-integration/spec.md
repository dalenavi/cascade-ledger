# Agent Integration

## ADDED Requirements

### Requirement: AI-Assisted Mapping
Claude Agent SHALL suggest initial parse plans from data samples.

#### Scenario: Auto-Generate Parse Plan
Given a CSV with headers like "Trade Date", "Symbol", "Quantity"
When requesting AI assistance
Then Claude analyzes the structure and sample data
And suggests mappings to canonical schema
And the user can accept, modify, or reject suggestions

### Requirement: Error Diagnosis
Agent SHALL help identify and fix parsing failures.

#### Scenario: Fix Date Format Error
Given parse errors on date columns
When requesting agent help
Then Claude identifies the date format issue
And suggests appropriate format string
And provides a preview of the fix

### Requirement: Iterative Refinement
Agent SHALL improve parse plans based on user feedback.

#### Scenario: Refine Field Detection
Given user corrections to parsed data
When requesting agent refinement
Then Claude analyzes the corrections
And updates transform rules accordingly
And learns from patterns for future suggestions

### Requirement: Semantic Validation
Agent SHALL validate financial consistency of parsed data.

#### Scenario: Detect Inverted Signs
Given parsed transactions with negative buy amounts
When agent validates semantics
Then it detects the sign inversion issue
And suggests a transform to correct it
And explains the financial logic

### Requirement: Agent Guardrails
Agent suggestions SHALL be validated before execution.

#### Scenario: Validate Agent Suggestions
Given a Claude-generated parse plan delta
When applying to the current plan
Then the delta is validated against schema
And dry-run on sample data first
And user must approve before committing

### Requirement: Agent Chat Panel
Parse Studio SHALL provide an integrated chat panel for agent collaboration.

#### Scenario: Open Agent Chat
Given a user in Parse Studio with a CSV loaded
When they click "Ask Claude" or similar affordance
Then a chat panel appears alongside the three-pane view
And the agent has context about the loaded CSV structure

#### Scenario: Request Parse Plan Creation
Given a CSV file loaded in Parse Studio
When the user types "Create a parse plan for this Fidelity CSV"
Then the agent analyzes the CSV headers and sample data
And suggests field mappings to canonical schema
And shows the proposed parse plan configuration
And the user can approve or modify suggestions

### Requirement: Live Parse Plan Updates
The agent SHALL update the parse plan in real-time as it works.

#### Scenario: Watch Agent Work
Given an agent creating a parse plan
When the agent makes changes
Then the Parse Rules panel updates in real-time
And the Results panel shows live preview of transformations
And the user sees progress indicators for agent actions

### Requirement: Interactive Refinement
Users SHALL be able to iteratively refine parse plans with the agent.

#### Scenario: Fix Parse Errors
Given parse errors in the results
When the user asks "Why are these rows failing?"
Then the agent analyzes the errors
And suggests specific fixes
And applies approved changes to the working copy
And the preview updates immediately

### Requirement: Agent Tool Use for Data Access
The agent SHALL have tools to access input and output data.

#### Scenario: Review Input Data
Given the agent analyzing a CSV
When it needs to see specific rows
Then it can use get_csv_data tool with page parameter
And receives data in pages of 100 rows
And can request specific row ranges

#### Scenario: Review Transformed Data
Given a parse plan has been applied
When the agent needs to see transformation results
Then it uses get_transformed_data tool
And receives sample of transformed data
And can paginate through results to diagnose issues

#### Scenario: Agent Workflow
Given a new CSV import
When the agent starts working
Then it:
1. Reviews system prompt with sample data (first 10 rows)
2. Creates initial parse plan
3. Gets access to transformed data sample (first 20 rows)
4. Uses pagination tools if needed to review errors
5. Iterates on parse plan based on results