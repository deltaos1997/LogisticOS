# BharatTruck — Development Workflow

This doc is for everyone working on this codebase. It covers how we use Claude, tmux, docs, and environment setup across the eight repos.

---

## Core Principle: One Claude Session Per Service

Each service is its own repo with its own `README.md` (and `API.md` where relevant). We exploit this structure with Claude by giving each session a narrow, well-documented scope.

**Never open a single Claude session and dump multiple services into it.** You lose context precision and waste tokens re-explaining things that are already written down.

| What you're working on | Claude session scope |
|---|---|
| Auth flow bug | One session in `bt-auth-service/` |
| Booking endpoint | One session in `bt-booking-service/` |
| Ops dashboard UI | One session in `bt-ops-web/` |
| Driver app screen | One session in `bt-driver-app/` |

---

## How to Start a Claude Session on a Service

Open Claude Code from inside the service directory:

```bash
cd bt-auth-service
claude
```

Or pass the working directory from the repo root:

```bash
claude --dir bt-booking-service
```

Claude will pick up the `README.md`, `API.md`, and any other MDs in that service. **That's the context it uses.** You don't need to paste code.

---

## The MD-First Rule: Docs Over Code

Claude sessions are most effective when they read docs, not source. Every time you ask Claude to help with a service it hasn't seen before, it should read `README.md` and `API.md` first — not `src/`.

**What this means in practice:**

- Keep `README.md` accurate. If you add an endpoint, update the API table before you close the session.
- When debugging with a new Claude session, say: *"read the README and API.md first, then I'll describe the problem."* This costs ~1k tokens vs 10k+ for a full `src/` read.
- If Claude starts reading source files you haven't pointed it at, redirect it: *"use the MDs, don't read the code unless I ask."*
- Docs are the primary interface. Code is the implementation detail.

---

## Keeping MDs Up to Date

**Rule: every commit that changes behaviour must update the relevant MD.**

This is not documentation for its own sake — it's what keeps future Claude sessions cheap and accurate. A Claude session that reads a stale README gives wrong answers.

**What to update and when:**

| Change | What to update |
|---|---|
| New or changed endpoint | `README.md` API table + `API.md` (if it exists) |
| New env variable | `README.md` env table + `.env.example` |
| New service dependency | `README.md` service dependencies section |
| Status change (scaffolded → done) | `docs/architecture.md` status table |
| New cross-service call | `docs/architecture.md` service-to-service graph |
| New Supabase table or column | Add a comment in the migration + note in README if it changes the API shape |

**Commit message convention:** if you updated a MD in the same commit, mention it:

```
feat: add /auth/google endpoint

- Adds POST /auth/google for Google ID token sign-in
- Links google_sub to existing account by email if found
- Updated README.md and API.md
```

---

## Integration Work: Two Claude Sessions, Side by Side

When you're wiring two services together (e.g. booking calling pricing, or auth being consumed by the ops-web), use **two Claude sessions in a tmux split** — one per service.

**The workflow:**

1. Left pane: Claude session in the **caller** service (e.g. `bt-booking-service`)
2. Right pane: Claude session in the **callee** service (e.g. `bt-pricing-service`)
3. Both sessions should have read the other service's `API.md` at the start

```
┌──────────────────────────┬──────────────────────────┐
│  claude (booking)        │  claude (pricing)         │
│                          │                           │
│  "I need to call POST    │  "Here's exactly what     │
│   /quote with these      │   /quote expects and      │
│   fields..."             │   returns..."             │
└──────────────────────────┴──────────────────────────┘
```

**Key rule:** don't try to solve both sides in one session. The caller session focuses on the outbound HTTP call and error handling. The callee session focuses on the contract and response shape. When there's a mismatch, fix the callee first, update its `API.md`, then tell the caller session what changed.

---

## tmux Setup

### Recommended layout for a full backend dev session

```bash
# From the LogisticOS root
tmux new-session -s bt

# Split into panes for the services you're running
# Window 1: Services
tmux rename-window 'services'
tmux split-window -h          # left: logs, right: shell
tmux split-window -v          # bottom right: health checks / curl tests

# Window 2: Claude sessions
tmux new-window -n 'claude'
tmux split-window -h          # two Claude sessions side by side
```

### Quick reference — tmux commands

| Action | Command |
|---|---|
| New window | `Ctrl+b c` |
| Switch window | `Ctrl+b 0–9` |
| Rename window | `Ctrl+b ,` |
| Split horizontal | `Ctrl+b %` |
| Split vertical | `Ctrl+b "` |
| Navigate panes | `Ctrl+b ←→↑↓` |
| Resize pane | `Ctrl+b` then hold `Alt+←→↑↓` |
| Zoom a pane | `Ctrl+b z` (toggle) |
| Detach session | `Ctrl+b d` |
| Reattach | `tmux attach -t bt` |
| List sessions | `tmux ls` |
| Kill pane | `Ctrl+b x` |

### Recommended window layout

```
Window 0: services     → make start / make logs
Window 1: auth         → logs-auth + curl tests for auth
Window 2: booking      → logs-booking + curl tests for booking
Window 3: claude-1     → Claude session on current service
Window 4: claude-2     → Claude session on callee service (integration work)
Window 5: git          → git status across repos (make git-status)
```

### Starting a named session with services pre-split

```bash
tmux new-session -d -s bt -n services
tmux send-keys -t bt:services 'make start' Enter

tmux new-window -t bt -n logs
tmux send-keys -t bt:logs 'make logs' Enter

tmux new-window -t bt -n work
tmux split-window -h -t bt:work

tmux attach -t bt
```

Save this as `tmux-dev.sh` in the repo root if you want a one-command startup.

---

## Debugging Without Claude

When something breaks in local dev, work through this before opening a Claude session:

### 1. Check which services are up

```bash
make status          # per-service: port, PID, UP/DOWN, health status
make health          # hit /health on all 6 web services
```

### 2. Read the logs

```bash
make logs-auth       # tail bt-auth-service
make logs-booking    # tail bt-booking-service
# etc.
```

### 3. Check the API contract first

Before reading any source code, check the relevant `API.md` or `README.md`. Most bugs at the HTTP boundary are mismatched request shapes, wrong headers, or stale assumptions about response format. The MD is faster to read than stepping through code.

### 4. Curl the endpoint directly

```bash
# Example: test OTP send
curl -X POST http://localhost:3001/auth/send-otp \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9876543210"}'

# Example: test pricing quote
curl -X POST http://localhost:3003/quote \
  -H 'Content-Type: application/json' \
  -d '{"distance_km":100,"vehicle_type":"lcv","load_type":"general","weight_kg":1000}'
```

### 5. Check environment first, code second

A large proportion of local dev failures are missing or wrong `.env` values. Check the service's `.env` against the `README.md` env table before assuming a code bug.

---

## Environment Variables

### Structure

Each service has its own `.env` file. There is no shared `.env` at the root. Each service is independently configured.

```
LogisticOS/
├── bt-auth-service/.env          ← never committed
├── bt-auth-service/.env.example  ← committed, tracks all required keys
├── bt-booking-service/.env
├── bt-booking-service/.env.example
└── ...
```

### Setting up for the first time

```bash
cp bt-auth-service/.env.example     bt-auth-service/.env
cp bt-booking-service/.env.example  bt-booking-service/.env
cp bt-pricing-service/.env.example  bt-pricing-service/.env
cp bt-payment-service/.env.example  bt-payment-service/.env
cp bt-cargo-ledger/.env.example     bt-cargo-ledger/.env
cp bt-ops-web/.env.example          bt-ops-web/.env
```

Ask the team lead for: Supabase URL + service role key, Upstash Redis URL, Razorpay keys, MSG91 auth key, SurePass API key, Google Client ID.

### Shared values (same across all services)

| Variable | Where to get it |
|---|---|
| `SUPABASE_URL` | Supabase dashboard → Settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase dashboard → Settings → API |
| `REDIS_URL` | Upstash console, or `redis://localhost:6379` for local Redis |
| `JWT_SECRET` | Generate: `openssl rand -hex 32` — must match across auth + all consumers |
| `JWT_REFRESH_SECRET` | Generate: `openssl rand -hex 32` |

### Dev-only shortcuts

| Variable | Effect |
|---|---|
| `OTP_DEV_MODE=true` | OTP logged to console, MSG91 not called |
| `NODE_ENV=development` | Pretty logs via pino-pretty |
| `BLOCKCHAIN_ENABLED=false` | Merkle root stored in DB only, no Polygon wallet needed |

### `.env.example` is a contract

When you add a new env variable to a service, **always add it to `.env.example`** with a placeholder value and a comment. This is how other devs know what they need. Treat `.env.example` the same way you treat an API contract — it's the spec, `.env` is the implementation.

---

## Port Reference

| Service | Port | Start command |
|---|---|---|
| bt-ops-web | 3000 | `make start-admin` |
| bt-auth-service | 3001 | `make start-auth` |
| bt-booking-service | 3002 | `make start-booking` |
| bt-pricing-service | 3003 | `make start-pricing` |
| bt-payment-service | 3004 | `make start-payment` |
| bt-cargo-ledger | 3005 | `make start-cargo` |
| bt-driver-app | Expo (QR) | `make start-driver` |
| bt-shipper-app | Expo (QR) | `make start-shipper` |

---

## Makefile Quick Reference

```bash
make install          # install deps for all 5 backend services
make install-all      # install deps for everything incl. frontends + mobile
make redis            # start local Redis (brew)

make start            # start all 6 web services in background
make stop             # kill all background services
make status           # per-service: port, PID, UP/DOWN
make health           # hit /health on all services

make logs             # tail all service logs
make logs-auth        # tail a specific service

make restart-auth     # restart a specific service
make git-status       # git status across all repos
make git-log          # recent commits across all repos
make clean            # remove all node_modules
```

Run `make help` for the full list with descriptions.

---

## Git — Each Service Is Its Own Repo

The `LogisticOS` workspace is the orchestration repo. Each service directory (`bt-auth-service/`, etc.) is a cloned, independent git repo. You commit and push from inside them individually.

```bash
cd bt-auth-service
git add src/routes/auth.ts README.md API.md
git commit -m "feat: add /auth/google endpoint — updated README and API.md"
git push
```

**Check status across all repos at once:**

```bash
make git-status
make git-log
```

---

## What to Tell a New Claude Session

When you start a Claude session on a service, paste this as your first message (adjust service name):

```
I'm working in bt-auth-service. Please read README.md and API.md first
before I describe what I need. Don't read src/ unless I specifically ask.
The tech stack is Fastify + TypeScript + Supabase + Redis. I'll describe
the problem after you've read the docs.
```

This sets the right behaviour immediately: docs first, code on demand.

For integration work between two services, tell each Claude session:

```
I'm working in bt-booking-service. I also need you to read
bt-pricing-service/API.md — I'm going to wire the outbound /quote call.
Don't read source unless I ask. Describe any ambiguities in the
pricing API contract and I'll confirm before we write code.
```

---

## What Not to Do

- **Don't paste raw source code into Claude** unless you've already read the MDs and still can't solve it. MDs give 90% of the context at 10% of the token cost.
- **Don't leave MDs stale after a commit.** Future sessions (and future you) will trust the MDs.
- **Don't run multiple unrelated services in one Claude session.** Scope creep kills context quality.
- **Don't share JWT secrets or Supabase service role keys in any Claude prompt.** Describe the variable name, not its value.
- **Don't run `make start` and walk away.** Check `make status` after — the services start in the background and a failure is silent until you look.
