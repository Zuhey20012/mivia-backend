// Runs the API's hot read paths against a seeded THROWAWAY database (see seed-scale.js), records the exact SQL Prisma
// sends, and prints EXPLAIN (ANALYZE, BUFFERS) for each statement: time, rows, and any sequential scan of a big table.
//
//   npm run build
//   DATABASE_URL=postgresql://postgres:test@localhost:56432/malvoya_scale node loadtest/explain-hot-queries.js > explain.txt
//
// The watchdog and payout scans really run (they cancel stale unpaid checkouts of the seeded data, as in production);
// the database name must contain "scale" or "loadtest".
const path = require("path");
const url = process.env.DATABASE_URL || "";
if (!/localhost|127\.0\.0\.1/.test(url) || !/scale|loadtest/i.test(url)) {
  console.error("Refusing: DATABASE_URL must be a local database whose name contains 'scale' or 'loadtest'.");
  process.exit(1);
}
Object.assign(process.env, {
  NODE_ENV: "development", LOG_LEVEL: "error",
  JWT_SECRET: process.env.JWT_SECRET || "loadtest-only-access-secret-0123456789abcdef",
  JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || "loadtest-only-refresh-secret-0123456789abcdef",
  STRIPE_SECRET_KEY: "sk_test_123", STRIPE_API_BASE: process.env.STRIPE_API_BASE || "http://localhost:12111",
  REDIS_URL: "",
});

// Record every statement while `label` is set
const pg = require("pg");
let label = null;
const captured = [];
const origQuery = pg.Client.prototype.query;
pg.Client.prototype.query = function (config, values, cb) {
  if (label) {
    const text = typeof config === "string" ? config : config?.text;
    const vals = typeof config === "object" && config?.values ? config.values : Array.isArray(values) ? values : [];
    if (text && /^\s*SELECT/i.test(text)) captured.push({ label, text, values: vals });
  }
  return origQuery.call(this, config, values, cb);
};

const dist = (...p) => require(path.join(__dirname, "..", "dist", ...p));

(async () => {
  const { prisma, pgPool } = dist("lib", "prisma.js");
  const orders = dist("modules", "orders", "orders.service.js");
  const products = dist("modules", "products", "products.service.js");
  const stores = dist("modules", "stores", "stores.service.js");
  const drops = dist("modules", "drops", "drops.service.js");
  const analytics = dist("modules", "admin", "analytics.js");
  const { runOrderWatchdog } = dist("services", "orderWatchdog.js");
  const payouts = dist("modules", "payouts", "payouts.service.js");

  // The busiest seeded customer, store owner and courier
  const one = async (sql) => (await prisma.$queryRawUnsafe(sql))[0];
  const cust = await one(`SELECT "userId" AS id FROM "Order" GROUP BY 1 ORDER BY count(*) DESC LIMIT 1`);
  const vend = await one(`SELECT s."ownerId" AS id FROM "Order" o JOIN "Store" s ON s.id = o."storeId" GROUP BY 1 ORDER BY count(*) DESC LIMIT 1`);
  const cour = await one(`SELECT c."userId" AS id FROM "Courier" c JOIN "Order" o ON o."courierId" = c.id WHERE c."isActive" GROUP BY 1 ORDER BY count(*) DESC LIMIT 1`);
  const admin = { id: 1, role: "ADMIN", email: "admin@loadtest.invalid" };

  const run = async (name, fn) => {
    label = name;
    const t = Date.now();
    try { await fn(); } catch (e) { console.log(`(${name} threw: ${e.message})`); }
    label = null;
    console.log(`# ${name}: service call ${Date.now() - t} ms`);
  };
  await run("orders list (customer)", () => orders.listOrdersFor({ id: cust.id, role: "CUSTOMER", email: "" }));
  await run("orders list (store)", () => orders.listOrdersFor({ id: vend.id, role: "VENDOR", email: "" }));
  await run("orders list (courier)", () => orders.listOrdersFor({ id: cour.id, role: "COURIER", email: "" }));
  await run("courier available jobs", () => orders.listAvailableOrders(cour.id));
  await run("drops feed (for you)", () => drops.getFeed({ mode: "foryou", limit: 10, lat: 60.17, lng: 24.94 }, null));
  await run("drops feed (latest)", () => drops.getFeed({ mode: "latest", limit: 10, lat: null, lng: null }, null));
  await run("product search 'wool'", () => products.searchProducts({ q: "wool", sort: "relevance", page: 1, limit: 20 }));
  await run("product search size M", () => products.searchProducts({ size: "M", sort: "newest", page: 1, limit: 20 }));
  await run("product search page 50", () => products.searchProducts({ sort: "newest", page: 50, limit: 20 }));
  await run("stores list", () => stores.getStores({ page: "1", limit: "20", lat: "60.17", lng: "24.94" }));
  await run("analytics 28 days", () => analytics.analytics(undefined, undefined));
  await run("watchdog scans", () => runOrderWatchdog());
  await run("payouts due", () => payouts.processDuePayouts());

  console.log("\n================ EXPLAIN (ANALYZE, BUFFERS) ================");
  const big = new Set(["Order", "OrderItem", "Product", "Payout", "Drop", "ProductVariant", "User", "Return", "PriceChange", "DropLike", "DropView"]);
  const seen = new Set();
  const client = new pg.Client({ connectionString: url });
  await client.connect();
  for (const q of captured) {
    const key = q.label + q.text;
    if (seen.has(key)) continue;
    seen.add(key);
    let plan;
    try {
      const r = await origQuery.call(client, { text: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${q.text}`, values: q.values });
      plan = r.rows[0]["QUERY PLAN"][0];
    } catch (e) {
      console.log(`\n[${q.label}] could not EXPLAIN: ${e.message}`);
      continue;
    }
    const seqs = [];
    const walk = (n) => {
      if (n["Node Type"] === "Seq Scan" && big.has(n["Relation Name"])) seqs.push(`${n["Relation Name"]} (${n["Actual Rows"] * (n["Actual Loops"] || 1)} rows out, ${n["Rows Removed by Filter"] ?? 0} filtered)`);
      for (const c of n.Plans || []) walk(c);
    };
    walk(plan.Plan);
    const ms = plan["Execution Time"].toFixed(2);
    console.log(`\n[${q.label}] ${ms} ms, ${plan.Plan["Actual Rows"]} rows, top: ${plan.Plan["Node Type"]}${seqs.length ? `\n  SEQ SCAN: ${seqs.join("; ")}` : ""}`);
    console.log("  " + q.text.replace(/\s+/g, " ").slice(0, 400));
    // SHOW_PLAN_MS=10: also print the full text plan of every statement slower than that
    if (plan["Execution Time"] > Number(process.env.SHOW_PLAN_MS || Infinity)) {
      const t = await origQuery.call(client, { text: `EXPLAIN (ANALYZE, BUFFERS) ${q.text}`, values: q.values });
      console.log(t.rows.map((r) => "    | " + r["QUERY PLAN"]).join("\n"));
    }
  }
  await client.end();
  await prisma.$disconnect();
  await pgPool.end();
})().catch((e) => { console.error(e); process.exit(1); });
