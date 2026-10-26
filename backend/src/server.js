import Fastify from 'fastify';
import multipart from '@fastify/multipart';
import rateLimit from '@fastify/rate-limit';
import crypto from 'node:crypto';
import { PDFDocument } from 'pdf-lib';
import { config } from './config.js';
import { reserveFax, getFax, setProviderId, setStatus, pendingFaxes, pagesUsedThisWeek, housekeeping } from './db.js';
import { verifyEntitlement, EntitlementError } from './entitlements.js';
import { provider, failureMessage, ProviderError } from './providers.js';
import { normalizeFaxNumber } from './phone.js';

const app = Fastify({
  logger: { redact: ['req.headers["x-test-token"]', 'req.headers.authorization'] },
  bodyLimit: 64 * 1024,
  trustProxy: true,
});

await app.register(rateLimit, { max: 120, timeWindow: '1 minute' });
await app.register(multipart, { limits: { fileSize: config.maxUploadBytes, files: 1, fields: 10, fieldSize: 32 * 1024 } });

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FINAL = new Set(['delivered', 'failed']);

function deviceId(req) {
  const id = req.headers['x-device-id'];
  return typeof id === 'string' && UUID.test(id) ? id.toLowerCase() : null;
}

function fail(reply, status, code, message, extra = {}) {
  return reply.code(status).send({ error: { code, message, ...extra } });
}

function present(fax) {
  return {
    id: fax.id,
    to: fax.to_number,
    pages: fax.pages,
    status: fax.status,
    failureReason: fax.failure_reason,
    failureMessage: fax.status === 'failed' ? failureMessage(fax.failure_reason) : null,
    createdAt: new Date(fax.created_at).toISOString(),
    updatedAt: new Date(fax.updated_at).toISOString(),
  };
}

async function refresh(fax) {
  if (FINAL.has(fax.status) || !fax.provider_fax_id) return fax;
  try {
    const result = await provider.status(fax.provider_fax_id);
    if (result.status !== fax.status) setStatus(fax.id, result.status, result.reason ?? null);
  } catch (err) {
    app.log.warn({ err: err.message, fax: fax.id }, 'status refresh failed');
  }
  return getFax(fax.id);
}

app.get('/', async () => ({ service: 'Fax and Scan API' }));

app.get('/health', async () => ({ ok: true, provider: provider.name, configured: provider.configured() }));

app.post('/v1/usage', async (req, reply) => {
  try {
    const ent = await verifyEntitlement(req.body?.transaction, req.headers['x-test-token']);
    return { pagesUsed: pagesUsedThisWeek(ent.originalTransactionId), pageLimit: config.weeklyPageLimit };
  } catch (err) {
    if (err instanceof EntitlementError) return fail(reply, 402, err.code, err.message);
    throw err;
  }
});

app.post('/v1/faxes', {
  config: { rateLimit: { max: 20, timeWindow: '1 hour', keyGenerator: (req) => deviceId(req) ?? req.ip } },
}, async (req, reply) => {
  const device = deviceId(req);
  if (!device) return fail(reply, 400, 'invalid_device', 'Missing device identifier.');
  if (!req.isMultipart()) return fail(reply, 400, 'invalid_request', 'Expected a multipart upload.');

  const fields = {};
  let pdf = null;
  try {
    for await (const part of req.parts()) {
      if (part.type === 'file') {
        if (part.fieldname !== 'document') {
          part.file.resume();
          continue;
        }
        pdf = await part.toBuffer();
      } else {
        fields[part.fieldname] = part.value;
      }
    }
  } catch (err) {
    if (err.code === 'FST_REQ_FILE_TOO_LARGE') {
      return fail(reply, 413, 'document_too_large', 'This document is larger than 20 MB. Remove some pages and try again.');
    }
    throw err;
  }

  let entitlement;
  try {
    entitlement = await verifyEntitlement(fields.transaction, req.headers['x-test-token']);
  } catch (err) {
    if (err instanceof EntitlementError) return fail(reply, 402, err.code, err.message);
    throw err;
  }

  const to = normalizeFaxNumber(fields.to);
  if (!to) {
    return fail(reply, 400, 'invalid_number', 'Enter a valid US or Canada fax number, including the area code.');
  }

  if (!pdf || pdf.subarray(0, 5).toString('latin1') !== '%PDF-') {
    return fail(reply, 400, 'invalid_document', 'The document is missing or is not a PDF.');
  }
  let pages;
  try {
    pages = (await PDFDocument.load(pdf, { ignoreEncryption: true, updateMetadata: false })).getPageCount();
  } catch {
    return fail(reply, 400, 'invalid_document', "The document couldn't be read.");
  }
  if (pages < 1) return fail(reply, 400, 'invalid_document', 'The document has no pages.');
  if (pages > config.maxPagesPerFax) {
    return fail(reply, 400, 'too_many_pages', `A fax can have up to ${config.maxPagesPerFax} pages.`);
  }

  if (!provider.configured()) {
    req.log.error('fax provider is not configured');
    return fail(reply, 503, 'service_unavailable', 'Fax sending is temporarily unavailable. Please try again later.');
  }

  const id = crypto.randomUUID();
  const reserved = reserveFax({
    id,
    deviceId: device,
    originalTransactionId: entitlement.originalTransactionId,
    environment: entitlement.environment,
    provider: provider.name,
    to,
    pages,
    now: Date.now(),
  }, config.weeklyPageLimit);
  if (!reserved.ok) {
    return fail(reply, 429, 'quota_exceeded',
      `Your plan includes ${config.weeklyPageLimit} pages per 7 days and you have ${Math.max(0, config.weeklyPageLimit - reserved.used)} left.`,
      { pagesUsed: reserved.used, pageLimit: config.weeklyPageLimit });
  }

  try {
    const providerId = await provider.send({ to, pdf });
    setProviderId(id, providerId);
  } catch (err) {
    req.log.error({ err: err.message }, 'provider send failed');
    setStatus(id, 'failed', 'provider_error');
    const status = err instanceof ProviderError ? 502 : 500;
    return fail(reply, status, 'send_failed', "The fax couldn't be sent right now. You weren't charged any pages. Please try again.");
  }

  req.log.info({ fax: id, pages, env: entitlement.environment }, 'fax queued');
  return reply.code(201).send({ fax: present(getFax(id)), pagesUsed: reserved.used, pageLimit: config.weeklyPageLimit });
});

app.get('/v1/faxes/:id', async (req, reply) => {
  const device = deviceId(req);
  const fax = UUID.test(req.params.id) ? getFax(req.params.id) : null;
  if (!device || !fax || fax.device_id !== device) return fail(reply, 404, 'not_found', 'Fax not found.');
  return { fax: present(await refresh(fax)) };
});

// Keep statuses moving even when nobody has the app open.
setInterval(async () => {
  try {
    for (const fax of pendingFaxes()) await refresh(fax);
    housekeeping();
  } catch (err) {
    app.log.error({ err: err.message }, 'background refresh failed');
  }
}, 60_000).unref();

await app.listen({ port: config.port, host: '0.0.0.0' });
