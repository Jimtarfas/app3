# Fax and Scan: Send Fax Online

An iPhone app (SwiftUI, iOS 17+) that scans documents, makes fax cover sheets and sends faxes to US and Canada numbers, plus the small backend that sends them.

- **App Store name:** Fax and Scan: Send Fax Online (home screen: "Fax & Scan")
- **Bundle ID:** `com.faxandscan.app` · ASC app id 6826948675 · team ZUCC9R4PP4
- **Subscriptions:** `com.faxandscan.app.weekly` ($4.99/week), `com.faxandscan.app.yearly` ($39.99/year, 3-day free trial), group "Fax and Scan Pro"
- **Backend:** https://faxandscan-api.fly.dev (Fly app `faxandscan-api`, region iad)
- **Fax carrier:** Telnyx fax application "Fax and Scan" (`3078868776435844474`), sending number +1 833-452-3118 (toll-free, also receives faxes, so it doubles as the test destination in the review notes)
- **Website:** https://jimtarfas.github.io/fax-and-scan-site/ (public repo `Jimtarfas/fax-and-scan-site`, copied from `docs/`)

## Layout

| Path | What |
|---|---|
| `ios/` | XcodeGen project (`project.yml`) and the SwiftUI app |
| `backend/` | Node 22 + Fastify API: verifies StoreKit transactions, enforces the weekly page limit, sends faxes via Telnyx (or Phaxio) |
| `docs/` | Landing page, privacy policy, terms and support pages |
| `marketing/` | App Store listing copy and screenshots |
| `scripts/` | Icon and screenshot generators |

## How sending works

1. The app builds a US Letter PDF (optional cover sheet + pages) and uploads it with the destination number and the active subscription's signed StoreKit transaction (`jwsRepresentation`).
2. The backend verifies the transaction against Apple's root CA (production or sandbox, so App Review and TestFlight work), checks the number (+1 NANP only, no 900/976), counts PDF pages and reserves them against the 100-pages-per-7-days allowance.
3. The PDF is streamed straight to Telnyx (`POST /v2/faxes`, multipart `contents`). It is never written to disk on our side.
4. The app polls `GET /v1/faxes/:id`; the server refreshes the status from the provider. Failed faxes don't count toward the allowance. Records are purged after 30 days.

## iOS

```bash
cd ios
xcodegen generate
open FaxScan.xcodeproj
```

The Run scheme uses `FaxScan/Resources/Products.storekit` for local StoreKit testing. Debug builds accept `-demo send|history|detail|cover|coverpreview|settings|paywall|preview` to show sample content for screenshots. Regenerate the icon with `swift scripts/make-icon.swift ios/FaxScan/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and the store screenshots with `swift scripts/make-store-screenshots.swift marketing/aso/screenshot-captions.json <rawDir> <outDir> <width> <height>`.

## Backend

```bash
cd backend
npm install
npm test
npm start            # needs Node 22+ (uses node:sqlite)
flyctl deploy --remote-only --app faxandscan-api
```

Secrets (set with `flyctl secrets set`): `TELNYX_API_KEY`, `TELNYX_CONNECTION_ID`, `TELNYX_FROM_NUMBER` (or `PHAXIO_API_KEY` + `PHAXIO_API_SECRET` and `FAX_PROVIDER=phaxio`). Optional `TEST_TOKEN` lets an operator send a test fax with curl via the `X-Test-Token` header; leave it unset in normal operation.
