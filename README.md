# AI Receptionist Voice Agent — Naturals Salon

AI-powered voice receptionist that handles salon appointment booking, rescheduling, and cancellation via phone/web.

---

## Architecture

```
Customer (Phone/Web)
        │
        ▼
  VAPI (Voice AI)
  ┌─────────────────────────────────────┐
  │  - Speech-to-Text (Deepgram)        │
  │  - LLM Reasoning (Claude Sonnet)    │
  │  - Text-to-Speech (VAPI Voice)      │
  │  - Function Calling (Tool Dispatch) │
  └──────────────┬──────────────────────┘
                 │ HTTP POST (Webhook Tools)
                 ▼
        n8n (Workflow Engine)
  ┌─────────────────────────────────────┐
  │  8 Sub-Workflows (Tools):           │
  │  01 Client Lookup                   │
  │  02 New Client CRM                  │
  │  03 Check Availability              │
  │  04 Book Event                      │
  │  05 Lookup Appointment              │
  │  06 Update Appointment              │
  │  07 Delete Appointment              │
  │  08 Pricing Info                    │
  │  + EOC Report (end-of-call)         │
  └──────┬──────────┬───────────────────┘
         │          │
         ▼          ▼
  Google Sheets   Google Calendar   Gmail
  (CRM + Logs)    (Scheduling)      (Confirmations)
```

---

## Tech Stack

| Layer | Tool | Purpose |
|---|---|---|
| Voice AI | VAPI | Speech-to-text, LLM orchestration, text-to-speech |
| Workflow Engine | n8n (self-hosted) | 8 sub-workflows as callable tools |
| LLM | Claude Sonnet (via VAPI) | Reasoning and conversation |
| CRM | Google Sheets | Clients tab, Appointment Log, Call Log |
| Scheduling | Google Calendar | Salon-side appointment calendar |
| Email | Gmail (via n8n) | Booking/reschedule/cancellation confirmations |
| Tunneling | ngrok | Exposes local n8n to VAPI webhooks |
| Website Hosting | GitHub Pages | Free static hosting for the booking website |
| Website | HTML/CSS/JS + VAPI Web SDK | Browser-based voice booking interface |

---

## Features

- **Voice Booking** — Customers call in and book appointments by voice; Sagar (the AI) handles the full flow
- **Rescheduling** — Look up existing bookings and move them to a new slot
- **Cancellation** — Cancel appointments with automatic confirmation email
- **Pricing FAQ** — Returns full services menu with prices and durations on request
- **CRM Lookup** — Identifies returning customers by phone number; onboards new ones automatically
- **Appointment Logging** — Every booking, reschedule, and cancellation is written to Google Sheets
- **Call Transcripts** — Full call summary and outcome logged after every call ends (EOC report)
- **Confirmation Emails** — Gmail sends booking/reschedule/cancellation emails to the customer
- **Web Interface** — Browser-based voice call widget for web visitors (VAPI Web SDK)
- **Variable Duration Booking** — End time calculated from service type, not hardcoded
- **Pre-Call Form Integration** — Website form passes name/phone/email to VAPI via `assistantOverrides.variableValues`, eliminating voice-based data entry errors
- **Past Appointment Lookup** — Callers can view both past and upcoming appointments
- **Fast, Natural Conversation** — Optimized for 1-sentence responses, minimal fillers, no repetitive confirmation loops

---

## Project Structure

```
naturals-salon-ai-receptionist/
├── README.md                          # This file
├── CLAUDE.md                          # Project context for Claude Code
├── startup.sh                         # Starts all services (n8n, ngrok, website, cloudflared)
├── stop.sh                            # Stops all services
├── .env.example                       # Credential placeholders (copy to .env)
├── .gitignore                         # Excludes .env, credentials, screenshots
├── n8n-workflows/
│   ├── source/                        # Nate Herk's original JSONs (reference only, DO NOT MODIFY)
│   │   ├── Vapi MCP Server.json
│   │   ├── Client Lookup.json
│   │   ├── New Client CRM.json
│   │   ├── Check Availability.json
│   │   ├── Book Event.json
│   │   ├── Lookup Appointment.json
│   │   ├── Update Appointment.json
│   │   ├── Delete Appointment.json
│   │   └── Hercules Receptionist EOC Report.json
│   └── adapted/                       # Adapted workflows for Naturals Salon
│       ├── MCP Server.json            # MCP Server Trigger (routes to all tools)
│       ├── 01-client-lookup.json      # Lookup client by phone or email
│       ├── 02-new-client-crm.json     # Create new client in CRM
│       ├── 03-check-availability.json # Check Google Calendar for free slots
│       ├── 04-book-event.json         # Book appointment + log + email
│       ├── 05-lookup-appointment.json # Find existing appointments
│       ├── 06-update-appointment.json # Reschedule appointment + email
│       ├── 07-delete-appointment.json # Cancel appointment + email
│       ├── 08-pricing-info.json       # Return services & pricing
│       └── eoc-report.json            # End-of-call report → Call Log sheet
├── vapi/
│   └── system-prompt.md               # Sagar's complete VAPI system prompt
├── website/
│   └── index.html                     # Booking website with VAPI Web SDK voice integration
├── learnings/
│   └── README.md                      # Detailed build learnings and debugging notes
└── docs/
    └── build-plan.md                  # Phase-by-phase build checklist
```

---

## Setup

### Prerequisites

- Docker Desktop (for self-hosted n8n)
- [ngrok](https://ngrok.com/) — tunnels n8n to the internet (free tier works)
- Website is hosted on [GitHub Pages](https://goelakshay11.github.io/ai-receptionist-voice-agent/) — no local hosting needed
- [VAPI](https://vapi.ai/) account — voice AI platform
- Google Cloud project with Sheets, Calendar, and Gmail OAuth2 APIs enabled
- Python 3 (optional, for local testing only)

### Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/goelakshay11/ai-receptionist-voice-agent.git
cd ai-receptionist-voice-agent

# 2. Install tunneling tools
brew install ngrok cloudflared

# 3. Configure environment
cp .env.example .env
# Edit .env with your actual credential IDs

# 4. Start n8n + ngrok
chmod +x startup.sh stop.sh
./startup.sh
# This starts: n8n (Docker) → ngrok
# Website is hosted on GitHub Pages: https://goelakshay11.github.io/ai-receptionist-voice-agent/

# 5. Stop all services
./stop.sh
```

### Detailed Setup

1. **Import n8n workflows** — Open n8n at your ngrok URL → Import each JSON from `n8n-workflows/adapted/` (01 through 08, then eoc-report, then MCP Server) → Re-connect Google OAuth2 credentials in each workflow → Activate all workflows

2. **Configure VAPI** — Create a new assistant → Set LLM model → Paste `vapi/system-prompt.md` as the system prompt → Add 8 function tools (one per sub-workflow webhook URL) → Enable `endCall` default tool → Set `maxDurationSeconds: 720` → Add EOC webhook → Set `endCallFunctionEnabled: true`

3. **Configure website** — Edit `website/index.html` and replace `YOUR_VAPI_PUBLIC_KEY` and `YOUR_VAPI_ASSISTANT_ID` with your actual VAPI credentials

4. **Test** — Open https://goelakshay11.github.io/ai-receptionist-voice-agent/ → Click "Book Appointment" → Talk to Sagar

---

## How It Works

```
1. Customer calls the VAPI phone number (or clicks the web widget)

2. Sagar greets: "Hi, I am Sagar from Naturals Salon Sarjapura.
                  Can I get your name and mobile number please?"

3. VAPI extracts the phone number and calls the Client Lookup webhook
   → n8n checks Google Sheets for a matching record
   → Returns: existing client (with name) or new client

4. For new clients: Sagar collects name + email → New Client CRM webhook
   → n8n appends a new row to the Clients sheet

5. Sagar detects intent (book / reschedule / cancel / pricing):

   BOOKING:
   → Asks for service + preferred date/time
   → Check Availability webhook → n8n queries Google Calendar
   → Confirms slot with customer
   → Book Event webhook → n8n creates calendar event + logs to Sheets + sends Gmail

   RESCHEDULING:
   → Lookup Appointment webhook → finds existing event ID
   → Check Availability for new slot
   → Update Appointment webhook → updates calendar + Sheets + sends Gmail

   CANCELLATION:
   → Lookup Appointment webhook → finds event ID
   → Confirms with customer
   → Delete Appointment webhook → removes from calendar + updates Sheets + sends Gmail

   PRICING:
   → Pricing Info webhook → returns services, prices, durations

6. Call ends → VAPI fires EOC webhook
   → n8n logs call summary + outcome to Call Log sheet
```

---

## Screenshots

_Coming soon._

---

## Credits

Inspired by [Nate Herk's "Build Your Own AI Receptionist with VAPI and n8n"](https://www.youtube.com/@nateherk) tutorial. Adapted and extended for Naturals Salon, Sarjapura, Bangalore.

Key changes from the original:
- Phone number as primary identifier (instead of email)
- Variable appointment duration by service (not hardcoded 1 hour)
- Gmail confirmation emails added for all booking actions
- Pricing Info tool added (new)
- Indian English voice persona (Sagar, not Kylie)
- IST timezone throughout
- Webhook-based tool dispatch (not MCP) for VAPI compatibility

---

## License

MIT
