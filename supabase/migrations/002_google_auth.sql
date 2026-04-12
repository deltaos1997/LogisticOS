-- ============================================================
-- Migration 002: Add Google OAuth support to existing users table
-- ============================================================

-- Add google_sub for future Google auth (nullable, won't break OTP flow)
alter table users
  add column if not exists google_sub varchar(255) unique;

-- Make phone_number nullable so Google-only users can sign up without a phone
alter table users
  alter column phone_number drop not null;

-- Index for Google sub lookups
create index if not exists idx_users_google_sub on users(google_sub)
  where google_sub is not null;
