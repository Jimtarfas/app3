import { SignedDataVerifier, Environment } from '@apple/app-store-server-library';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { config } from './config.js';

const roots = ['AppleRootCA-G3.cer', 'AppleRootCA-G2.cer'].map((name) =>
  fs.readFileSync(new URL(`../certs/${name}`, import.meta.url)),
);

// App Review and TestFlight purchases are signed for the sandbox, so both are accepted.
const verifiers = [
  new SignedDataVerifier(roots, true, Environment.PRODUCTION, config.bundleId, config.appAppleId),
  new SignedDataVerifier(roots, true, Environment.SANDBOX, config.bundleId),
];

export class EntitlementError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function isTestToken(token) {
  if (!config.testToken || !token) return false;
  const a = Buffer.from(String(token));
  const b = Buffer.from(config.testToken);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/**
 * Verifies a StoreKit 2 signed transaction (Transaction.jwsRepresentation) and
 * returns the subscription it proves, or throws EntitlementError.
 */
export async function verifyEntitlement(signedTransaction, testToken) {
  if (isTestToken(testToken)) {
    return { originalTransactionId: 'operator-test', environment: 'Test', productId: 'test' };
  }
  if (!signedTransaction || typeof signedTransaction !== 'string') {
    throw new EntitlementError('subscription_required', 'A subscription is required to send faxes.');
  }

  let tx;
  for (const verifier of verifiers) {
    try {
      tx = await verifier.verifyAndDecodeTransaction(signedTransaction);
      break;
    } catch {
      // try the next environment
    }
  }
  if (!tx) throw new EntitlementError('invalid_transaction', 'Your purchase could not be verified. Try Restore Purchases.');

  if (!config.productIds.includes(tx.productId)) {
    throw new EntitlementError('subscription_required', 'A subscription is required to send faxes.');
  }
  if (tx.revocationDate) {
    throw new EntitlementError('subscription_required', 'This subscription was refunded or revoked.');
  }
  if (!tx.expiresDate || tx.expiresDate < Date.now()) {
    throw new EntitlementError('subscription_expired', 'Your subscription has expired. Renew it to keep sending faxes.');
  }

  return {
    originalTransactionId: String(tx.originalTransactionId),
    environment: tx.environment,
    productId: tx.productId,
    expiresDate: tx.expiresDate,
  };
}
