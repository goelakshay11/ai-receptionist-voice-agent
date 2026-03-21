# CLAUDE.md — Naturals Salon AI Receptionist (Sagar)

> This file gives Claude Code full project context. Read it at the start of every session.
> Do NOT start building anything without reading this file first.

---

## Project Overview

Building **"Sagar"** — an AI voice receptionist for **Naturals Salon, Sarjapura, Bangalore**.
Sagar handles inbound calls and manages appointments for men's grooming services only.

**Inspired by:** Nate Herk's "Build Your Own AI Receptionist with VAPI and n8n" tutorial.
**Purpose:** Personal learning project (AI PM skill-building). Not for production/wide use.
**Scope:** Booking, rescheduling, cancellation, and pricing FAQ only. No sales handoff. No customer support handoff.

---

## Tech Stack

| Layer | Tool | Purpose |
|---|---|---|
| Voice Brain | VAPI (cloud) | Voice synthesis, conversation, LLM decision-making |
| Tool Brain | n8n (self-hosted) | MCP Server + 8 sub-workflows as tools |
| CRM Database | Google Sheets | Clients tab, Appointment Log tab, Call Log tab |
| Scheduling | Google Calendar | Salon-side calendar only (no client invites) |
| Email Confirmations | Gmail (via n8n) | Sends booking/reschedule/cancel emails to client |
| LLM Model | Claude (via VAPI) | Sagar's reasoning engine |

**n8n instance URL:** `https://YOUR_NGROK_DOMAIN.ngrok-free.dev`
**MCP SSE URL pattern:** `https://YOUR_NGROK_DOMAIN.ngrok-free.dev/mcp/[webhook-id]/sse`
(Get the exact webhook-id from the MCP Server Trigger node after activation)

---

## Business Context

**Salon:** Naturals Salon — Sarjapura location only, Bangalore, India
**Assistant Name:** Sagar
**Timezone:** Asia/Kolkata (IST, UTC+5:30)
**Operating Hours:** Monday – Saturday, 10:00 AM – 9:00 PM IST
**Last bookable slot start time:** 8:00 PM IST (so the latest appointment ends by ~9 PM)
**Closed:** Sundays

---

## Services & Pricing (Mock Data)

| Service | Price (INR) | Duration | Notes |
|---|---|---|---|
| Haircut | ₹300 | 45 min | Standard men's cut |
| Beard Trim | ₹150 | 20 min | Trim and shape |
| Haircut + Beard | ₹400 | 65 min | Combined package |
| Head Massage | ₹200 | 30 min | Relaxing scalp massage |
| Face Cleanup | ₹250 | 30 min | Basic face treatment |
| Haircut + Head Massage | ₹500 | 75 min | Popular combo |
| Full Grooming (Haircut + Beard + Head Massage) | ₹600 | 95 min | Premium package |

**Appointment duration is variable** — always calculate end time from start time + service duration.
Never hardcode 1 hour. Sagar must ask which service before checking/booking availability.

---

## Client Data Model

**Primary identifier:** Mobile phone number (not email)
**CRM lookup:** By phone number

### Google Sheets Structure

**Tab 1: Clients**
| Column | Notes |
|---|---|
| Phone | Primary key, e.g. +91XXXXXXXXXX |
| Name | First name or full name |
| Email | For sending confirmation emails |

**Tab 2: Appointment Log**
| Column | Notes |
|---|---|
| ID | Google Calendar Event ID |
| Phone | Client phone number |
| Email | Client email |
| Appointment Type | Service name (e.g. "Haircut + Beard") |
| Date | ISO datetime of appointment start |
| Notes | "Appointment Booked" / "Moved to [new time]" / "Cancelled" |

**Tab 3: Call Log**
| Column | Notes |
|---|---|
| Date | Timestamp of call |
| Summary | Auto-generated call summary from VAPI EOC report |
| Outcome | e.g. "Appointment Booked", "Rescheduled", "No Action" |

---

## n8n Architecture

### Overview

One **MCP Server Trigger** acts as the router. VAPI calls it, and it routes to 8 sub-workflows.
There is also one separate **EOC (End of Call) Webhook** workflow (not an MCP tool).

```
VAPI ──MCP──► n8n MCP Server Trigger
                    ├── Tool 1: Client Lookup
                    ├── Tool 2: New Client CRM
                    ├── Tool 3: Check Availability
                    ├── Tool 4: Book Event
                    ├── Tool 5: Lookup Appointment
                    ├── Tool 6: Update Appointment
                    ├── Tool 7: Delete Appointment
                    └── Tool 8: Pricing Info

VAPI ──POST Webhook──► n8n EOC Report (after call ends)
```

---

## Tool Specifications

### Tool 1: Client Lookup
- **Purpose:** Identify if caller is new or returning client
- **Input:** `phone` (string, e.g. "+919876543210")
- **Process:**
  1. Search "Clients" tab in Google Sheets for matching phone number
  2. If found: check "Appointment Log" for past appointments
  3. Return: client exists + name + appointment history, OR "new client"
- **Source file:** `n8n-workflows/source/Client Lookup.json`
- **Key adaptation from Nate's:** Replace `email` lookup with `phone` lookup

### Tool 2: New Client CRM
- **Purpose:** Onboard a new client
- **Inputs:** `phone` (string), `name` (string), `email` (string)
- **Process:** Append new row to "Clients" tab in Google Sheets
- **Source file:** `n8n-workflows/source/New Client CRM.json`
- **Key adaptation from Nate's:** Add `email` field; use `phone` as primary identifier instead of `email`

### Tool 3: Check Availability
- **Purpose:** Find free slots on the salon's Google Calendar
- **Inputs:** `afterTime` (ISO datetime), `beforeTime` (ISO datetime)
- **Process:**
  1. Query Google Calendar for events between afterTime and beforeTime
  2. If no events: return "entire window is available"
  3. If events found: return busy slots (VAPI infers free slots from this)
- **Source file:** `n8n-workflows/source/Check Availability.json`
- **Key adaptation from Nate's:** None — logic is identical

### Tool 4: Book Event
- **Purpose:** Create an appointment on the salon's Google Calendar + send confirmation email
- **Inputs:** `startTime` (ISO datetime), `endTime` (ISO datetime), `phone` (string), `email` (string), `eventSummary` (service name, e.g. "Haircut + Beard — Naturals Salon")
- **Process:**
  1. Create Google Calendar event (salon calendar only, no client attendee)
  2. Append row to "Appointment Log" in Google Sheets with event ID
  3. Send Gmail confirmation email to client's email address
- **Source file:** `n8n-workflows/source/Book Event.json`
- **Key adaptations from Nate's:**
  - Replace email identifier with phone
  - Remove client attendee from calendar invite
  - Add Gmail node at end to send confirmation email
  - endTime is calculated by Sagar based on service duration (not hardcoded +1 hour)

**Confirmation email template:**
```
Subject: Appointment Confirmed — Naturals Salon Sarjapura

Hi [Name],

Your appointment at Naturals Salon, Sarjapura is confirmed!

Service: [eventSummary]
Date & Time: [startTime in readable IST format]

Address: Naturals Salon, Sarjapura, Bangalore

See you soon!
— Sagar, Naturals Salon
```

### Tool 5: Lookup Appointment
- **Purpose:** Retrieve a client's existing appointment (to get the Event ID for modifications)
- **Inputs:** `afterTime` (ISO datetime), `beforeTime` (ISO datetime)
- **Process:** Query Google Calendar for events in the window; return event list with IDs
- **Source file:** `n8n-workflows/source/Lookup Appointment.json`
- **Key adaptation from Nate's:** None — logic is identical

### Tool 6: Update Appointment (Reschedule)
- **Purpose:** Reschedule an existing appointment to a new time
- **Inputs:** `startTime` (new start, ISO datetime), `endTime` (new end, ISO datetime), `eventID` (from Lookup tool), `email` (string), `name` (string)
- **Process:**
  1. Update Google Calendar event using eventID with new start/end times
  2. Update row in "Appointment Log" — set Notes to "Moved to [new start time]"
  3. Send Gmail reschedule confirmation email to client
- **Source file:** `n8n-workflows/source/Update Appointment.json`
- **Key adaptations from Nate's:** Add Gmail node for reschedule email

**Reschedule email template:**
```
Subject: Appointment Rescheduled — Naturals Salon Sarjapura

Hi [Name],

Your appointment has been rescheduled.

New Date & Time: [new startTime in readable IST format]
Service: [service name]

Address: Naturals Salon, Sarjapura, Bangalore

See you soon!
— Sagar, Naturals Salon
```

### Tool 7: Delete Appointment (Cancel)
- **Purpose:** Cancel an existing appointment
- **Inputs:** `eventID` (string), `email` (string), `name` (string), `startTime` (original time, for email reference)
- **Process:**
  1. Delete Google Calendar event using eventID
  2. Update row in "Appointment Log" — set Notes to "Cancelled"
  3. Send Gmail cancellation email to client
- **Source file:** `n8n-workflows/source/Delete Appointment.json`
- **Key adaptations from Nate's:** Add Gmail node for cancellation email

**Cancellation email template:**
```
Subject: Appointment Cancelled — Naturals Salon Sarjapura

Hi [Name],

Your appointment on [startTime in readable IST format] has been cancelled.

If you'd like to rebook, feel free to call us anytime!

— Sagar, Naturals Salon
```

### Tool 8: Pricing Info
- **Purpose:** Return the services menu and pricing for Naturals Salon
- **Inputs:** None (or optional `service` to filter)
- **Process:** Return a static formatted list of services, prices, and durations
- **Source file:** None — build this from scratch
- **This is a new workflow not in Nate's original**

**Response to return:**
```
Naturals Salon Sarjapura — Men's Services:
• Haircut — ₹300, 45 mins
• Beard Trim — ₹150, 20 mins
• Haircut + Beard — ₹400, 65 mins
• Head Massage — ₹200, 30 mins
• Face Cleanup — ₹250, 30 mins
• Haircut + Head Massage — ₹500, 75 mins
• Full Grooming (Haircut + Beard + Head Massage) — ₹600, 95 mins
```

### EOC Report (End of Call Webhook — NOT an MCP tool)
- **Trigger:** HTTP POST from VAPI after every call ends
- **Data received:** `message.analysis.summary`, `message.analysis.structuredData.Outcome`
- **Process:** Append row to "Call Log" tab with timestamp, summary, outcome
- **Source file:** `n8n-workflows/source/Hercules Receptionist EOC Report.json`
- **Key adaptation from Nate's:** None — logic is identical

---

## Conversation Flow

```
Inbound Call
    │
    ▼
Sagar greets: "Hi, I am Sagar from Naturals Salon Sarjapura.
               Can I get your name and mobile number please?"
    │
    ▼
Tool 1: Client Lookup (by phone number)
    ├── Existing client → "Welcome back [Name]! How can I help you today?"
    └── New client → Collect name + email → Tool 2: New Client CRM
    │
    ▼
Intent Detection
    ├── "Book appointment"
    │       ├── Ask which service
    │       ├── Ask preferred date/time
    │       ├── Tool 3: Check Availability
    │       ├── Confirm slot + service with client
    │       └── Tool 4: Book Event → email sent automatically
    │
    ├── "Reschedule appointment"
    │       ├── Tool 5: Lookup Appointment (find existing booking)
    │       ├── Confirm which appointment to reschedule
    │       ├── Ask for new preferred date/time
    │       ├── Tool 3: Check Availability
    │       ├── Confirm new slot
    │       └── Tool 6: Update Appointment → email sent automatically
    │
    ├── "Cancel appointment"
    │       ├── Tool 5: Lookup Appointment
    │       ├── Confirm which appointment to cancel
    │       └── Tool 7: Delete Appointment → email sent automatically
    │
    └── "Pricing / Services"
            └── Tool 8: Pricing Info → read out relevant services
    │
    ▼
End call gracefully
    │
    ▼
VAPI sends EOC webhook → EOC Report logs to Call Log sheet
```

---

## VAPI System Prompt (Sagar)

> See `vapi/system-prompt.md` for the full prompt.
> Key characteristics:
> - Indian English, warm and professional (not overly casual like Kylie in Nate's version)
> - Greeting: "Hi, I am Sagar from Naturals Salon Sarjapura." — do NOT use "Namaste"
> - Uses filler phrases before tool calls: "Ek second ruko" / "Let me check that for you" / "Just a moment"
> - Always says service + price + duration before confirming a booking
> - Enforces business hours: 10 AM – 8 PM Mon–Sat (last START slot is 8 PM)
> - Timezone: Asia/Kolkata — uses {{ "now" | date: "%B %d, %Y, %I:%M %p", "Asia/Kolkata" }}
> - Calculates endTime = startTime + service duration (NOT hardcoded 1 hour)

---

## File Structure

```
naturals-salon-ai-receptionist/
├── CLAUDE.md                          ← This file (read first every session)
├── n8n-workflows/
│   ├── source/                        ← Nate's original JSONs (DO NOT MODIFY)
│   │   ├── Vapi MCP Server.json
│   │   ├── Client Lookup.json
│   │   ├── New Client CRM.json
│   │   ├── Check Availability.json
│   │   ├── Book Event.json
│   │   ├── Lookup Appointment.json
│   │   ├── Update Appointment.json
│   │   ├── Delete Appointment.json
│   │   └── Hercules Receptionist EOC Report.json
│   └── adapted/                       ← Claude Code outputs go here
│       ├── MCP Server.json            ← Routes to all 8 tools
│       ├── 01-client-lookup.json
│       ├── 02-new-client-crm.json
│       ├── 03-check-availability.json
│       ├── 04-book-event.json
│       ├── 05-lookup-appointment.json
│       ├── 06-update-appointment.json
│       ├── 07-delete-appointment.json
│       ├── 08-pricing-info.json       ← New, no source file
│       └── eoc-report.json
├── vapi/
│   └── system-prompt.md              ← Sagar's full VAPI system prompt
└── docs/
    └── build-plan.md                 ← Phase-by-phase checklist
```

---

## Instructions for Claude Code

### How to work on this project

1. **Always read this CLAUDE.md first** before doing any work.
2. **When adapting a workflow:** Read the source JSON from `n8n-workflows/source/` first. Understand its node structure. Then output the adapted version to `n8n-workflows/adapted/`.
3. **Never modify files in `n8n-workflows/source/`** — they are Nate's originals for reference only.
4. **One workflow at a time.** Confirm each adapted JSON is correct before moving to the next.
5. **After outputting a workflow JSON**, remind the user to: import it in n8n → re-connect Google credentials → activate the workflow.

### How to adapt a workflow (step-by-step)
1. Read the source JSON
2. Identify all node types and connections
3. Apply adaptations listed in the tool spec above
4. Output valid n8n JSON (same format as input — nodes array, connections object, settings)
5. Do not change node IDs unless necessary
6. Ensure all `fromAI()` input mappings match the tool's input spec

### Credential placeholders
When writing adapted JSONs, use these placeholders for credentials (user will replace with their actual IDs):
- Google Sheets credential: `GOOGLE_SHEETS_CREDENTIAL_ID`
- Google Calendar credential: `GOOGLE_CALENDAR_CREDENTIAL_ID`
- Gmail credential: `GMAIL_CREDENTIAL_ID`
- Google Sheets ID (the actual sheet): `GOOGLE_SHEETS_ID`
- Google Calendar ID: `GOOGLE_CALENDAR_ID`

### Where to find actual credential IDs (in n8n UI)
n8n stores credential IDs in its Postgres database — they are not in any file on disk.
To get them:
1. Open n8n → `https://YOUR_NGROK_DOMAIN.ngrok-free.dev`
2. Go to **Settings → Credentials**
3. Click each Google credential → the ID is in the browser URL: `.../credentials/[ID]`
4. Copy each ID into `.env` (copied from `.env.example`)

**n8n instance details** (from `/N8N - self host local/.env`):
- Base URL: `https://YOUR_NGROK_DOMAIN.ngrok-free.dev`
- Encryption key: stored in `/N8N - self host local/.env` — do NOT copy into this repo

**GitHub safety:** `.env` is in `.gitignore`. Only `.env.example` (with placeholders) is committed.

### Build order
Work in this sequence:
1. `01-client-lookup.json`
2. `02-new-client-crm.json`
3. `03-check-availability.json`
4. `04-book-event.json`
5. `05-lookup-appointment.json`
6. `06-update-appointment.json`
7. `07-delete-appointment.json`
8. `08-pricing-info.json`
9. `eoc-report.json`
10. `MCP Server.json` (last — after all sub-workflows exist and have IDs in n8n)
11. `vapi/system-prompt.md`

---

## Current Build Status

- [x] Project planning complete
- [x] Services, pricing, and business rules defined
- [x] Architecture designed
- [x] Folder structure created (n8n-workflows/source, adapted/, vapi/, docs/)
- [x] Nate's source JSONs copied to n8n-workflows/source/
- [ ] Google Sheets CRM created
- [ ] Google Calendar created for salon
- [ ] Gmail credential connected in n8n
- [ ] n8n workflows adapted and imported
- [ ] VAPI assistant created
- [ ] System prompt written and added
- [ ] MCP tool connected in VAPI
- [ ] EOC webhook configured in VAPI
- [ ] End-to-end test: booking flow
- [ ] End-to-end test: rescheduling flow
- [ ] End-to-end test: cancellation flow
- [ ] End-to-end test: pricing FAQ

---

## Key Differences from Nate's Original

| Aspect | Nate's Original (Kylie) | This Project (Sagar) |
|---|---|---|
| Business | Hercules Detailing (car detailing) | Naturals Salon Sarjapura (hair salon) |
| Primary identifier | Email address | Mobile phone number |
| Client data collected | Email, name, phone | Phone, name, email |
| Appointment duration | Hardcoded 1 hour | Variable by service type |
| Client calendar invite | Yes (attendee added) | No — salon calendar only |
| Email confirmation | No | Yes — Gmail node after book/update/delete |
| Pricing tool | No | Yes — Tool 8 (new) |
| Sales/support handoff | Yes | No — out of scope |
| Voice tone | Casual, American (Kylie) | Warm, Indian English (Sagar) |
| Timezone | America/Chicago | Asia/Kolkata |
| Business hours | Not specified | Mon–Sat, 10 AM–8 PM last slot |
