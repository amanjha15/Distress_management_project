# Deploying to Railway

Three services in one Railway project: **Postgres** (Railway's managed plugin,
not the self-hosted container from `docker-compose.yml`) → **backend**
(FastAPI, from `Road-Distress-Management-System/backend/Dockerfile`) →
**frontend** (Flutter web build, served by nginx, from `mobile/Dockerfile`).
Unlike the Oracle/`docker-compose` path in [DEPLOYMENT.md](DEPLOYMENT.md),
each service gets its own Railway-assigned domain instead of one nginx
reverse-proxying both — the frontend calls the backend cross-origin, which
already works since CORS is wide open (`allow_origins=["*"]` in
`backend/app/main.py`).

Files already added for this: `backend/railway.json`, `mobile/Dockerfile`,
`mobile/nginx.railway.conf.template`, `mobile/railway.json`. Also fixed:
`backend/.dockerignore` was excluding `models/` from the Docker build
context — harmless for `docker-compose` (which bind-mounts the models
directory at runtime) but would have shipped a backend with no model
weights on Railway, since there's no equivalent mount there.

**Push these changes to GitHub first** — Railway deploys from your connected
repo, not from this local checkout.

---

## 1. Postgres

In the Railway project: **New → Database → Add PostgreSQL**. That's it —
Railway provisions it and exposes a `DATABASE_URL` variable other services
in the project can reference.

## 2. Backend service

**New → GitHub Repo** → select this repo → set **Root Directory** to
`Road-Distress-Management-System/backend`. Railway will detect
`railway.json` and build `Dockerfile`.

Set these **Variables** on the service:
- `DATABASE_URL` = `${{Postgres.DATABASE_URL}}` (references the plugin from
  step 1 — start typing `${{` and Railway autocompletes it)

`BACKEND_CORS_ORIGINS` and everything else already defaults sensibly in
`app/core/config.py`; no other variables are required. Table creation and
schema migrations run automatically on startup (`main.py`'s `startup_event`
— no manual `init_db` step needed here, unlike the Oracle path).

**Settings → Networking → Generate Domain** — copy the resulting
`https://....up.railway.app` URL, you need it for step 3.

**Settings → Volumes → New Volume** — mount at `/app/backend/uploads`.
This is the important one: it's where raw/processed videos, detection
crops, and the downloadable APK live — without it, everything uploaded is
lost on every redeploy. Add a second volume at `/app/reports` too if your
plan allows more than one; generated PDF/Excel reports are less critical
since they're regenerated on download, so prioritize `uploads/` if you can
only have one.

**Verify model weights actually deployed**: after the first build, open a
shell on the service (Railway dashboard → service → the `>_` shell icon, or
`railway run bash` via CLI) and check:
```bash
ls -la models/
```
`road_best.pth` should be ~193MB and `signage_best.pth` ~68.5MB. If they're
tiny (under 1KB), Railway's build checked out git-lfs *pointer* files
instead of the real weights — the fix is enabling Git LFS in the GitHub
integration (Railway project Settings → the connected repo's settings), or
as a fallback, hosting the two `.pth` files somewhere with a stable direct
URL (GitHub Releases, Hugging Face Hub) and adding a `RUN curl -L <url> -o
models/road_best.pth` step to the Dockerfile instead of relying on LFS at
all. Flag this to me if you hit it and I'll wire up the curl-based fallback.

## 3. Frontend service

**New → GitHub Repo** → same repo → **Root Directory** = `mobile`. Railway
detects `mobile/railway.json` and builds `mobile/Dockerfile`.

Set this **Variable** on the service (Railway auto-passes it as a Docker
build arg since the Dockerfile declares `ARG API_BASE_URL`):
- `API_BASE_URL` = the backend's domain from step 2, e.g.
  `https://backend-production-xxxx.up.railway.app`

This gets baked into the compiled JS at build time — if the backend's
domain ever changes, redeploy the frontend, don't just restart it.

**Settings → Networking → Generate Domain** for the frontend too — this is
the URL you actually share/open in a browser.

## 4. Verify

Open the frontend's Railway URL. You should see the login screen. Log in
with the seeded admin account (`admin@roaddistress.org` /
`AdminSecurePassword123!` — change it immediately, same caveat as
DEPLOYMENT.md), then upload a short video and confirm Video Review shows
real detections.

If detections don't appear, check the backend service's logs (Railway
dashboard → backend → Deployments → View Logs) for AI pipeline errors —
the most likely cause is the model-weights issue from step 2.

---

## About "free"

Railway removed its indefinite free tier — new projects get a one-time ~$5
trial credit, then it's usage-based billing (compute + the persistent
volumes above). Worth knowing going in, since this conversation started
from a "what's free" angle: if cost matters and Railway is a requirement
rather than a preference, keep an eye on the usage dashboard early on so
there are no surprises.

## What this still doesn't fix

Same gap as flagged for the Oracle path: the backend has no real session
token — `/login` just checks the password and returns the user, so any API
route is callable without credentials if someone has the URL. Fine for an
internal pilot behind a Railway URL nobody's guessing; worth fixing before
this is handed to real users.
