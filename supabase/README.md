# Mimo account sync backend

Mimo uses Supabase Auth and Postgres for optional cross-platform text sync. The
Mac app remains fully usable without this configuration. Audio, downloaded
models, API credentials, screen context, and diagnostics never enter this sync
envelope.

## Project setup

1. Create one Supabase project for Mimo and keep email confirmation enabled.
2. Link this directory with the Supabase CLI.
3. Apply `migrations/20260902031000_mimo_account_sync.sql`.
4. Deploy `functions/delete-account` without exposing the service-role key to
   either client. Supabase supplies `SUPABASE_URL` and
   `SUPABASE_SERVICE_ROLE_KEY` to the function environment.
5. Configure the clients and GitHub Actions with only:

   - `MIMO_SUPABASE_URL`
   - `MIMO_SUPABASE_PUBLISHABLE_KEY`

For the `ederntjw/mimo` GitHub repository these are repository **variables**,
not secrets, because they are intentionally embedded in the distributable
clients. Row Level Security is the authorization boundary. Never configure or
ship `SUPABASE_SERVICE_ROLE_KEY` in a client build.

## Reproducible commands

After installing and authenticating the Supabase CLI:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase functions deploy delete-account
```

Use the Supabase dashboard to copy the project URL and publishable key into the
two variables above. A build without them reports that account sync is not
configured and continues in local-only mode.

The canonical client envelope and conflict rules live in
`Context/mimo-account-sync-v1.md` in the maintainer workspace.
