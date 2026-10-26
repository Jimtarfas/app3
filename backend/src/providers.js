import { config } from './config.js';

export class ProviderError extends Error {}

// Our statuses: queued -> sending -> delivered | failed

async function readJson(res) {
  const text = await res.text();
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    return { raw: text.slice(0, 300) };
  }
}

const telnyx = {
  name: 'telnyx',
  configured: () => Boolean(config.telnyx.apiKey && config.telnyx.connectionId && config.telnyx.fromNumber),

  async send({ to, pdf }) {
    const form = new FormData();
    form.set('connection_id', config.telnyx.connectionId);
    form.set('from', config.telnyx.fromNumber);
    form.set('to', to);
    form.set('quality', 'high');
    form.set('contents', new Blob([pdf], { type: 'application/pdf' }), 'document.pdf');
    const res = await fetch('https://api.telnyx.com/v2/faxes', {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.telnyx.apiKey}` },
      body: form,
    });
    const body = await readJson(res);
    if (!res.ok || !body.data?.id) {
      throw new ProviderError(`Telnyx send failed (${res.status}): ${JSON.stringify(body.errors ?? body).slice(0, 300)}`);
    }
    return body.data.id;
  },

  async status(providerId) {
    const res = await fetch(`https://api.telnyx.com/v2/faxes/${encodeURIComponent(providerId)}`, {
      headers: { Authorization: `Bearer ${config.telnyx.apiKey}` },
    });
    const body = await readJson(res);
    if (!res.ok) throw new ProviderError(`Telnyx status failed (${res.status})`);
    const s = body.data?.status;
    if (s === 'delivered') return { status: 'delivered' };
    if (s === 'failed') return { status: 'failed', reason: body.data.failure_reason ?? 'unknown' };
    if (['initiated', 'originated', 'sending'].includes(s)) return { status: 'sending' };
    return { status: 'queued' };
  },
};

const phaxio = {
  name: 'phaxio',
  configured: () => Boolean(config.phaxio.apiKey && config.phaxio.apiSecret),
  auth: () => 'Basic ' + Buffer.from(`${config.phaxio.apiKey}:${config.phaxio.apiSecret}`).toString('base64'),

  async send({ to, pdf }) {
    const form = new FormData();
    form.set('to', to);
    form.set('file', new Blob([pdf], { type: 'application/pdf' }), 'document.pdf');
    const res = await fetch('https://api.phaxio.com/v2.1/faxes', {
      method: 'POST',
      headers: { Authorization: this.auth() },
      body: form,
    });
    const body = await readJson(res);
    if (!res.ok || !body.success || !body.data?.id) {
      throw new ProviderError(`Phaxio send failed (${res.status}): ${String(body.message ?? '').slice(0, 300)}`);
    }
    return String(body.data.id);
  },

  async status(providerId) {
    const res = await fetch(`https://api.phaxio.com/v2.1/faxes/${encodeURIComponent(providerId)}`, {
      headers: { Authorization: this.auth() },
    });
    const body = await readJson(res);
    if (!res.ok || !body.success) throw new ProviderError(`Phaxio status failed (${res.status})`);
    const s = body.data?.status;
    if (s === 'success') return { status: 'delivered' };
    if (s === 'failure' || s === 'partialsuccess') return { status: 'failed', reason: body.data.error_id ? `phaxio_${body.data.error_id}` : body.data.error_type ?? 'unknown' };
    if (s === 'inprogress') return { status: 'sending' };
    return { status: 'queued' };
  },
};

export const provider = config.provider === 'phaxio' ? phaxio : telnyx;

const messages = {
  receiver_no_answer: "The receiving fax machine didn't answer. Check the number and try again.",
  receiver_busy: 'The line was busy. Try again in a few minutes.',
  user_busy: 'The line was busy. Try again in a few minutes.',
  receiver_decline: 'The call was declined by the receiving line.',
  receiver_call_dropped: 'The call dropped before the fax finished. Try again.',
  receiver_incompatible_destination: "The number answered, but it isn't a fax machine.",
  receiver_invalid_number_format: "This fax number isn't valid.",
  destination_invalid: "This fax number isn't valid or can't receive faxes.",
  destination_unreachable: "This fax number can't be reached right now.",
  file_format_invalid: "The document couldn't be read. Try scanning it again.",
  timeout: "The fax didn't finish within 24 hours.",
};

export function failureMessage(reason) {
  if (!reason) return null;
  return messages[reason] ?? "The fax couldn't be delivered. Check the number and try again.";
}
