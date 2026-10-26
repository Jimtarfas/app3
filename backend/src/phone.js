import { config } from './config.js';

// North American numbers: NXX-NXX-XXXX, where N is 2-9.
const NANP = /^\+1([2-9]\d{2})([2-9]\d{2})(\d{4})$/;
// Premium-rate and other area codes a fax should never dial.
const BLOCKED_NANP_AREAS = new Set(['900', '976']);

/** Returns the number in E.164 form, or null if it may not be dialed. */
export function normalizeFaxNumber(input) {
  if (typeof input !== 'string') return null;
  let digits = input.replace(/[^\d+]/g, '');
  if (!digits.startsWith('+')) {
    // A bare 10-digit number is treated as US/Canada.
    digits = digits.length === 10 ? `+1${digits}` : `+${digits}`;
  }
  if (!/^\+\d{8,15}$/.test(digits)) return null;

  const allowed = config.allowedCountryCodes.find((code) => digits.startsWith(`+${code}`));
  if (!allowed) return null;

  if (allowed === '1') {
    const m = digits.match(NANP);
    if (!m || BLOCKED_NANP_AREAS.has(m[1]) || m[2] === '555' && m[3].startsWith('01')) return null;
  }
  return digits;
}
