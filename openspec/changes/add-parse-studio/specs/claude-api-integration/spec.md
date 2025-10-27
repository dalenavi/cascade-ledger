# Claude API Integration

## ADDED Requirements

### Requirement: API Key Management
The system SHALL securely store and manage Claude API keys.

#### Scenario: Configure API Key
Given a user without a configured API key
When they open Settings or Parse Studio
Then they are prompted to enter an Anthropic API key
And the key is stored securely in the system Keychain
And the key is validated before saving

#### Scenario: Validate API Key
Given a user entering an API key
When they save the key
Then the system makes a test API call to Claude
And displays success or error message
And only saves valid keys

#### Scenario: Update API Key
Given a user with an existing API key
When they want to change it
Then they can access Settings → API Keys
And enter a new key
And the old key is replaced securely

#### Scenario: Remove API Key
Given a user wanting to remove their API key
When they delete it from settings
Then the key is removed from Keychain
And the user is notified that agent features are disabled

### Requirement: Claude API Connection
Parse Studio SHALL connect to Claude API using Haiku 4.5 model.

#### Scenario: Initialize Claude Client
Given a valid API key in Keychain
When Parse Studio loads
Then a Claude API client is initialized
And uses claude-haiku-4.5-20250929 model
And is ready to handle requests

#### Scenario: Handle API Errors
Given a Claude API request
When the API returns an error
Then the error is displayed to the user
And the chat shows helpful error messages
And the user can retry or check their API key

### Requirement: Agent System Prompt
The agent SHALL receive structured context about the parse task.

#### Scenario: Provide Parse Context
Given a CSV file loaded in Parse Studio
When the agent chat is opened
Then the agent receives a system prompt containing:
- CSV file structure (headers, sample data)
- Account and institution information
- Frictionless Data standards documentation
- ParsePlan schema structure
- Available canonical ledger fields
- JSONata transformation syntax

#### Scenario: Maintain Conversation Context
Given an ongoing agent conversation
When the user sends a message
Then the full conversation history is sent
And the current parse plan state is included
And the agent can reference previous suggestions

### Requirement: Parse Plan Manipulation
The agent SHALL be able to create and modify parse plans through structured responses.

#### Scenario: Agent Creates Parse Plan
Given the agent analyzing a CSV
When it determines appropriate field mappings
Then it returns a structured ParsePlanDefinition JSON
And the system applies it to the working copy
And the live preview updates immediately

#### Scenario: Agent Modifies Parse Plan
Given an existing parse plan
When the user asks for changes
Then the agent returns a delta/patch
And the system applies changes to working copy
And validation runs before applying

### Requirement: Streaming Responses
The agent SHALL stream responses for better UX.

#### Scenario: Stream Agent Response
Given the agent processing a request
When generating a response
Then the response streams word-by-word
And the chat UI updates in real-time
And the user sees progress immediately

### Requirement: Rate Limiting and Cost Control
The system SHALL manage API usage appropriately.

#### Scenario: Track Token Usage
Given agent interactions
When API calls are made
Then token usage is tracked
And displayed to the user
And warnings shown for high usage

#### Scenario: Limit Request Size
Given a large CSV file
When providing context to the agent
Then only sample data is sent (first 100 rows)
And file size is checked before sending
And user is warned if context will be expensive

### Requirement: Offline Graceful Degradation
The system SHALL handle missing API key or network issues.

#### Scenario: No API Key Configured
Given a user without an API key
When they try to use agent features
Then they see a clear prompt to configure API key
And are directed to settings
And the UI remains functional for manual parse plan editing

#### Scenario: Network Failure
Given a network connection issue
When the agent is invoked
Then an appropriate error message is shown
And the user can retry
And local data is not lost
