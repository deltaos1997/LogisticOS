# BharatTruck — Architecture Overview

## Service Map

```
                        ┌──────────────────────┐
                        │     bt-ops-web :3000  │  Next.js — ops console + fleet portal
                        └──────────┬───────────┘
                                   │ (proxies to backend services)
              ┌────────────────────┼────────────────────┐
              │                    │                    │
    ┌─────────▼──────┐   ┌─────────▼──────┐   ┌────────▼──────┐
    │ bt-driver-app  │   │ bt-shipper-app │   │  bt-ops-web   │
    │ (React Native) │   │ (React Native) │   │  (Next.js)    │
    └─────────┬──────┘   └────────┬───────┘   └────────┬──────┘
              │                   │                    │
              └───────────────────┼────────────────────┘
                                  │
                     ┌────────────▼────────────┐
                     │    (future API gateway) │
                     └────────────┬────────────┘
                                  │
         ┌────────────┬───────────┼───────────┬────────────┐
         │            │           │           │            │
    ┌────▼────┐ ┌─────▼────┐ ┌───▼───┐ ┌────▼────┐ ┌─────▼──────┐
    │  auth   │ │ booking  │ │pricing│ │payment  │ │cargo-ledger│
    │  :3001  │ │  :3002   │ │ :3003 │ │  :3004  │ │   :3005    │
    └────┬────┘ └─────┬────┘ └───┬───┘ └────┬────┘ └─────┬──────┘
         │            │          │           │             │
         └────────────┼──────────┴───────────┴─────────────┘
                      │
             ┌────────▼────────┐
             │   PostgreSQL    │  (Supabase)
             │   Redis         │  (Upstash)
             │   Cloudflare R2 │  (file storage — KYC docs, ePOD photos)
             └─────────────────┘
```

## Service-to-Service Call Graph

```
bt-booking-service (3002)
  ├── POST /quote              → bt-pricing-service (3003)   on booking create
  ├── POST /shipments          → bt-cargo-ledger   (3005)   on booking create
  └── POST /payments/release   → bt-payment-service (3004)  on delivery confirmed
```

All calls are internal HTTP. Locally, configured via `*_URL` env vars. In Docker Compose, resolved via compose network.

---

## Key Decisions

### No API gateway yet
Clients (mobile apps, ops-web) call services directly by URL. An API gateway is planned but not implemented — see "future API gateway" in diagram.

### Why microservices?
Each service is independently deployable, versioned, and can have its own CI/CD pipeline. No service needs to know about another's internals — only the shared HTTP contracts documented in each service's README.

### Why bt-cargo-ledger?
Multi-leg freight doesn't go A→B directly. It goes A→B→C→D across multiple trucks. At each handoff, both parties sign. The signed data is SHA-256 hashed and assembled into a Merkle tree. On final delivery, the Merkle root is optionally written to Polygon blockchain — giving any party a tamper-proof, verifiable chain of custody usable in dispute resolution.

**Phase flag:** Blockchain writing is controlled by the `BLOCKCHAIN_ENABLED` env var:
- `false` (Phase 1) — Merkle root computed and stored in DB only, no wallet needed
- `true` (Phase 2) — Root hash written on-chain via Polygon smart contract (ethers.js)

### Notifications
Not a separate service. `bt-booking-service` and `bt-payment-service` emit notifications directly via MSG91 (SMS) and Firebase FCM (push). Simple, no queue overhead for MVP.

### Auth — OTP + Google OAuth
Two sign-in paths are supported:

```
OTP flow:
  POST /auth/send-otp    → 6-digit OTP stored in Redis (5min TTL, rate-limited 5/hr)
  POST /auth/verify-otp  → verify → issue access_token (15min) + refresh_token (7 days)

Google OAuth flow:
  POST /auth/google      → Google ID token → lookup by google_sub or email → issue tokens
```

New users complete registration via `POST /auth/register` regardless of sign-in method. Phone is nullable for Google-only accounts (see migration 002).

### Blockchain strategy
- PostgreSQL is source of truth (actual checkpoint data)
- SHA-256 Merkle hash of checkpoint data stored in DB on every checkpoint
- On final delivery: Merkle root computed from all checkpoint hashes
- Phase 2: Merkle root written to Polygon (~$0.001/tx) — anyone can verify by recomputing the hash
- Phase 2 smart contract can automate escrow release on final delivery hash

---

## bt-ops-web — Two Portals

`bt-ops-web` serves two distinct user groups on the same Next.js app:

| Portal | Route prefix | Users |
|--------|-------------|-------|
| Ops Console | `/ops/*` | Internal BharatTruck ops team |
| Fleet Portal | `/portal/*` | Verified fleet owners (self-service) |

Both portals currently use **mock data** — live backend integration is planned for Sprint 3–5.

---

## Phase 1 MVP — Implementation Status

| Service | Feature | Status |
|---------|---------|--------|
| bt-auth-service | OTP login → JWT | Done |
| bt-auth-service | Google OAuth (`/auth/google`) | Done |
| bt-auth-service | KYC verify + status routes | Scaffolded — Sprint 4 |
| bt-booking-service | Booking CRUD + lifecycle endpoints | Scaffolded — Sprint 3–5 |
| bt-booking-service | Driver matching (Redis geo-index) | Sprint 4 |
| bt-booking-service | WebSocket live tracking | Sprint 3 |
| bt-booking-service | ePOD photo upload (Cloudflare R2) | Sprint 5 |
| bt-pricing-service | Static fare calculation (`/quote`) | Done |
| bt-pricing-service | ML dynamic pricing | Sprint 17 |
| bt-payment-service | Razorpay escrow + payout | Scaffolded — Sprint 7 |
| bt-cargo-ledger | Checkpoint recording + Merkle hash | Done (Phase 1) |
| bt-cargo-ledger | Polygon blockchain write | Phase 2 |
| bt-driver-app | Load notifications, accept, navigate, OTP confirm, ePOD | In progress |
| bt-shipper-app | Book truck, track, pay, rate | In progress |
| bt-ops-web | Ops dashboard + KYC queue + live trips | UI done, mock data |
| bt-ops-web | Fleet owner portal | UI done, mock data |
| bt-ops-web | Backend API integration | Sprint 3–5 |
| bt-ops-web | Google Maps live trip view | Sprint 3 |
