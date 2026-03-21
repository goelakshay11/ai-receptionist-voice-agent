# Build Learnings — Naturals Salon AI Receptionist (Sagar)

A detailed record of what was built, what broke, what was learned, and why decisions were made. Written as a reference for future AI voice agent projects.

---

## Phase 1: n8n Workflow Development

### What Was Built

8 sub-workflows adapted from Nate Herk's Hercules Detailing template, plus an EOC Report workflow and an MCP Server router:

| # | Workflow | Purpose |
|---|---|---|
| 01 | Client Lookup | Identify caller by phone; return name + history |
| 02 | New Client CRM | Onboard new callers to Google Sheets |
| 03 | Check Availability | Query Google Calendar for free/busy slots |
| 04 | Book Event | Create calendar event + log + send confirmation email |
| 05 | Lookup Appointment | Retrieve existing event ID for modification |
| 06 | Update Appointment | Reschedule event + update log + send email |
| 07 | Delete Appointment | Cancel event + update log + send email |
| 08 | Pricing Info | Return static services + prices menu |
| — | EOC Report | Log call summary + outcome after every call |
| — | MCP Server | Route VAPI tool calls to sub-workflows |

### Key Adaptations from Nate's Original

- **Phone as primary identifier:** Nate's workflows use email for CRM lookup. Indian calling patterns make phone number the natural primary key. Changed all lookup queries to match on the Phone column.
- **Variable appointment duration:** Nate hardcodes 1-hour slots. Each Naturals Salon service has a different duration (20 min–95 min). The LLM calculates endTime = startTime + service duration before calling Book Event.
- **Gmail confirmation emails:** Added a Gmail node at the end of Book Event, Update Appointment, and Delete Appointment. Nate's original has no email step.
- **Pricing Info tool:** Entirely new — not present in Nate's project. Returns a static formatted menu.
- **No client calendar invite:** Nate adds the customer as an attendee on the Google Calendar event. Removed this — salon-side calendar only.

### n8n Trigger Type Learnings

n8n has two main trigger types for sub-workflows:

- **Execute Workflow Trigger** (`n8n-nodes-base.executeWorkflowTrigger`): Designed to be called by another n8n workflow using the Execute Workflow node. Not reachable by external HTTP calls.
- **Webhook Trigger** (`n8n-nodes-base.webhook`): Exposes an HTTP endpoint. Required for VAPI to call the workflow directly.

Nate's source workflows use Execute Workflow Trigger (because his MCP Server calls them internally). When switching to a webhook-based approach (Phase 4), Webhook trigger nodes had to be added to all 8 sub-workflows.

---

## Phase 2: VAPI Configuration

### Assistant Setup

- **LLM:** Claude Sonnet (via VAPI's model configuration)
- **Transcription:** Deepgram
- **Voice:** VAPI's built-in TTS
- **First message:** "Hi, I am Sagar from Naturals Salon Sarjapura. Can I get your name and mobile number please?"

### System Prompt Design Decisions

- Indian English tone — warm and professional, not overly casual
- Greeting uses "I am Sagar" not "Namaste" (avoids stereotype)
- Filler phrases before tool calls: "Ek second ruko" / "Just a moment" — gives the impression of a natural pause while n8n executes
- Strict rules added to prevent LLM hallucination and premature confirmation (more on this in Phase 6)

### Analysis Plan (End-of-Call Reporting)

VAPI's analysis plan runs after every call and extracts structured data. Configured:
- `summary`: free-text call summary
- `structuredData.Outcome`: one of "Appointment Booked", "Rescheduled", "Cancelled", "No Action"

This data is posted to the EOC Report webhook and logged in the Call Log sheet.

---

## Phase 3: MCP Approach (Failed)

### What Was Attempted

The original plan was to connect VAPI to n8n using MCP (Model Context Protocol). n8n v2.12+ ships with an MCP Server Trigger node that exposes tools over an SSE (Server-Sent Events) endpoint.

VAPI has an MCP client integration that lets you point it at an MCP endpoint URL.

The idea: one MCP Server Trigger in n8n routes all tool calls to 8 sub-workflows. VAPI connects to it via MCP. Clean architecture.

### Why It Failed

**Protocol mismatch.**

- VAPI's MCP client uses **SSE (Server-Sent Events)** transport — the original MCP transport spec
- n8n v2.12+ switched its MCP Server Trigger to **Streamable HTTP** transport — a newer spec
- These two transports are not compatible. VAPI cannot connect to n8n's MCP endpoint.

### Symptoms

- VAPI call logs showed: `llm tokens: 0`
- Calls crashed immediately after the first greeting
- No audio was processed; no tool calls were made
- No errors were visible in n8n (because VAPI never successfully connected)

### Lesson

**Always verify transport protocol compatibility before building an integration.**

When two systems both claim to "support MCP", that does not guarantee they speak the same version of the protocol. Check:
1. Which transport does the server use? (SSE vs Streamable HTTP)
2. Which transport does the client support?
3. Are there version flags or compatibility modes?

In this case, the fix was to abandon MCP entirely and use VAPI's native Function Calling with webhook-based tools instead.

---

## Phase 4: Webhook Approach (Succeeded)

### Architecture Change

Instead of one MCP endpoint routing all tools, each tool gets its own webhook URL:

```
VAPI Function Call: "clientLookup"
        │
        ▼ HTTP POST
https://{ngrok-url}/webhook/{workflowId}/client-lookup
        │
        ▼
n8n Webhook Trigger → [workflow nodes] → Respond to Webhook
```

### What Changed in n8n

- Added a Webhook trigger node to all 8 sub-workflows (and EOC Report)
- Each webhook has a unique path (e.g., `/client-lookup`, `/book-event`)
- Added a "Respond to Webhook" node at the end of each workflow

### What Changed in VAPI

- Replaced MCP tool connection with 8 individual Function tools
- Each function has a name, description, parameter schema, and a server URL pointing to the n8n webhook
- VAPI sends tool arguments in the POST body

### VAPI Tool Call Payload Structure

VAPI wraps tool arguments in a nested structure:

```json
{
  "message": {
    "toolCalls": [
      {
        "id": "call_abc123",
        "function": {
          "name": "clientLookup",
          "arguments": "{\"phone\": \"+919876543210\"}"
        }
      }
    ]
  }
}
```

Note: `arguments` is a JSON-encoded string, not a parsed object. The n8n workflow must parse it.

### VAPI Expected Response Format

VAPI requires a specific response format from tool webhooks:

```json
{
  "results": [
    {
      "toolCallId": "call_abc123",
      "result": "Client found: Akshay. Past appointments: Haircut on Jan 15."
    }
  ]
}
```

If the format is wrong or missing, VAPI ignores the tool result and the LLM may hallucinate.

---

## Phase 5: Debugging the Integration

### Bug 1: n8n Security Sandbox Blocks "arguments"

**Problem:** n8n's expression sandbox blocks the word `arguments` in Set node expressions. This is a JavaScript reserved word conflict.

**Symptom:** Set node silently returns undefined when trying to access `{{ $json.body.message.toolCalls[0].function.arguments }}`.

**Fix:** Replace Set node with a Code node:

```javascript
const toolCall = $input.first().json.body.message.toolCalls[0];
const args = JSON.parse(toolCall.function.arguments);
return [{ json: { toolCallId: toolCall.id, ...args } }];
```

### Bug 2: Wrong Webhook URL Format

**Problem:** n8n webhook URLs include the workflow ID as a prefix in some configurations:
```
/webhook/{workflowId}/webhook/{path}
```
Not just `/webhook/{path}`.

**Fix:** Copy the exact webhook URL from the Webhook node's "Test URL" or "Production URL" field in n8n UI — do not construct it manually.

### Bug 3: Google Sheets Returns Integers for Phone Numbers

**Problem:** Google Sheets stores phone numbers as numbers. n8n returns them as integers (e.g., `919876543210`), not strings. Loose string comparison (`===`) fails.

**Fix:** In the lookup Code node, convert both sides to strings before comparing:
```javascript
const sheetPhone = String(row.Phone).trim();
const inputPhone = String(phone).trim();
if (sheetPhone === inputPhone || sheetPhone.endsWith(inputPhone)) { ... }
```

Also accept 10-digit input matching the last 10 digits of a stored +91 number.

### Bug 4: Docker Restart Required After Webhook Changes

**Problem:** n8n registers webhooks at startup. If you add or modify Webhook trigger nodes while n8n is running, the new webhooks are not reachable until n8n restarts.

**Fix:** `docker compose restart n8n` after any structural webhook change.

### Bug 5: DNS Resolution Fails Inside Docker

**Problem:** Intermittently, n8n Docker container fails to resolve external hostnames (e.g., Google APIs). Manifests as timeout errors on Google Sheets / Calendar nodes.

**Fix:** `docker compose restart n8n` resolves the DNS cache issue.

### Bug 6: Check Availability Only Returned First Event

**Problem:** The Check Availability workflow was returning only the first calendar event in the window instead of all of them. VAPI's LLM could not correctly infer available slots.

**Fix:** Changed the output aggregation to collect all events and return them as a formatted list.

---

## Phase 6: Voice-Specific Challenges

### Challenge 1: Number Parsing — "Double" and "Triple"

**Problem:** In Indian English, callers say "double 7" to mean the digit 7 repeated twice (77), not the digit before it. Speech-to-text transcribes this literally.

**Fix:** Added explicit parsing rule to the system prompt:
> "double X" = XX (the digit X twice), "triple X" = XXX. Example: "double 7" = 77.

### Challenge 2: Email Address Garbling

**Problem:** Speech-to-text garbles email addresses. "akshay dot sharma at gmail dot com" becomes inconsistent transcriptions.

**Fix:** After capturing an email, Sagar spells it back to the customer letter by letter and asks for confirmation before using it.

### Challenge 3: LLM Hallucinating Appointment Slots

**Problem:** The LLM sometimes confirmed appointment times without actually calling Check Availability first, or ignored the tool's response and invented a time.

**Fix:** Added strict rules to the system prompt:
> - NEVER suggest or confirm a time slot unless Check Availability has returned it as free.
> - If Check Availability returns busy slots, explicitly list them and offer alternatives.
> - Do NOT invent availability.

### Challenge 4: LLM Auto-Confirming Without Waiting

**Problem:** The LLM would say "Great, I've booked your appointment!" before the customer confirmed. This caused double-bookings and confused customers.

**Fix:** Added explicit confirmation gate to the system prompt:
> Before calling Book Event, say: "So that's [service] on [date] at [time], correct?" and WAIT for the customer to say yes.

### Challenge 5: Filler Phrase Loops

**Problem:** The LLM repeated filler phrases multiple times ("Just a sec... just a sec... just a sec...") while waiting for a tool call to return.

**Fix:** Added rule: use ONE filler phrase per tool call, then go silent and wait for the result.

---

## Phase 7: Website Development

### Approach

Built a single-page HTML file with embedded CSS and JavaScript. No build tools, no frameworks, no npm. Deployed as a static file.

Key design elements:
- Canvas particle animation (background)
- Scroll-triggered section reveals (Intersection Observer API)
- Glass-morphism card styling
- VAPI Web SDK integration for browser-based voice calls

### VAPI Web SDK Integration

```javascript
const vapi = new Vapi(PUBLIC_KEY);
vapi.start(ASSISTANT_ID);

vapi.on('call-start', () => { /* update UI */ });
vapi.on('call-end', () => { /* update UI */ });
vapi.on('speech-start', () => { /* show speaking indicator */ });
```

The public key is safe to expose in frontend JS (it only allows starting calls, not accessing account data).

---

## Key Architectural Decisions

### Phone as Primary Identifier

Indian users are more likely to provide a mobile number than spell out an email address over the phone. Phone number is consistent, unambiguous, and already known to the caller.

Stored as 10 digits (without +91 country code) in Google Sheets to avoid format mismatch issues when callers say "nine eight seven six...".

### IST Timezone Throughout

All dates stored and displayed in IST. VAPI's system prompt uses:
```
{{ "now" | date: "%B %d, %Y, %I:%M %p", "Asia/Kolkata" }}
```

Google Calendar events are created with explicit IST offset (`+05:30`) in the ISO datetime strings passed by the LLM.

### Separate Start Time / End Time / Services Columns

Appointment Log stores start time, end time, and service name in separate columns. This makes it easy to:
- Query future appointments
- Calculate duration retrospectively
- Display readable summaries

### Comprehensive Notes Column

The Notes column in Appointment Log tracks the full lifecycle:
- Initial: "Appointment Booked"
- After reschedule: "Moved to [new time]"
- After cancellation: "Cancelled"

This gives a complete audit trail without needing a separate history table.

### EOC Report Filters Spam Events

VAPI fires multiple webhook events during a call (speech-update, transcript, etc.). The EOC Report workflow filters on `message.type === "end-of-call-report"` to avoid writing junk rows to the Call Log sheet.

### Full Call Transcript in Call Log

In addition to the structured summary and outcome, the full call transcript is logged in a separate column. Useful for debugging LLM behavior and reviewing edge cases.

---

## What I Would Do Differently

1. **Start with webhooks, not MCP.** MCP sounds elegant but protocol compatibility is a real risk. Webhooks are boring and reliable.

2. **Test tool call/response format on day 1.** The VAPI payload structure (`body.message.toolCalls[0].function.arguments`) and expected response format (`{"results": [...]}`) should be verified with a simple echo tool before building real logic.

3. **Use Code nodes instead of Set nodes for JSON parsing.** Set nodes are fine for simple field mapping but fail silently on reserved words and nested parsing. Code nodes are more explicit.

4. **Log everything during development.** Add a debug log node at the start of every workflow that writes the raw incoming payload to a sheet or sends it to a Slack channel. Saves hours of guessing what VAPI is actually sending.

5. **Build the system prompt incrementally.** Start with a minimal prompt (just greeting + one tool), test end-to-end, then add rules one at a time. A large prompt added all at once is hard to debug.

---

## Tools and Resources Used

- [Nate Herk's YouTube tutorial](https://www.youtube.com/@nateherk) — original architecture and source workflows
- [VAPI documentation](https://docs.vapi.ai) — function calling, webhook format, Web SDK
- [n8n documentation](https://docs.n8n.io) — webhook nodes, Code nodes, Google integrations
- Claude Code — workflow JSON generation, system prompt writing, website development
- ngrok — local tunnel for n8n webhooks
