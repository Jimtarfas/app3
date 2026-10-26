import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeFaxNumber } from '../src/phone.js';

test('accepts US and Canada numbers in common formats', () => {
  assert.equal(normalizeFaxNumber('(212) 555-1234'), '+12125551234');
  assert.equal(normalizeFaxNumber('+1 416 555 2199'), '+14165552199');
  assert.equal(normalizeFaxNumber('1-888-473-2963'), '+18884732963');
});

test('rejects invalid, premium-rate and other-country numbers', () => {
  for (const n of ['123', '+1 112 555 1234', '+1 900 555 1234', '+1 212 155 1234', '+1 212 555 0123', '+44 20 7946 0000', '', null]) {
    assert.equal(normalizeFaxNumber(n), null, String(n));
  }
});
