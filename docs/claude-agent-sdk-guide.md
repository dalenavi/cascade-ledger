# Guide: Using the Claude Agent SDK

This guide covers how to install, configure, and build agents using the **Claude Agent SDK** (Anthropic). It is suitable for developers building autonomous or tool-using agents in **Python** or **TypeScript/JavaScript**.

---

## 1. Overview

The **Claude Agent SDK** allows you to build agents that can:

- Use custom tools or APIs.
- Maintain state across tasks.
- Interact with files, codebases, or structured environments.
- Operate autonomously under guardrails.

The SDK is inspired by the internal framework that powers **Claude Code**.

---

## 2. Installation

### Python
```bash
pip install claude-agent-sdk
```

### JavaScript / TypeScript
```bash
npm install @anthropic-ai/claude-agent-sdk
```

---

## 3. Core Concepts

| Concept | Description |
|----------|--------------|
| **Agent** | The autonomous entity (Claude model) that can reason and act. |
| **Tool** | A function the agent can call to perform an action (API call, file op, computation). |
| **Session** | Context of interaction, allowing persistence and branching. |
| **Permissions** | Guardrails for tool usage and file access. |
| **Subagents / Hooks** | Mechanisms for delegation and custom behavior. |

---

## 4. Basic Python Example

```python
from claude_agent_sdk import Agent, Tool

# Define a custom tool
def get_weather(city: str) -> str:
    return f"The weather in {city} is sunny."

# Register tool
weather_tool = Tool.from_function(get_weather)

# Create agent
agent = Agent(model="claude-3.5-sonnet", tools=[weather_tool])

# Run the agent
response = agent.run("What's the weather in Paris?")
print(response.output)
```

---

## 5. Basic TypeScript Example

```typescript
import { Agent, Tool } from "@anthropic-ai/claude-agent-sdk";

// Define a tool
const getWeather = new Tool({
  name: "get_weather",
  description: "Get current weather by city name.",
  function: async ({ city }) => `The weather in ${city} is sunny.`
});

// Create the agent
const agent = new Agent({
  model: "claude-3.5-sonnet",
  tools: [getWeather]
});

// Run the agent
const result = await agent.run("What's the weather in Paris?");
console.log(result.output);
```

---

## 6. Using Sessions

Agents can maintain conversational or contextual state using sessions:

```python
session = agent.create_session(name="weather_bot")
session.run("What's the weather in London?")
session.run("And in Berlin?")
```

---

## 7. Permissions & Security

Each tool or environment access can have explicit permission scopes.  
For example, tools that modify files or run commands require explicit declaration in the agent config.

```python
agent = Agent(
    model="claude-3.5-sonnet",
    tools=[weather_tool],
    permissions=["read:files", "write:logs"]
)
```

---

## 8. Subagents & Delegation

Claude supports hierarchical delegation via subagents or hooks.

Example:
```python
subagent = Agent(model="claude-3.5-haiku", purpose="quick fact-checking")
main_agent = Agent(model="claude-3.5-sonnet", subagents=[subagent])
```

---

## 9. Tool Composition Example

```python
from claude_agent_sdk import Agent, Tool
import requests

def search(query: str):
    return requests.get("https://api.duckduckgo.com", params={"q": query, "format": "json"}).json()

search_tool = Tool.from_function(search)

agent = Agent(model="claude-3.5-sonnet", tools=[search_tool])
response = agent.run("Search the web for 'Claude Agent SDK examples'")
print(response.output)
```

---

## 10. Tips & Best Practices

1. **Use guardrails** – explicitly limit tool permissions.  
2. **Structure tools modularly** – each tool should do one thing.  
3. **Handle context size** – watch token limits; persist context externally if needed.  
4. **Observe logs** – the SDK provides structured logs for debugging tool calls.  
5. **Version tools** – clearly define input/output schemas to prevent breakage.  

---

## 11. Resources

- [Official Anthropic Agent SDK Docs](https://anthropic.mintlify.app/en/docs/claude-code/sdk)
- [Anthropic Blog: Claude Agent SDK Overview](https://www.anthropic.com/news/enabling-claude-code-to-work-more-autonomously)
- [Python SDK Package](https://pypi.org/project/claude-agent-sdk/)
- [JS SDK Package](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk)

---

© 2025 Anthropic / Guide written by ChatGPT (GPT-5)
