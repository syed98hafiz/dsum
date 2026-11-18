# Discharge Summary Builder (`dsum`)

Standalone Patient Dashboard, Discharge Summary Builder, Google Cloud Sync, and Doctor-to-Doctor Patient Handover web app hosted at **[dsum.shop](https://dsum.shop/)** (`https://syed98hafiz.github.io/dsum/`).

## Key Features
- **Google-Only Doctor Authentication & Cloud Sync**:
  - Doctors sign in using Google OAuth via Supabase Auth.
  - Multi-device sync for patient summaries, institution defaults, saved templates, themes, and frequently shared contacts.
- **Patient Details Sharing (Google-Verified)**:
  - Share patient summaries from one doctor's Google email to another right inside the website (`📤 Share` on any patient card, table row, form bar, or summary bar).
  - Before sending, the website verifies (both in the UI and in the Supabase `share_patient_summary` RPC) that the recipient email has signed in using Google.
- **Frequently Shared Contacts Dashboard**:
  - Automatically tracks and pins colleagues you share patient records with on the Dashboard for one-click sharing (`👥 Frequently Shared Contacts`).
- **Offline-First + A4 Print / PDF**:
  - Works offline via IndexedDB (`ds-builder-v2`) and Service Worker (`sw.js`), with direct inline A4 summary editing, smart pagination (`relaxed` / `compact` / `compact2`), and PDF export/sharing.

## Supabase Setup
1. Open **SQL Editor → New query** in your Supabase project (`voczhrkycygwquxqswxx`), paste [`supabase-schema.sql`](./supabase-schema.sql), and click **Run** (or push migrations under `supabase/migrations/`).
   - Creates `public.discharge_summaries`, `public.user_settings`, `public.user_directory`, `public.patient_shares`, RLS policies, and the `verify_google_recipient` + `share_patient_summary` RPCs.
2. In **Authentication → Providers**, keep **Google** enabled and disable **Email** provider.
3. In **Authentication → URL Configuration**, set **Site URL** to `https://dsum.shop/` and add redirect URLs for `https://dsum.shop/**`, `https://www.dsum.shop/**`, and `https://syed98hafiz.github.io/dsum/**`.
