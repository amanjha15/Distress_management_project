# Workflow Analysis — New Multi-Module Platform Design

**Purpose of this document:** My reading of the 6 handwritten workflow pages, compiled so we can confirm I've understood it correctly *before* any code changes. Nothing has been built yet based on this — this is purely the "are we on the same page" checkpoint you asked for.

**A note on confidence:** Some of the handwriting was genuinely hard to make out. Where I'm confident, I've stated it plainly. Where I'm guessing, I've marked it clearly with 🔸 and explained what I think it says and why — please correct those specifically rather than assuming I got them right.

---

## 1. The big picture

This is a **significant expansion**, not a tweak. The app that exists today does *one* thing end-to-end: upload/record road video → AI detects cracks & potholes → view results on a map/in reports. What's sketched here is a **multi-module platform** where that existing crack-detection flow becomes just *one of four modules* a user can choose to work in, sitting behind a real login system with role-based access, for what looks like an NHAI (National Highways Authority of India) context specifically.

```
Login (Email + OTP)
  ├─ Admin  → full access to everything
  └─ Employee (sub-types E1 / E2 / E3) → sees only the projects/data they're assigned to
         │
         ▼
Homepage / Dashboard
  - "NHAI" branded
  - KPI row: No. of Projects, Km Coverage, Severity
  - Admin view vs. User view differ
         │
         ▼
Project-wise Survey (per-project view)
  - Shows existing data: videos, records, reports
  - "Choose what they want" → pick a project type / module:
         │
         ├─ M1: Crack Detection [Road Survey]        ← this is what exists today
         ├─ M2: Road Safety Audit [Project Mgmt]
         ├─ M3: Asset Management
         └─ M4: Predictive Analysis
```

---

## 2. Screen-by-screen reading

### S1 — Login
- **Email + OTP**, not a plain password. (Today: hardcoded mock email/password, no OTP, no real backend auth at all.)
- Two account types branch immediately at login: **Admin** and **Employee**.
- Admin = "All rights" (unrestricted).
- Employee has sub-types **E1, E2, E3** 🔸 — the specifics of what distinguishes these three weren't legible. My working assumption: three different employee *roles* with different permission levels (e.g. field surveyor / reviewer / manager), but I don't want to guess the actual names/permissions — **please tell me what E1/E2/E3 actually are.**
- Noted access rule: **"Admin sees everything, User sees [only] the portion they work under"** 🔸 (one word here was ambiguous between "pension" and "portion" — I'm reading it as "portion," i.e. employees are scoped to their assigned projects only, which is the only reading that makes sense in context).

### S2 — Homepage / Dashboard
- Branded around **NHAI**.
- Admin and User get different dashboard views.
- KPI table across the top: **No. of Projects**, **Km Coverage**, **Severity** (breakdown).
- This maps closely to the existing Overview/Dashboard screens, just needs the NHAI framing and these specific KPI numbers front-and-center.

### S3 — Project-wise Survey (homepage per project)
- Shows a project's existing data: **videos, records, reports**.
- **"Choose what they want"** — the user picks which module to run for this project/survey:

| Module | Name | Bracket note |
|---|---|---|
| **M1** | Crack Detection | [Road Survey] |
| **M2** | Road Safety Audit | [Project Management] |
| **M3** | Asset Management | — |
| **M4** | Predictive Analysis | — |

Then a choice of **input type: Video or Text** for starting a project 🔸 (the exact wording "Court detail" I couldn't parse — I'm reading this as a mis-transcription of something like "input detail" or similar, referring to choosing how you're providing data for the project. **Please confirm what this step is actually asking the user to choose.**)

### M1 — Crack Detection / Road Survey (this is the existing app, described as the target shape)
- Module-specific page.
- **Upload** a video, or **Read/Record** live — and *while recording live*, capture an **audio commentary** track alongside the video (a surveyor narrating observations as they drive/record). This is **new** — nothing in the current app records or attaches audio commentary.
- **Result**: flags **"Bad Road"** segments, shows **trend changes** over time.
- **Report**: exportable as **Excel** and **PDF**, and the report should **show location on a map**.

### M2 — Road Safety Audit / Project Management
- **"Same as M1"** structurally, with a change: focuses on reviewing **area / audio / visual** 🔸 (this line was one of the harder ones — I'm reading it as "same upload+record pattern as M1, but the review/output centers on area coverage plus the audio and visual review together"). Produces a **"Diff report"** 🔸 (differential/comparison report — e.g. against a safety standard or a previous audit? **Needs your clarification** — "diff" against what, exactly?).
- Formal name: **Road Safety Audit**.

### M3 — Asset Management / Project Management
- Adds: **upload document** capability (not just video) — so reports/records can be attached, reused, or managed as documents 🔸 (the exact phrase "to reuse/manage reports" was partially legible — my best reading is that M3 is where supporting documents get attached to a project for record-keeping, separate from the video-driven M1/M2 flows).

### M4 — Predictive Analysis
- Listed as a module, but **no detail was given** in these pages beyond its name. I have nothing to go on here yet — **this one needs the most input from you.**

---

## 3. What already exists vs. what's net-new

This is the part I want to be most precise about, since it's the actual gap we'd be closing.

### Already built (maps to M1 / Crack Detection today)
- Video upload (`/upload-video`) — multipart upload, real backend pipeline
- Live camera detection (`/live-monitoring`) — USB camera or phone-streamed, real-time YOLOX inference
- Road distress results (`/road-distresses`) — table, filters, per-record detail drawer
- GIS Map (`/gis-map`) — real interactive map of detections
- Video Review (`/video-review`) — dual raw/annotated playback with detection sidebar
- Reports (`/reports`) — real PDF/Excel generation and download
- Maintenance (`/maintenance`) — Kanban/table/calendar task views
- Analytics, History, Notifications, Dashboard, Overview — all real-backend or mock-data screens already built
- A `/survey` (Mission Setup) screen already exists — though it currently feeds straight into the crack-detection flow, not a module chooser

**In short: M1 essentially already exists**, except for two pieces that are genuinely new even for M1:
- Audio commentary capture during live recording
- "Bad Road" trend-over-time reporting specifically (current reporting is per-detection, not framed as road-segment health trends)

### Does not exist yet (net-new)
1. **Real authentication** — Email + OTP flow, replacing the current hardcoded mock login entirely (needs a real backend auth system: OTP generation/delivery via email, session/token handling)
2. **Role-based access control** — Admin vs. Employee (E1/E2/E3), with data scoping so employees only see their assigned projects
3. **The module chooser itself** — there's currently no concept of "projects" as containers that can run different modules; the app always goes straight into crack detection
4. **M2 — Road Safety Audit module** — entirely new: its own workflow, its own "diff" report type
5. **M3 — Asset Management module** — entirely new, including document upload/attachment (separate from video upload)
6. **M4 — Predictive Analysis module** — entirely new, and currently undefined beyond a name
7. **NHAI-specific dashboard framing** — the Project count / Km coverage / Severity KPI row as the primary homepage view
8. **Audio commentary recording** tied to live video capture

---

## 4. Open questions before we plan implementation

I'd rather ask than guess wrong on these, since they materially change the design:

1. **E1 / E2 / E3** — what are these three employee roles, and what should each be able to see/do differently from each other and from Admin?
2. **"Diff report" (M2)** — a diff against what — a previous audit of the same road, a safety standard/checklist, or something else?
3. **M4 Predictive Analysis** — what does this actually predict, and from what input data? (e.g. forecasting when a road segment will need maintenance based on crack-growth trends?)
4. **The Video/Text choice** when starting a project — text meaning a manually-typed survey report instead of video, or something else?
5. **Is this a replacement for the existing app, or an addition on top of it?** i.e., does the current single-purpose crack-detection flow keep working as-is for existing users while this module system wraps around it, or are we restructuring the existing screens directly?
6. **OTP delivery** — email-based (matching "Email + OTP"), via what service? (This needs a real email-sending capability the backend doesn't currently have at all.)

---

## 5. What I have *not* done

No code has been touched. This is purely the shared-understanding checkpoint you asked for — once you've corrected whatever I got wrong above (especially the 🔸-marked items), I'll turn this into an actual implementation plan before writing anything.
