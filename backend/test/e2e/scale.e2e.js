// Scale and operations checks (horizontal scaling, observability, idempotency, caching, queue, shutdown).
// Starts its own API instances from dist/ (run `npm run build` first) against its own database and ports, so it never
// clashes with the main suite:
//
//   # without Redis (single instance: in-memory limiter, local rooms, in-memory idempotency, in-process queue)
//   node test/e2e/scale.e2e.js
//   # with Redis: also two instances sharing Redis (sockets, rate limits, session revocation, idempotency, BullMQ)
//   docker run -d --name malvoya-test-redis -p 56379:6379 redis:7
//   SCALE_REDIS_URL=redis://localhost:56379 node test/e2e/scale.e2e.js
//
// Env: SCALE_DATABASE_URL (default postgresql://postgres:test@localhost:56432/malvoya_scale, migrated), stripe-mock on
// :12111, the Cloudinary mock is not needed. Ports 4565 and 4567.
const { spawn, execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { io } = require("socket.io-client");

const ROOT = path.join(__dirname, "..", "..");
const DB_URL = process.env.SCALE_DATABASE_URL || "postgresql://postgres:test@localhost:56432/malvoya_scale";
const DB_NAME = new URL(DB_URL).pathname.slice(1);
const REDIS = process.env.SCALE_REDIS_URL || "";
const A = "http://localhost:4565";
const B = "http://localhost:4567";
const METRICS_TOKEN = "scale-test-metrics-token-0123456789";
let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass++; console.log(`  ✓ ${name}`); }
  else { fail++; console.log(`  ✗ ${name}`, extra !== undefined ? JSON.stringify(extra).slice(0, 400) : ""); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
function sql(q) {
  return execSync(`docker exec -i malvoya-test-db psql -U postgres -d ${DB_NAME} -tA`, { input: q }).toString().trim();
}
if (!/scale|loadtest/.test(DB_NAME)) { console.error("SCALE_DATABASE_URL must name a throwaway *scale* database"); process.exit(1); }

const testEnv = Object.fromEntries(fs.readFileSync(path.join(__dirname, "test.env"), "utf8").split(/\r?\n/)
  .filter((l) => l && !l.startsWith("#") && l.includes("="))
  .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
const baseEnv = {
  ...process.env, ...testEnv, DATABASE_URL: DB_URL, REDIS_URL: REDIS, DISABLE_SCHEDULER: "true", LOG_LEVEL: "warn",
  CLOUDINARY_API_BASE: "http://localhost:12232", METRICS_TOKEN, SENTRY_DSN: "", WORKER_MODE: "",
};
// The test process itself loads dist modules (scheduler lease, queue): same settings
Object.assign(process.env, baseEnv);

const procs = [];
function startApi(port, extra = {}, { ipc = false } = {}) {
  const base = `http://localhost:${port}`;
  const child = spawn(process.execPath, ipc ? ["-e", "require('./dist/index.js'); process.on('message', (m) => { if (m === 'stop') process.emit('SIGTERM'); });"] : ["dist/index.js"], {
    cwd: ROOT, env: { ...baseEnv, PORT: String(port), PUBLIC_API_URL: base, ...extra },
    stdio: ipc ? ["ignore", "pipe", "pipe", "ipc"] : ["ignore", "ignore", "pipe"],
  });
  child.output = "";
  child.stdout?.on("data", (d) => (child.output += d));
  child.stderr?.on("data", (d) => (child.output += d));
  procs.push(child);
  return child;
}
async function waitUp(base) {
  for (let i = 0; i < 80; i++) {
    try { if ((await fetch(`${base}/health`)).ok) return true; } catch {}
    await sleep(250);
  }
  return false;
}
async function waitDown(base) {
  for (let i = 0; i < 80; i++) {
    try { await fetch(`${base}/health`); } catch { return true; }
    await sleep(250);
  }
  return false;
}
process.on("exit", () => { for (const p of procs) { try { p.kill(); } catch {} } });

let ipSeq = 1;
async function call(base, method, p, body, token, headers = {}) {
  const res = await fetch(`${base}/api/v1${p}`, {
    method,
    headers: {
      "Content-Type": "application/json", "X-Forwarded-For": `10.77.${Math.floor(ipSeq / 250)}.${ipSeq++ % 250}`,
      ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, body: json, headers: res.headers };
}
const uniq = Date.now();
async function register(base, name, role) {
  const r = await call(base, "POST", "/auth/register", {
    name, email: `${name.toLowerCase()}${uniq}@scale.invalid`, password: "strong-pass-123", ...(role ? { role } : {}),
    ...(role === "VENDOR" || role === "COURIER" ? { acceptTerms: true } : {}),
  });
  return r.body;
}
/** Accepts every blocking agreement of the account (the API answers 428 until then). */
async function acceptAgreements(base, token) {
  const r = await call(base, "GET", "/me/agreements", undefined, token);
  for (const d of r.body?.required ?? []) {
    if (!d.accepted && d.currentVersion) await call(base, "POST", "/me/agreements/accept", { doc: d.doc, version: d.currentVersion }, token);
  }
}
function connect(base, token) {
  return new Promise((resolve) => {
    const s = io(base, { auth: { token }, transports: ["websocket"], reconnection: false });
    s.events = [];
    s.onAny((ev, data) => s.events.push({ ev, data }));
    s.on("connect", () => resolve(s));
    s.on("connect_error", (e) => { s.connectError = e.message; resolve(s); });
  });
}
const waitFor = async (fn, ms = 5000) => {
  for (let t = 0; t < ms; t += 100) { if (fn()) return true; await sleep(100); }
  return !!fn();
};

(async () => {
  console.log(`\nScale checks — ${REDIS ? `WITH Redis (${REDIS})` : "without Redis"}; database ${DB_NAME}`);
  const apiA = startApi(4565);
  check("API instance A starts", await waitUp(A), apiA.output.slice(-800));
  if (fail) { console.log(apiA.output); process.exit(1); }

  console.log("\n— Health, request id, compression, caching");
  const health = await (await fetch(`${A}/health`)).json();
  check("/health is liveness", health.ok === true && health.status === "healthy");
  const ready = await fetch(`${A}/health/ready`);
  const readyBody = await ready.json();
  check("/health/ready checks the database (and Redis when configured)", ready.status === 200 && readyBody.database === "up" && readyBody.redis === (REDIS ? "up" : "not configured"), readyBody);
  const rid = await fetch(`${A}/health`, { headers: { "X-Request-Id": "scale-test-request-0001" } });
  check("a well-formed X-Request-Id is echoed back", rid.headers.get("x-request-id") === "scale-test-request-0001");
  const bad = await fetch(`${A}/health`, { headers: { "X-Request-Id": "bad id\twith spaces" } });
  check("a malformed X-Request-Id is replaced by a new UUID", /^[0-9a-f-]{36}$/.test(bad.headers.get("x-request-id") || ""), bad.headers.get("x-request-id"));
  const br = await fetch(`${A}/api/v1/stores?limit=50`, { headers: { "Accept-Encoding": "br" } });
  check("public JSON is brotli-compressed when the client accepts br", br.headers.get("content-encoding") === "br");
  const gz = await fetch(`${A}/api/v1/stores?limit=50`, { headers: { "Accept-Encoding": "gzip" } });
  check("…and gzip otherwise", gz.headers.get("content-encoding") === "gzip");
  const cc = br.headers.get("cache-control") || "";
  check("anonymous public GETs are cacheable briefly with stale-while-revalidate", /public, max-age=\d+, stale-while-revalidate=\d+/.test(cc), cc);
  const etag = br.headers.get("etag");
  // Plain http (fetch adds "Cache-Control: no-cache" to conditional requests, which rightly forces a 200)
  const notModified = await new Promise((resolve) => require("http").get(`${A}/api/v1/stores?limit=50`, { headers: { "If-None-Match": etag || "" } }, (r) => { r.resume(); resolve(r.statusCode); }).on("error", () => resolve(0)));
  check("an unchanged public GET answers 304 to its ETag", !!etag && notModified === 304, notModified);
  const legal = await fetch(`${A}/legal/privacy`);
  check("legal pages carry a Cache-Control header", /max-age/.test(legal.headers.get("cache-control") || ""), legal.headers.get("cache-control"));

  console.log("\n— Accounts and a shop for the checks");
  const cust = await register(A, "ScaleCustomer");
  const vend = await register(A, "ScaleVendor", "VENDOR");
  const cour = await register(A, "ScaleCourier", "COURIER");
  const adm = await register(A, "ScaleAdmin");
  check("test accounts are created", !!(cust?.accessToken && vend?.accessToken && cour?.accessToken && adm?.accessToken), { cust, vend });
  sql(`UPDATE "User" SET role='ADMIN' WHERE id=${adm.user.id}`);
  const adminToken = (await call(A, "POST", "/auth/login", { email: `scaleadmin${uniq}@scale.invalid`, password: "strong-pass-123" })).body.accessToken;
  await acceptAgreements(A, cust.accessToken);
  await acceptAgreements(A, cour.accessToken);
  const storeId = Number(sql(`INSERT INTO "Store"("ownerId", name, category, "isVerified", latitude, longitude, address, "updatedAt")
    VALUES (${vend.user.id}, 'Scale Test Shop ${uniq}', 'APPAREL', true, 60.17, 24.94, 'Testikatu 1, Helsinki', now()) RETURNING id`).split("\n")[0]);
  const productId = Number(sql(`INSERT INTO "Product"("storeId", name, category, "salePriceCents", "stockQuantity", "updatedAt")
    VALUES (${storeId}, 'Scale test jacket', 'Jacket', 4900, 1000, now()) RETURNING id`).split("\n")[0]);
  check("a verified shop with a product exists", storeId > 0 && productId > 0);
  const basket = { storeId, items: [{ productId, quantity: 1 }], deliveryLat: 60.171, deliveryLng: 24.941, deliveryAddress: "Mannerheimintie 1, Helsinki" };
  const authed = await fetch(`${A}/api/v1/stores/${storeId}`, { headers: { Authorization: `Bearer ${cust.accessToken}` } });
  check("signed-in GETs are private, never shared-cacheable", /private/.test(authed.headers.get("cache-control") || ""), authed.headers.get("cache-control"));

  console.log("\n— Metrics");
  check("/admin/metrics needs a sign-in", (await call(A, "GET", "/admin/metrics")).status === 401);
  check("/admin/metrics refuses non-admins", (await call(A, "GET", "/admin/metrics", undefined, cust.accessToken)).status === 403);
  const m = await call(A, "GET", "/admin/metrics", undefined, adminToken);
  check("/admin/metrics shows event-loop lag, heap, DB pool, request and error rates, sockets",
    m.status === 200 && typeof m.body.eventLoopLag?.p99Ms === "number" && typeof m.body.memory?.heapUsedMb === "number" &&
    typeof m.body.db?.pool?.max === "number" && typeof m.body.requests?.sinceStart?.errorRate5xx === "number" &&
    Array.isArray(m.body.requests?.currentWindow?.routes) && typeof m.body.sockets?.connectionsThisInstance === "number", m.body);
  check("routes are reported by pattern, not raw URL", (m.body.requests?.currentWindow?.routes ?? []).some((r) => r.route === "GET /api/v1/stores/:id(\\d+)"), m.body.requests?.currentWindow?.routes?.map((r) => r.route));
  check("METRICS_TOKEN lets a scraper read the metrics", (await call(A, "GET", "/admin/metrics", undefined, METRICS_TOKEN)).status === 200);
  check("a wrong metrics token is refused", (await call(A, "GET", "/admin/metrics", undefined, "wrong-token")).status === 401);
  check("metrics report the queue and feature switches", m.body.queue?.backend === (REDIS ? "bullmq" : "in-process") && m.body.features?.redis === !!REDIS, { q: m.body.queue, f: m.body.features });

  console.log("\n— Idempotency-Key");
  const key = `scale-${uniq}-checkout`;
  const o1 = await call(A, "POST", "/orders", basket, cust.accessToken, { "Idempotency-Key": key });
  check("checkout with an Idempotency-Key works", o1.status === 201 && o1.body.order?.id, o1.body);
  const o2 = await call(A, "POST", "/orders", basket, cust.accessToken, { "Idempotency-Key": key });
  check("the same key and body replay the first response (no second order)", o2.status === 201 && o2.body.order?.id === o1.body.order?.id && o2.headers.get("idempotent-replayed") === "true", o2.body);
  const o3 = await call(A, "POST", "/orders", { ...basket, items: [{ productId, quantity: 2 }] }, cust.accessToken, { "Idempotency-Key": key });
  check("the same key with a different body is refused with 422", o3.status === 422, o3.body);
  check("an invalid key is refused with 400", (await call(A, "POST", "/orders", basket, cust.accessToken, { "Idempotency-Key": "has space" })).status === 400);
  const orderCount = Number(sql(`SELECT count(*) FROM "Order" WHERE "userId"=${cust.user.id}`));
  check("only one order exists for the replayed checkout", orderCount === 1, orderCount);
  const k2 = `scale-${uniq}-parallel`;
  const par = await Promise.all([1, 2, 3].map(() => call(A, "POST", "/orders", basket, cust.accessToken, { "Idempotency-Key": k2 })));
  const ids = new Set(par.filter((r) => r.status === 201).map((r) => r.body.order.id));
  check("parallel retries with one key create one order (others replay or get 409)", ids.size === 1 && par.every((r) => r.status === 201 || r.status === 409), par.map((r) => r.status));
  const otherUser = await register(A, "ScaleOther");
  await acceptAgreements(A, otherUser.accessToken);
  const o4 = await call(A, "POST", "/orders", basket, otherUser.accessToken, { "Idempotency-Key": key });
  check("keys are per user: another customer's same key is a new order", o4.status === 201 && o4.body.order?.id !== o1.body.order?.id, o4.body);
  const agreeKey = `scale-${uniq}-agree`;
  const agr = await call(A, "GET", "/me/agreements", undefined, cust.accessToken);
  const doc = agr.body?.required?.[0];
  const ag1 = await call(A, "POST", "/me/agreements/accept", { doc: doc?.doc, version: doc?.currentVersion }, cust.accessToken, { "Idempotency-Key": agreeKey });
  const ag2 = await call(A, "POST", "/me/agreements/accept", { doc: doc?.doc, version: doc?.currentVersion }, cust.accessToken, { "Idempotency-Key": agreeKey });
  check("POST /me/agreements/accept honours Idempotency-Key", ag1.status === 200 && ag2.status === 200 && ag2.headers.get("idempotent-replayed") === "true", { a: ag1.status, b: ag2.status });

  console.log("\n— Pagination");
  const page1 = await call(A, "GET", "/orders?limit=1", undefined, cust.accessToken);
  check("GET /orders?limit=1 returns one order and a cursor", page1.status === 200 && page1.body.orders.length === 1 && typeof page1.body.nextBefore === "number", page1.body?.nextBefore);
  const page2 = await call(A, "GET", `/orders?limit=1&before=${page1.body.nextBefore}`, undefined, cust.accessToken);
  check("…and ?before= gives the next, older page", page2.status === 200 && page2.body.orders.length === 1 && page2.body.orders[0].id < page1.body.orders[0].id, page2.body);
  const allOrders = await call(A, "GET", "/orders", undefined, cust.accessToken);
  check("without paging the list is unchanged (capped) and says there is no next page", allOrders.status === 200 && allOrders.body.orders.length >= 2 && allOrders.body.nextBefore === null, allOrders.body?.nextBefore);
  check("rentals and returns lists are capped and paged too", (await call(A, "GET", "/rentals?limit=5", undefined, cust.accessToken)).status === 200 && (await call(A, "GET", "/returns?limit=5", undefined, cust.accessToken)).status === 200);

  console.log("\n— Scheduler lease (each job runs once across instances)");
  const scheduler = require(path.join(ROOT, "dist", "services", "scheduler.js"));
  const lease = `scale-test-${uniq}`;
  const got = await Promise.all(Array.from({ length: 8 }, () => scheduler.acquireLease(lease, 60_000)));
  check("8 instances racing for one job lease: exactly one wins", got.filter(Boolean).length === 1, got);
  check("a held lease is not taken again before it expires", (await scheduler.acquireLease(lease, 60_000)) === false);

  console.log("\n— Background queue");
  const queue = require(path.join(ROOT, "dist", "lib", "queue.js"));
  let tries = 0, deadTries = 0;
  queue.defineJob("scale-flaky", async () => { tries++; if (tries < 3) throw new Error("transient"); }, { attempts: 4, backoffMs: 50 });
  queue.defineJob("scale-dead", async () => { deadTries++; throw new Error("always fails"); }, { attempts: 2, backoffMs: 50 });
  if (REDIS) queue.startQueueWorker();
  await queue.enqueue("scale-flaky", { n: 1 });
  await queue.enqueue("scale-dead", { n: 2 });
  check("a failing job is retried with backoff until it succeeds", await waitFor(() => tries === 3, 15_000), tries);
  check("a job failing every attempt stops after its attempts (dead letter)", await waitFor(() => deadTries === 2, 15_000) && (await sleep(500), deadTries === 2), deadTries);
  const qs = await queue.queueStats();
  check("the dead letter is counted", qs.local.deadLettered >= 1 && (!REDIS || qs.deadLetters >= 1), qs);
  await queue.stopQueue();

  if (REDIS) {
    console.log("\n— Two instances sharing Redis");
    startApi(4567);
    check("API instance B starts", await waitUp(B));
    // Order with an assigned, approved courier (customer watches on B, courier reports on A)
    await call(A, "GET", "/courier/me", undefined, cour.accessToken);
    const courierId = Number(sql(`UPDATE "Courier" SET "isApproved"=true, "isActive"=true WHERE "userId"=${cour.user.id} RETURNING id`).split("\n")[0]);
    const orderId = o1.body.order.id;
    sql(`UPDATE "Order" SET status='CONFIRMED', "paymentStatus"='SUCCEEDED', "paidAt"=now(), "confirmedAt"=now(), "courierId"=${courierId} WHERE id=${orderId}`);
    const custToken = (await call(A, "POST", "/auth/login", { email: `scalecustomer${uniq}@scale.invalid`, password: "strong-pass-123" })).body.accessToken;
    const sockB = await connect(B, custToken);
    check("customer socket connects to instance B", sockB.connected, sockB.connectError);
    sockB.emit("track:order", orderId);
    await new Promise((r) => sockB.emit("chat:join", orderId, () => r()));
    await sleep(300);
    const tel = await call(A, "POST", "/courier/telemetry", { latitude: 60.172, longitude: 24.942, orderId }, cour.accessToken);
    check("courier location sent to instance A", tel.status === 200, tel.body);
    check("…reaches the customer connected to instance B (Redis adapter)", await waitFor(() => sockB.events.some((e) => e.ev === "courier:location" && e.data.orderId === orderId)), sockB.events.map((e) => e.ev));
    const msg = await call(A, "POST", `/orders/${orderId}/messages`, { text: "Hello from instance A" }, cour.accessToken);
    check("a chat message posted on A reaches the client on B", msg.status < 300 && await waitFor(() => sockB.events.some((e) => e.ev === "chat:message")), { status: msg.status, body: msg.body });
    // The background worker has no socket server: its emits go through the Redis emitter
    const emitter = spawn(process.execPath, ["-e", `const s = require('./dist/lib/socket.js'); s.emitOrderStatus(${orderId}, { status: 'PROCESSING', fromWorker: true }); setTimeout(() => process.exit(0), 500);`], { cwd: ROOT, env: baseEnv, stdio: "ignore" });
    await new Promise((r) => emitter.on("exit", r));
    check("an emit from a process without a socket server (the worker) reaches the client (Redis emitter)", await waitFor(() => sockB.events.some((e) => e.ev === "order:status" && e.data.fromWorker)), sockB.events.map((e) => e.ev));
    sockB.close();

    // Shared rate limit: the sign-in limiter (20 per 15 min per address) counts across both instances
    const ipHdr = { "X-Forwarded-For": "10.250.250.250" };
    const statuses = [];
    for (let i = 0; i < 24; i++) {
      const base = i % 2 ? B : A;
      statuses.push((await call(base, "POST", "/auth/login", { email: `nobody${i}@scale.invalid`, password: "wrong-password" }, undefined, ipHdr)).status);
    }
    check("the sign-in rate limit is shared by both instances (21st attempt overall → 429)", statuses.slice(0, 20).every((s) => s === 401) && statuses.slice(20).every((s) => s === 429), statuses);

    // Session revocation: B caches the session state for 30 s; a password change on A ends it on B at once
    const oldToken = custToken;
    check("the token works on B (state now cached there)", (await call(B, "GET", "/me", undefined, oldToken)).status === 200);
    await sleep(1100); // tokens issued in the same second as the change stay valid by design
    const change = await call(A, "POST", "/auth/password/change", { currentPassword: "strong-pass-123", newPassword: "even-stronger-pass-456" }, oldToken);
    check("password changed on A", change.status === 200, change.body);
    await sleep(300);
    check("…and B refuses the old token immediately (Redis pub/sub, not after 30 s)", (await call(B, "GET", "/me", undefined, oldToken)).status === 401);

    // Idempotency is shared too
    const kx = `scale-${uniq}-cross`;
    const x1 = await call(A, "POST", "/orders", basket, otherUser.accessToken, { "Idempotency-Key": kx });
    const x2 = await call(B, "POST", "/orders", basket, otherUser.accessToken, { "Idempotency-Key": kx });
    check("a retry landing on the other instance replays the first response", x1.status === 201 && x2.status === 201 && x2.body.order?.id === x1.body.order?.id && x2.headers.get("idempotent-replayed") === "true", { x1: x1.body?.order?.id, x2: x2.body?.order?.id });
    const readyB = await (await fetch(`${B}/health/ready`)).json();
    check("readiness on B reports Redis up", readyB.redis === "up", readyB);
  } else {
    console.log("\n— Single instance without Redis (as today)");
    const st = [];
    for (let i = 0; i < 22; i++) st.push((await call(A, "POST", "/auth/login", { email: `nobody${i}@scale.invalid`, password: "wrong-password" }, undefined, { "X-Forwarded-For": "10.251.1.1" })).status);
    check("the in-memory sign-in limiter still applies (21st attempt → 429)", st.slice(0, 20).every((s) => s === 401) && st[20] === 429, st);
    const metricsAgain = await call(A, "GET", "/admin/metrics", undefined, adminToken);
    check("no Redis connection is attempted without REDIS_URL", metricsAgain.body.features?.redis === false && metricsAgain.body.queue?.backend === "in-process");
  }

  console.log("\n— Graceful shutdown");
  const g = startApi(4568, { LOG_LEVEL: "info" }, { ipc: true });
  const G = "http://localhost:4568";
  check("a third instance starts for the shutdown check", await waitUp(G));
  const gsock = await connect(G, adminToken);
  let disconnected = false;
  gsock.on("disconnect", () => (disconnected = true));
  const inflight = fetch(`${G}/api/v1/products/search?q=jacket&size=M&sort=newest`).then((r) => r.status).catch((e) => `error ${e.message}`);
  await sleep(150); // the request has reached the server (a cold search takes about a second)
  const exited = new Promise((r) => g.on("exit", (code) => r(code)));
  g.send("stop");
  const status = await inflight;
  check("a request in flight when SIGTERM arrives still completes", status === 200, { status, out: g.output.slice(-1500) });
  const code = await Promise.race([exited, sleep(20_000).then(() => "timeout")]);
  check("the process exits cleanly (0) after closing sockets, queue, Redis and DB", code === 0, { code, out: g.output.slice(-600) });
  check("connected sockets were closed", disconnected);
  check("the shutdown is logged", /Shutting down gracefully/.test(g.output) && /Shutdown complete/.test(g.output), g.output.slice(-600));
  check("no new connections are accepted afterwards", await waitDown(G));

  console.log(`\n${pass} passed, ${fail} failed`);
  for (const p of procs) { try { p.kill(); } catch {} }
  if (REDIS) { try { require(path.join(ROOT, "dist", "lib", "redis.js")).closeRedis(); } catch {} }
  setTimeout(() => process.exit(fail ? 1 : 0), 300);
})().catch((e) => { console.error(e); process.exit(1); });
