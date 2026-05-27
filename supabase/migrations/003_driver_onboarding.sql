-- ============================================================
-- Migration 003: Driver Onboarding & Identity
-- Adds driver profile enrichment, vehicles, licenses,
-- insurance, and bank accounts tables.
-- ============================================================

-- ─── Extend drivers table ─────────────────────────────────────────────────────

alter table drivers
  add column if not exists photo_url text,
  add column if not exists languages text[] default '{}',
  add column if not exists home_base_city varchar(100),
  add column if not exists home_base_lat decimal(10, 8),
  add column if not exists home_base_lng decimal(11, 8),
  add column if not exists verification_badge text not null default 'pending'
    check (verification_badge in ('pending', 'verified', 'premium'));

-- ─── Vehicles ─────────────────────────────────────────────────────────────────
-- Normalised vehicle table — a driver can own/operate multiple vehicles.

create table if not exists vehicles (
  id              uuid primary key default gen_random_uuid(),
  driver_id       uuid not null references drivers(id) on delete cascade,
  rc_number       varchar(20) not null,
  rc_storage_path text,
  vehicle_photos  text[] default '{}',
  capacity_tons   decimal(6, 2),
  body_type       text check (body_type in (
                    'open', 'closed', 'container', 'flatbed', 'tanker', 'refrigerated'
                  )),
  axle_config     text check (axle_config in (
                    '4x2', '6x2', '6x4', '8x4', '10x2'
                  )),
  maker_model     varchar(100),
  fuel_type       varchar(20),
  rc_status       text not null default 'pending'
                    check (rc_status in ('pending', 'verified', 'rejected')),
  rc_expiry       date,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (rc_number)
);

create index if not exists idx_vehicles_driver_id on vehicles(driver_id);

create trigger vehicles_updated_at
  before update on vehicles
  for each row execute function update_updated_at();

-- ─── Driver Licenses ──────────────────────────────────────────────────────────

create table if not exists driver_licenses (
  id              uuid primary key default gen_random_uuid(),
  driver_id       uuid not null references drivers(id) on delete cascade,
  dl_number       varchar(30) not null,
  dl_storage_path text,
  vehicle_classes text[] default '{}',
  expiry_date     date,
  status          text not null default 'pending'
                    check (status in ('pending', 'verified', 'rejected')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (driver_id),
  unique (dl_number)
);

create trigger driver_licenses_updated_at
  before update on driver_licenses
  for each row execute function update_updated_at();

-- ─── Driver Insurance ─────────────────────────────────────────────────────────
-- Per-vehicle insurance policies.

create table if not exists driver_insurance (
  id              uuid primary key default gen_random_uuid(),
  driver_id       uuid not null references drivers(id) on delete cascade,
  vehicle_id      uuid not null references vehicles(id) on delete cascade,
  policy_number   varchar(50),
  provider        varchar(100),
  storage_path    text,
  expiry_date     date,
  status          text not null default 'pending'
                    check (status in ('pending', 'verified', 'rejected')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (vehicle_id, policy_number)
);

create index if not exists idx_driver_insurance_driver_id on driver_insurance(driver_id);
create index if not exists idx_driver_insurance_vehicle_id on driver_insurance(vehicle_id);

create trigger driver_insurance_updated_at
  before update on driver_insurance
  for each row execute function update_updated_at();

-- ─── Bank Accounts ────────────────────────────────────────────────────────────
-- Linked to users (not just drivers) so shippers can also receive refunds.

create table if not exists bank_accounts (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references users(id) on delete cascade,
  account_number_enc   text not null,
  account_number_last4 varchar(4) not null,
  ifsc                 varchar(11) not null,
  bank_name            varchar(100),
  account_holder_name  varchar(100) not null,
  is_primary           boolean not null default true,
  verification_status  text not null default 'pending'
                         check (verification_status in ('pending', 'verified', 'rejected')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists idx_bank_accounts_user_id on bank_accounts(user_id);

create trigger bank_accounts_updated_at
  before update on bank_accounts
  for each row execute function update_updated_at();

-- ─── RLS ──────────────────────────────────────────────────────────────────────

alter table vehicles enable row level security;
alter table driver_licenses enable row level security;
alter table driver_insurance enable row level security;
alter table bank_accounts enable row level security;
