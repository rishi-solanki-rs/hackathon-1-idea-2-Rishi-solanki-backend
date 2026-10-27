# A Una Milla — database project (Supabase)

The backend repository holds the **database** for A Una Milla. It contains migrations, explicit grants, row-level security, a seed catalogue and pgTAP tests. The app's API layer lives in the Next.js frontend (Route Handlers). This repo does not run a separate server (ADR-012).

> The hackathon demo runs in **guest mode** (`AUTH_MODE=guest`), so the frontend does not call this database yet. These migrations are the tested foundation for `AUTH_MODE=supabase`. Do not apply them to a hosted project without review.

## Contents

```
supabase/migrations/20261027120000_catalogue.sql          airports, loyalty_programs, transfer_routes (public read-only)
supabase/migrations/20261027120100_user_data.sql          profiles, loyalty_balances, trips, trip_legs, test_bookings, guest_migrations
supabase/migrations/20261027120200_guest_migration_rpc.sql migrate_guest_data(): idempotent, security invoker
supabase/migrations/20261027130000_planner_profiles_and_plans.sql  private planner document + immutable plan history
supabase/migrations/20261027130100_card_catalogue.sql     card_products with evidence checks (public read-only)
supabase/seed.sql            generated from frontend/src/fixtures/catalogue.ts (scripts/export-catalogue-sql.mjs)
supabase/tests/database/     pgTAP: RLS everywhere, explicit grants, row isolation, composite FKs, idempotency
```

### Security model

- **RLS:** every public table has RLS enabled and at least one policy. Ownership checks use `(select auth.uid())`.
- **Grants:**
  - `anon` can only read the catalogue.
  - `authenticated` can read the catalogue and manage only their own rows.
  - Test bookings are insert and read only.
- **Child rows:** child tables use a composite foreign key `(parent_id, user_id)`, so a row can never reference another user's parent row.
- **Catalogue honesty:** a transfer rule cannot be `VERIFIED` without a source URL and a check date.

## Run locally (Docker required)

```bash
pnpm install
pnpm db:start     # Postgres only (other Supabase services excluded)
pnpm db:reset     # apply migrations + seed
pnpm db:test      # pgTAP
pnpm db:stop
```

## Hosted project (later, owner action)

The hosted project must be created and linked by the owner, and any changes must be reviewed first. Backups on the Free plan are manual: `supabase db dump`, stored **outside** this repo. The Supabase MCP must not be used with account-wide write access.
