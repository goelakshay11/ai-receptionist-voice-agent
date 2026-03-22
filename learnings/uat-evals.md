# UAT, Bug Bash & Evals — Naturals Salon AI Receptionist

A comprehensive record of every bug found, every system prompt improvement, and every n8n workflow fix during development and testing.

---

## Bug Bash Log

### Category: Voice Agent — Phone Number Handling

| # | Issue | Severity | Root Cause | Fix | Outcome |
|---|---|---|---|---|---|
| 1 | "double 7" parsed as "17" instead of "77" | High | LLM interpreted "double" as applying to the preceding digit, not the following one | Added explicit rule to system prompt: "double X means the digit AFTER double is repeated" with examples | Phone numbers now parsed correctly from Indian English speech |
| 2 | LLM confirmed number back digit-by-digit every time, even when clearly stated | Medium | System prompt said "always confirm" | Changed to "only confirm if genuinely unsure" | Faster calls, less repetition |
| 3 | Phone stored with +91 in sheet but searched without | High | Format mismatch between VAPI input and Google Sheets data | Normalize Input strips +91 prefix; phone stored as 10 digits without country code | Consistent lookup regardless of input format |
| 4 | Google Sheets returns phone as integer, not string | High | Sheets auto-converts number columns to integers | Added `looseTypeValidation: true` on If nodes and `.toString()` conversion | Phone comparison works with both types |

### Category: Voice Agent — Email Handling

| # | Issue | Severity | Root Cause | Fix | Outcome |
|---|---|---|---|---|---|
| 5 | Email garbled by speech-to-text ("janedoe123" vs "janedoe123") | High | STT confuses similar-sounding letters (p/b, o/a) | System prompt: "ALWAYS spell email back letter by letter before using it" | Email accuracy improved dramatically |
| 6 | Asked for email again during booking even though already collected during registration | Medium | System prompt didn't explicitly say to reuse existing email | Added rule: "NEVER ask for email again if already collected. Use the one you have." | No redundant questions |

### Category: Voice Agent — Appointment Management

| # | Issue | Severity | Root Cause | Fix | Outcome |
|---|---|---|---|---|---|
| 7 | LLM hallucinated appointment slots (said 4 PM was booked when it wasn't) | Critical | checkAvailability only returned the FIRST calendar event, not all of them | Fixed VAPI Response node to use `$input.all()` and return ALL events as formatted list | LLM sees complete picture of busy slots |
| 8 | LLM invented available times instead of using tool results | Critical | System prompt didn't strictly require tool verification | Added "AVAILABILITY RULES (NO HALLUCINATION)" section: must call tool, must read result literally, must NOT invent slots | Eliminated slot hallucination |
| 9 | LLM auto-confirmed bookings without waiting for user to say "yes" | High | No explicit instruction to wait | Added bold "WAIT for explicit confirmation" before every bookEvent/updateAppointment/deleteAppointment call | User always confirms before action |
| 10 | Rescheduling blocked by caller's own appointment | High | checkAvailability treated all events as conflicts, including the one being rescheduled | Added "RESCHEDULING EXCEPTION" rule: if the conflict Event ID matches the caller's own appointment, ignore it | Can shift appointments by 30 min without false conflict |
| 11 | Suggested reschedule to a time within 30 min of current slot | Medium | No rule against it | Added "NEVER suggest a reschedule within 30 minutes of the current appointment" | More useful reschedule suggestions |
| 12 | "Show me my appointments" returned everyone's appointments | High | lookupAppointment returns ALL calendar events, LLM didn't filter | Added rule: "Only tell caller about events matching THEIR name in the summary" | Privacy preserved, correct results |
| 13 | Calendar event summary was "Haircut — Naturals Salon" (no user name) | Medium | Book Event didn't include name in summary | Changed to "Haircut — Akshay — Naturals Salon" format | Enables name-based filtering and better calendar readability |
| 14 | Appointment Log showed UTC time, not IST | Medium | Raw ISO datetime stored directly | Added IST conversion in Normalize Input Code node using `toLocaleString('en-IN', {timeZone: 'Asia/Kolkata'})` | Human-readable IST times in sheet |
| 15 | Confirmation email showed wrong cost for "Haircut and Head Massage" | Medium | Pricing lookup matched "Head Massage" (₹200) before "Haircut + Head Massage" (₹500) | Reordered pricing array from most specific to least specific; added "and" variants | Correct pricing in all emails |
| 16 | Reschedule notes didn't record old vs new details | Low | Notes just said "Moved to [time]" | Changed to "Rescheduled: Haircut at 1:15 pm → Haircut + Beard at 4:00 pm" | Full audit trail |

### Category: Voice Agent — Conversation Quality

| # | Issue | Severity | Root Cause | Fix | Outcome |
|---|---|---|---|---|---|
| 17 | Sagar repeated greeting ("Hi I am Sagar") after every user message | High | System prompt didn't clarify that firstMessage is automatic | Added "The first message is sent automatically. Do NOT repeat it." | Clean conversation start |
| 18 | Filler phrase loops ("just a sec, just a sec, just a sec...") | High | LLM kept generating fillers while waiting for tool result | Added "Say filler ONCE, then wait silently" + banned specific phrases | Clean single filler per tool call |
| 19 | Used Western English phrases ("just a sec", "hold on") instead of Indian English | Medium | Default LLM behavior | Explicit BANNED list + mandatory Indian phrases ("Give me a few seconds, please", "Ek second, please") | More natural for Indian callers |
| 20 | Call never ended — customer had to hang up | High | No endCall function configured | Enabled endCallFunctionEnabled, added endCall tool, prompt says to call endCall after "Thank you...Goodbye!" | Sagar ends call proactively |
| 21 | Kept asking "Is there anything else?" but then said just "Goodbye" | Low | Closing flow wasn't specific | Changed to full closing: "Thank you for calling Naturals Salon Sarjapura. Have a good day. Goodbye!" then endCall | Professional, complete closing |

### Category: n8n / VAPI Integration

| # | Issue | Severity | Root Cause | Fix | Outcome |
|---|---|---|---|---|---|
| 22 | n8n Set node blocked access to "arguments" property | Critical | n8n security sandbox treats "arguments" as reserved JS keyword | Replaced all Set nodes with Code nodes that use bracket notation `['arguments']` | All VAPI payloads parsed correctly |
| 23 | VAPI returned "No result returned" for every tool call | Critical | n8n returned raw JSON; VAPI expects `{"results": [{"toolCallId": "...", "result": "..."}]}` | Added VAPI Response Code node at end of every workflow | VAPI receives and uses tool results |
| 24 | Webhook URLs had workflow ID prefix that changed on restart | High | n8n generates paths like `/webhook/{workflowId}/webhook/{path}` | Checked DB, updated all VAPI tool URLs to match actual registered paths | Stable webhook connections |
| 25 | Webhooks not registered after adding them via API | High | n8n webhook registry doesn't update without deactivate/activate cycle | Docker restart + deactivate/activate via MCP after structural changes | Webhooks register reliably |
| 26 | Sheets/Calendar nodes referenced `$('When Executed by Another Workflow')` which was skipped on webhook path | High | Webhook path skips the executeWorkflowTrigger node | Changed all references to `$('Normalize Input')` | Both trigger paths work |
| 27 | Google Sheets rate limiting (429 errors) | Medium | Too many read requests per minute during testing | Transient — wait between tests. EOC workflow now filters only `end-of-call-report` events (was processing every speech-update) | Reduced API calls by ~90% |
| 28 | EOC Report received ALL VAPI events, not just end-of-call | Medium | VAPI sends speech-updates, tool-calls, etc. to the same serverUrl | Added filter in Extract Call Data Code node: `if (msg?.type !== 'end-of-call-report') return [];` | Only logs actual call endings |
| 29 | DNS resolution failed in Docker container | Medium | Intermittent Docker networking issue | `docker restart n8n` fixes it | Documented as known issue |
| 30 | updateAppointment VAPI tool had no server URL | Critical | PATCH to update tool params overwrote the server object | Re-set the server URL after every tool parameter update | Tool always reachable |

### Category: Website / SDK

| # | Issue | Severity | Root Cause | Fix | Outcome |
|---|---|---|---|---|---|
| 31 | "Connection error" on Book Appointment click | Critical | VAPI public key was sanitized to placeholder for GitHub push | Keep real keys in gh-pages branch; placeholders only on main | Website works on GitHub Pages |
| 32 | VAPI button hidden with pointer-events:none — click couldn't reach it | High | CSS made button invisible AND unclickable | Changed to `pointer-events:auto` | Button click works |
| 33 | VAPI button created with 0px width/height | High | SDK config had `width: '0px'` | Changed to `50px` | Button actually exists in DOM |
| 34 | ESM module import of @vapi-ai/web failed in browser | High | @daily-co/daily-js dependency doesn't load as ESM | Reverted to HTML script tag SDK (vapiSDK.run()) | Proven SDK approach works reliably |
| 35 | Call UI squished horizontally instead of vertical layout | Medium | #callUI div didn't have flex-direction:column | Added CSS class with proper column flex layout | Clean vertical layout |

---

## System Prompt Evolution

| Version | Key Change | Trigger |
|---|---|---|
| v1 | Basic prompt with tool names as "Client Lookup", "Book Event" etc. | Initial build |
| v2 | Changed tool names to match VAPI function names: `clientLookup`, `bookEvent` | Tools not being called — name mismatch |
| v3 | Added phone parsing rules ("double X = XX") | Users couldn't give phone numbers |
| v4 | Added email spell-back confirmation | Emails garbled by STT |
| v5 | Added "NO HALLUCINATION" availability rules | LLM inventing time slots |
| v6 | Added "WAIT for explicit confirmation" gates | Auto-confirming without user consent |
| v7 | Complete rewrite — voice communication rules, filler bans, response length limits | Multiple voice UX issues |
| v8 | Rescheduling exception (own slot = free) | Can't shift appointment by 30 min |
| v9 | Indian filler phrases mandatory, Western phrases BANNED | "Just a sec" sounds unnatural |
| v10 | endCall function + proactive call ending | Calls never ended |
| v11 | Filter appointments by caller's name | Showed everyone's appointments |

---

## Evals Summary

### What Works Well
- Full booking flow (new client registration → service selection → availability check → booking → email)
- Rescheduling with service change
- Cancellation with email notification
- Pricing FAQ
- CRM lookup by phone and email fallback
- IST timezone throughout
- Comprehensive call logging with transcript

### Known Limitations
- n8n must be running on local machine with ngrok for tools to work
- ngrok URL changes on restart (must update VAPI tool URLs)
- Google Sheets rate limit of 60 reads/minute can cause failures during heavy testing
- Speech-to-text still occasionally mishears numbers — pre-call form mitigates this
- LLM may still occasionally use banned filler phrases despite explicit rules
