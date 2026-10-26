// Sets up Telnyx for sending faxes. Reads TELNYX_API_KEY from backend/.env.
//   node scripts/telnyx-setup.mjs              -> creates the outbound voice profile and fax application, lists numbers
//   node scripts/telnyx-setup.mjs --buy +1...  -> buys that number (about $1/month) and assigns it to the fax application
// Prints the TELNYX_CONNECTION_ID and TELNYX_FROM_NUMBER values to set as Fly secrets.
import fs from 'node:fs';

const envFile = new URL('../.env', import.meta.url);
const env = Object.fromEntries(fs.readFileSync(envFile, 'utf8').split('\n')
  .map((l) => l.trim()).filter((l) => l && !l.startsWith('#') && l.includes('='))
  .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim().replace(/^["']|["']$/g, '')]));
const key = env.TELNYX_API_KEY;
if (!key) throw new Error('TELNYX_API_KEY is missing from backend/.env');

const WEBHOOK = 'https://faxandscan-api.fly.dev/webhooks/telnyx';
const NAME = 'Fax and Scan';

async function telnyx(method, path, body) {
  const res = await fetch(`https://api.telnyx.com/v2${path}`, {
    method,
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${JSON.stringify(json.errors ?? json).slice(0, 500)}`);
  return json;
}

const balance = await telnyx('GET', '/balance').catch((e) => ({ error: e.message }));
console.log('balance:', balance.data ? `${balance.data.balance} ${balance.data.currency}` : balance.error);

let profile = (await telnyx('GET', `/outbound_voice_profiles?filter[name][contains]=${encodeURIComponent(NAME)}`)).data[0];
if (!profile) {
  profile = (await telnyx('POST', '/outbound_voice_profiles', {
    name: NAME, traffic_type: 'conversational', service_plan: 'global', enabled: true,
    whitelisted_destinations: ['US', 'CA'],
  })).data;
}
console.log('outbound voice profile:', profile.id);

let faxApp = (await telnyx('GET', `/fax_applications?filter[application_name][contains]=${encodeURIComponent(NAME)}`)).data[0];
if (!faxApp) {
  faxApp = (await telnyx('POST', '/fax_applications', {
    application_name: NAME, active: true, webhook_event_url: WEBHOOK,
    outbound: { outbound_voice_profile_id: profile.id, channel_limit: 10 },
  })).data;
}
console.log('fax application (TELNYX_CONNECTION_ID):', faxApp.id);

const owned = (await telnyx('GET', `/phone_numbers?filter[connection_id]=${faxApp.id}`)).data;
const buyIndex = process.argv.indexOf('--buy');
if (owned.length) {
  console.log('number on the fax application (TELNYX_FROM_NUMBER):', owned[0].phone_number);
} else if (buyIndex > 0) {
  const number = process.argv[buyIndex + 1];
  const order = (await telnyx('POST', '/number_orders', { phone_numbers: [{ phone_number: number }], connection_id: faxApp.id })).data;
  console.log('ordered', number, 'status', order.status, '(TELNYX_FROM_NUMBER)');
} else {
  const available = (await telnyx('GET', '/available_phone_numbers?filter[country_code]=US&filter[features][]=fax&filter[phone_number_type]=local&filter[limit]=5')).data;
  console.log('fax-capable numbers you can buy:');
  for (const n of available) {
    console.log(' ', n.phone_number, n.region_information?.map((r) => r.region_name).join(', ') ?? '', n.cost_information ? `${n.cost_information.monthly_cost} ${n.cost_information.currency}/month` : '');
  }
  console.log('Run again with --buy <number> to buy one.');
}
