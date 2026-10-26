import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';

fs.mkdirSync(config.dataDir, { recursive: true });
const db = new DatabaseSync(path.join(config.dataDir, 'faxes.db'));
db.exec('PRAGMA journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS faxes (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    original_transaction_id TEXT NOT NULL,
    environment TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_fax_id TEXT,
    to_number TEXT NOT NULL,
    pages INTEGER NOT NULL,
    status TEXT NOT NULL,
    failure_reason TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS faxes_by_subscription ON faxes (original_transaction_id, created_at);
  CREATE INDEX IF NOT EXISTS faxes_by_status ON faxes (status, created_at);
`);

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

const statements = {
  pagesUsed: db.prepare(`SELECT COALESCE(SUM(pages), 0) AS used FROM faxes
    WHERE original_transaction_id = ? AND created_at > ? AND status != 'failed'`),
  insert: db.prepare(`INSERT INTO faxes (id, device_id, original_transaction_id, environment, provider,
    to_number, pages, status, created_at, updated_at)
    VALUES (@id, @deviceId, @originalTransactionId, @environment, @provider, @to, @pages, 'queued', @now, @now)`),
  get: db.prepare('SELECT * FROM faxes WHERE id = ?'),
  getByProviderId: db.prepare('SELECT * FROM faxes WHERE provider_fax_id = ?'),
  setProviderId: db.prepare('UPDATE faxes SET provider_fax_id = ?, updated_at = ? WHERE id = ?'),
  setStatus: db.prepare('UPDATE faxes SET status = ?, failure_reason = ?, updated_at = ? WHERE id = ?'),
  pending: db.prepare(`SELECT * FROM faxes WHERE status IN ('queued', 'sending') AND provider_fax_id IS NOT NULL
    AND created_at > ? ORDER BY created_at LIMIT 50`),
  stale: db.prepare(`UPDATE faxes SET status = 'failed', failure_reason = 'timeout', updated_at = ?
    WHERE status IN ('queued', 'sending') AND created_at <= ?`),
  purge: db.prepare('DELETE FROM faxes WHERE created_at < ?'),
};

export function pagesUsedThisWeek(originalTransactionId, now = Date.now()) {
  return statements.pagesUsed.get(originalTransactionId, now - WEEK_MS).used;
}

// Checks the weekly allowance and records the fax in one transaction,
// so two uploads at the same moment can't both slip under the limit.
export function reserveFax(fax, limit) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const used = pagesUsedThisWeek(fax.originalTransactionId, fax.now);
    if (used + fax.pages > limit) {
      db.exec('ROLLBACK');
      return { ok: false, used };
    }
    statements.insert.run(fax);
    db.exec('COMMIT');
    return { ok: true, used: used + fax.pages };
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
}

export const getFax = (id) => statements.get.get(id);
export const getFaxByProviderId = (providerId) => statements.getByProviderId.get(providerId);
export const setProviderId = (id, providerId) => statements.setProviderId.run(providerId, Date.now(), id);
export const setStatus = (id, status, reason = null) => statements.setStatus.run(status, reason, Date.now(), id);
export const pendingFaxes = () => statements.pending.all(Date.now() - 24 * 60 * 60 * 1000);

export function housekeeping() {
  const now = Date.now();
  statements.stale.run(now, now - 24 * 60 * 60 * 1000);
  statements.purge.run(now - config.retentionDays * 24 * 60 * 60 * 1000);
}
