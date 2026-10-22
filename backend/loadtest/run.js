// Load-test scenarios with autocannon (npm devDependency, nothing else to install).
//
//   node loadtest/run.js <browse|search|order|telemetry|sockets|all> [--connections 20] [--duration 20]
//
// Against the local test setup only: an API started with the test env on LOADTEST_BASE (default :4565), a database
// seeded by seed-scale.js, stripe-mock for the order scenario. Each scenario prints one JSON line with req/s and
// latency percentiles (autocannon reports p50/p90/p97.5/p99; p95 is quoted as the p97.5 bound in the results doc).
const autocannon = require("autocannon");
const { io } = require("socket.io-client");
const { BASE, assertThrowaway, db, token, pick, ip, report } = require("./common");

assertThrowaway();
const args = process.argv.slice(2);
const scenario = args[0] || "all";
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? Number(args[i + 1]) : fallback;
};
const CONNECTIONS = opt("connections", 20);
const DURATION = opt("duration", 20);

function cannon(name, requests, extra = {}) {
  return new Promise((resolve, reject) => {
    const inst = autocannon({ url: BASE, connections: CONNECTIONS, duration: DURATION, requests, ...extra }, (err, res) => {
      if (err) return reject(err);
      resolve(report(name, res));
    });
    autocannon.track(inst, { renderProgressBar: false, renderResultsTable: false, renderLatencyTable: false });
  });
}

async function seedIds() {
  const c = await db();
  const q = async (sql) => (await c.query(sql)).rows;
  const stores = (await q(`SELECT id FROM "Store" WHERE name LIKE 'Loadtest Shop %'`)).map((r) => r.id);
  const products = (await q(`SELECT id, "storeId" FROM "Product" WHERE "storeId" IN (SELECT id FROM "Store" WHERE name LIKE 'Loadtest Shop %') AND "isAvailable" AND id % 4 <> 0`));
  const customers = await q(`SELECT id, role, email FROM "User" WHERE email LIKE 'lt-c%@loadtest.invalid' ORDER BY id LIMIT 500`);
  const couriers = await q(`SELECT u.id, u.role, u.email, c.id AS "courierId" FROM "User" u JOIN "Courier" c ON c."userId" = u.id WHERE u.email LIKE 'lt-k%@loadtest.invalid' AND c."isActive"`);
  return { c, stores, products, customers, couriers };
}

async function browse(ids) {
  const json = { "Accept-Encoding": "br, gzip" };
  return cannon("browse", [{
    setupRequest: (req) => {
      const r = Math.random();
      const store = pick(ids.stores);
      const path = r < 0.25 ? `/api/v1/stores?lat=60.17&lng=24.94&page=${1 + Math.floor(Math.random() * 5)}&limit=20`
        : r < 0.45 ? `/api/v1/stores/${store}?lat=60.17&lng=24.94`
        : r < 0.65 ? `/api/v1/stores/${store}/products?page=1&limit=20`
        : r < 0.85 ? `/api/v1/products/${pick(ids.products).id}`
        : `/api/v1/drops/feed?mode=foryou&limit=10&lat=60.17&lng=24.94`;
      return { ...req, method: "GET", path, headers: { ...json, "X-Forwarded-For": ip() } };
    },
  }]);
}

async function search() {
  const words = ["wool", "vintage", "dress", "denim jacket", "silk", "boots", "linen shirt", "coat", "bag", "pleated skirt", "blazer 12"];
  return cannon("search", [{
    setupRequest: (req) => {
      const r = Math.random();
      const qs = r < 0.6 ? `q=${encodeURIComponent(pick(words))}&page=1&limit=20`
        : r < 0.8 ? `size=M&sort=newest&page=1&limit=20`
        : `sort=price_asc&page=${1 + Math.floor(Math.random() * 20)}&limit=20`;
      return { ...req, method: "GET", path: `/api/v1/products/search?${qs}`, headers: { "Accept-Encoding": "br, gzip", "X-Forwarded-For": ip() } };
    },
  }]);
}

async function order(ids) {
  // Plenty of stock on the products used, so the scenario measures checkout rather than "sold out"
  await ids.c.query(`UPDATE "Product" SET "stockQuantity" = 1000000 WHERE id = ANY($1)`, [ids.products.map((p) => p.id)]);
  const tokens = ids.customers.map((u) => token(u));
  const basket = () => {
    const p = pick(ids.products);
    return { storeId: p.storeId, items: [{ productId: p.id, quantity: 1 }], deliveryLat: 60.17 + Math.random() * 0.02, deliveryLng: 24.94 + Math.random() * 0.02 };
  };
  // Customers accept the Terms in force first (POST /orders answers 428 AGREEMENT_REQUIRED until they do)
  const probe = await fetch(`${BASE}/api/v1/orders`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${tokens[0]}`, "X-Forwarded-For": ip() },
    body: JSON.stringify({ ...basket(), deliveryAddress: "Mannerheimintie 1, Helsinki" }) });
  const need = probe.status === 428 ? await probe.json() : null;
  if (need?.doc) {
    for (let i = 0; i < tokens.length; i += 20) {
      await Promise.all(tokens.slice(i, i + 20).map((t) => fetch(`${BASE}/api/v1/me/agreements/accept`, { method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${t}`, "X-Forwarded-For": ip() }, body: JSON.stringify({ doc: need.doc, version: need.version }) })));
    }
  }
  const quote = await cannon("quote", [{
    setupRequest: (req) => ({ ...req, method: "POST", path: "/api/v1/orders/quote",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${pick(tokens)}`, "X-Forwarded-For": ip() }, body: JSON.stringify(basket()) }),
  }]);
  const ord = await cannon("order (stripe-mock)", [{
    setupRequest: (req) => ({ ...req, method: "POST", path: "/api/v1/orders",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${pick(tokens)}`, "X-Forwarded-For": ip(), "Idempotency-Key": `lt-${Date.now()}-${Math.random()}` },
      body: JSON.stringify({ ...basket(), deliveryAddress: "Mannerheimintie 1, Helsinki" }) }),
  }]);
  return [quote, ord];
}

async function telemetry(ids) {
  const tokens = ids.couriers.map((u) => token(u));
  return cannon("courier telemetry (HTTP)", [{
    setupRequest: (req) => ({ ...req, method: "POST", path: "/api/v1/courier/telemetry",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${pick(tokens)}`, "X-Forwarded-For": ip() },
      body: JSON.stringify({ latitude: 60.15 + Math.random() * 0.1, longitude: 24.85 + Math.random() * 0.2, speed: 4, bearing: 90, accuracy: 8 }) }),
  }]);
}

/** Opens N sockets (customers), then couriers stream locations for 15 s; reports connect times and delivered events. */
async function sockets(ids) {
  const n = opt("sockets", 500);
  const users = ids.customers.slice(0, Math.min(n, ids.customers.length));
  while (users.length < n) users.push(pick(ids.customers));
  const times = [];
  let failed = 0;
  const t0 = Date.now();
  const socks = await Promise.all(users.map((u) => new Promise((resolve) => {
    const start = Date.now();
    const s = io(BASE, { auth: { token: token(u) }, transports: ["websocket"], reconnection: false, timeout: 20_000 });
    s.on("connect", () => { times.push(Date.now() - start); resolve(s); });
    s.on("connect_error", () => { failed++; resolve(s); });
  })));
  const connectWallMs = Date.now() - t0;
  // Couriers send locations over their sockets (as the app does) for 15 s
  const courierSocks = await Promise.all(ids.couriers.slice(0, 100).map((u) => new Promise((resolve) => {
    const s = io(BASE, { auth: { token: token(u) }, transports: ["websocket"], reconnection: false });
    s.on("connect", () => resolve(s));
    s.on("connect_error", () => resolve(s));
  })));
  let sent = 0;
  const timer = setInterval(() => {
    for (const s of courierSocks) { s.emit("courier:telemetry", { orderId: 1, lat: 60.17, lng: 24.94 }); sent++; }
  }, 1000);
  await new Promise((r) => setTimeout(r, 15_000));
  clearInterval(timer);
  times.sort((a, b) => a - b);
  const p = (q) => times[Math.min(times.length - 1, Math.floor(q * times.length))] ?? null;
  const line = { scenario: "sockets", sockets: n, connected: times.length, failed, connectWallMs, connectMs: { p50: p(0.5), p95: p(0.95), p99: p(0.99), max: times[times.length - 1] ?? null }, courierLocationEventsSent: sent };
  console.log(JSON.stringify(line));
  for (const s of [...socks, ...courierSocks]) s.close();
  return line;
}

(async () => {
  const ids = await seedIds();
  if (!ids.stores.length) { console.error("No seeded data: run loadtest/seed-scale.js first."); process.exit(1); }
  const run = { browse, search, order, telemetry, sockets };
  const names = scenario === "all" ? Object.keys(run) : [scenario];
  for (const name of names) {
    if (!run[name]) { console.error(`Unknown scenario ${name}`); process.exit(1); }
    await run[name](ids);
  }
  await ids.c.end();
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
