# Discharge Summary Builder (`dsum`)

Offline-first Clinical Workspace Dashboard, structured Discharge Summary Builder, Google-verified Doctor-to-Doctor Patient Handover, and Multi-Algorithm A4 Print / PDF Progressive Web App.

- **Live Web App:** [https://dsum.shop/](https://dsum.shop/) (mirror: [https://syed98hafiz.github.io/dsum/](https://syed98hafiz.github.io/dsum/))
- **Privacy Policy:** [https://dsum.shop/privacy.html](https://dsum.shop/privacy.html)
- **Terms of Service:** [https://dsum.shop/terms.html](https://dsum.shop/terms.html)
- **License:** [MIT License](./LICENSE)

---

## Key Features

### 1. Clinical Workspace Dashboard & Offline-First PWA
- **Local-First Storage:** Works completely offline out of the box using IndexedDB (`ds-builder-v2`), `localStorage`, and Service Worker caching ([sw.js](./sw.js)).
- **Google Sign-In & Local Mode:** Doctors can work purely locally or sign in with Google via Supabase Auth to sync patient summaries, institution defaults, saved templates, themes, and contacts across devices.
- **Filterable Overview:** Quick stat cards (`All Patients`, `Incomplete`, `Completed`, `Cloud Sync`), status filter pills (`All`, `Incomplete`, `Completed`, `Shared`), instant search, sorting, and Card/Table desktop layouts.

### 2. Google-Verified Doctor-to-Doctor Patient Handover
- **Colleague Verification:** Before dispatching patient details, recipients are checked via Supabase `verify_google_recipient` / `user_directory`, with zero-SQL local registry, Gmail/Workspace domain MX (`dns.google`), Realtime Broadcast, and local inbox fallback support.
- **Frequently Shared Contacts:** Pinned doctor contacts appear right on the Dashboard for one-click patient handover, alongside `+ Add Contact`.

### 3. Bi-Directional A4 Preview & Multi-Algorithm Auto-Fit Engine
- **Interactive Direct Editing:** Edit patient fields, complaints, investigations table values, medications, or discharge advice directly on the A4 preview page (`#paper`), synced live back to the form.
- **4 Cycling A4 Fitting Algorithms (`⟳ Re-fit A4`):**

| Cycle Order | Algorithm | Strategy |
| :--- | :--- | :--- |
| **Default (`0`)** | **Default Auto-Density** (`runDefaultDensityAlgo`) | Automatically uses standard, `relaxed`, `compact`, or `compact2` CSS presets to keep summaries within 1–2 A4 pages. |
| **Click 1 (`1`)** | **Binary Search Auto-Scale** (`runBinarySearchScaleAlgo`) | Binary searches typography/layout scale (`0.78`–`1.04`) across 6 passes to pick the largest scale that fits the target page budget. |
| **Click 2 (`2`)** | **Flex Spacing Redistribution** (`runFlexSpacingAlgo`) | Redistributes section margins, heading gaps, line-height, and table cell padding before reducing font scale. |
| **Click 3 (`3`)** | **Knuth-Plass Balanced Breaks** (`runBalancedPenaltyAlgo`) | Guards against orphaned section headings and rebalances underfull trailing pages while protecting pinned doctor signatures. |

### 4. Custom Color Maker & Saved Templates
- **Custom Color Maker:** Solid and 2-stop gradient theme builder inside the menu (`Theme & Appearance`) with color presets, native color pickers, hex inputs (`#themeHex1` / `#themeHex2`), and live Hue / Shade sliders synced to Supabase user settings.
- **Reusable Templates:** Save full clinical protocols (e.g., unit protocols, disease bundles) or header defaults cleanly as local/cloud templates or `.json` files.

---

## Project Structure

| Path | Purpose |
| :--- | :--- |
| [index.html](./index.html) | App shell, topbar & menu dropdown, Dashboard, Clinical Form, A4 Summary view, Modals |
| [app.js](./app.js) | Application state, IndexedDB store, Supabase sync & sharing, A4 pagination & fitting algorithms |
| [styles.css](./styles.css) | Responsive UI styles (Desktop, Android, iOS Safari), themes, Custom Color Maker, and `@media print` A4 rules |
| [sw.js](./sw.js) | Network-first PWA Service Worker (`ds-v2-cache-v16`) |
| [manifest.json](./manifest.json) | PWA Web App Manifest (`icon-192.png`, `icon-512.png`) |
| [supabase-config.js](./supabase-config.js) | Supabase project URL and publishable anon key configuration |
| [supabase-schema.sql](./supabase-schema.sql) | Supabase tables (`discharge_summaries`, `user_settings`, `user_directory`, `patient_shares`), RLS, and RPCs |
| [supabase/](./supabase/) | Supabase CLI config and SQL migrations |
| [templates/](./templates/) | Built-in template library page & presets |
| [privacy.html](./privacy.html) | Standalone Privacy Policy page (linked in menu & Google OAuth Branding) |
| [terms.html](./terms.html) | Standalone Terms of Service page (linked in menu & Google OAuth Branding) |
| [LICENSE](./LICENSE) | MIT License |
| [CNAME](./CNAME) | Custom domain binding (`dsum.shop`) for GitHub Pages |
| [discharge-summary-builder.html](./discharge-summary-builder.html) | Legacy standalone single-file version |
| [export_pdf.py](./export_pdf.py) | Helper PDF export script |

---

## Supabase & Google Cloud OAuth Setup

### Supabase Setup
1. Open **SQL Editor → New query** in your Supabase project (`voczhrkycygwquxqswxx`), paste [`supabase-schema.sql`](./supabase-schema.sql), and click **Run** (or apply migrations inside [`supabase/migrations/`](./supabase/migrations/)).
2. In **Authentication → Providers**, enable **Google** and disable **Email** sign-in.
3. In **Authentication → URL Configuration**:
   - **Site URL:** `https://dsum.shop/`
   - **Redirect URLs:** `https://dsum.shop/**`, `https://www.dsum.shop/**`, `https://syed98hafiz.github.io/dsum/**`

### Google Cloud Auth Platform Branding URLs
Use these exact URLs when configuring **Google Auth Platform → Branding** and **Clients**:
- **Application home page:** `https://dsum.shop/`
- **Application privacy policy link:** `https://dsum.shop/privacy.html`
- **Application terms of service link:** `https://dsum.shop/terms.html`
- **Authorized JavaScript origins:** `https://dsum.shop`, `https://syed98hafiz.github.io`, `https://voczhrkycygwquxqswxx.supabase.co`
- **Authorized redirect URI:** `https://voczhrkycygwquxqswxx.supabase.co/auth/v1/callback`

---

## Local Development

Serve the repository statically from any local web server:

```bash
python -m http.server 8766 --bind 127.0.0.1
```

Then open [http://127.0.0.1:8766/](http://127.0.0.1:8766/) in your browser.

---

## License

Licensed under the [MIT License](./LICENSE).
