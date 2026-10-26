const list = (value, fallback) =>
  (value ?? fallback).split(',').map((s) => s.trim()).filter(Boolean);

export const config = {
  port: Number(process.env.PORT ?? 8080),
  dataDir: process.env.DATA_DIR ?? './data',

  // App Store
  bundleId: process.env.BUNDLE_ID ?? 'com.faxandscan.app',
  appAppleId: Number(process.env.APP_APPLE_ID ?? 6826948675),
  productIds: list(process.env.PRODUCT_IDS, 'com.faxandscan.app.weekly,com.faxandscan.app.yearly'),

  // Usage limits. They are shown on the paywall, so keep them in sync with the app.
  weeklyPageLimit: Number(process.env.WEEKLY_PAGE_LIMIT ?? 100),
  // TestFlight and App Review purchases are free sandbox purchases, so they get a smaller allowance.
  sandboxWeeklyPageLimit: Number(process.env.SANDBOX_WEEKLY_PAGE_LIMIT ?? 20),
  maxPagesPerFax: Number(process.env.MAX_PAGES_PER_FAX ?? 50),
  maxUploadBytes: Number(process.env.MAX_UPLOAD_BYTES ?? 20 * 1024 * 1024),
  // Country calling codes that may be dialed, e.g. "1" for US and Canada.
  allowedCountryCodes: list(process.env.ALLOWED_COUNTRY_CODES, '1'),
  retentionDays: Number(process.env.RETENTION_DAYS ?? 30),

  // Fax provider: "telnyx" or "phaxio"
  provider: process.env.FAX_PROVIDER ?? (process.env.PHAXIO_API_KEY ? 'phaxio' : 'telnyx'),
  telnyx: {
    apiKey: process.env.TELNYX_API_KEY,
    connectionId: process.env.TELNYX_CONNECTION_ID,
    fromNumber: process.env.TELNYX_FROM_NUMBER,
  },
  phaxio: {
    apiKey: process.env.PHAXIO_API_KEY,
    apiSecret: process.env.PHAXIO_API_SECRET,
  },

  // Lets the operator send a test fax with curl without a StoreKit purchase.
  // Never shipped in the app. Leave unset in normal operation.
  testToken: process.env.TEST_TOKEN,
};
