// Fills a THROWAWAY database with realistic volume for EXPLAIN audits and load tests:
// ~2 000 customers, 500 approved stores, 20 000 products (a quarter with size options), 300 couriers (half online
// around Helsinki), 50 000 orders over 90 days (+ ~100 000 items, payouts) and 3 000 drops.
//
//   DATABASE_URL=postgresql://postgres:test@localhost:56432/malvoya_scale node loadtest/seed-scale.js
//
// Refuses to run unless the database is on this machine and its name contains "scale" or "loadtest", so it can never
// touch production or the shared e2e database. Every seeded account uses @loadtest.invalid addresses.
const { Client } = require("pg");
const bcrypt = require("bcryptjs");

const url = process.env.DATABASE_URL || "";
let parsed;
try { parsed = new URL(url); } catch { parsed = null; }
const dbName = parsed ? parsed.pathname.replace(/^\//, "") : "";
if (!parsed || !["localhost", "127.0.0.1", "[::1]"].includes(parsed.hostname) || !/scale|loadtest/i.test(dbName)) {
  console.error("Refusing to seed: DATABASE_URL must point at a local database whose name contains 'scale' or 'loadtest'.");
  process.exit(1);
}

const N = {
  customers: Number(process.env.SEED_CUSTOMERS || 2000),
  stores: Number(process.env.SEED_STORES || 500),
  productsPerStore: Number(process.env.SEED_PRODUCTS_PER_STORE || 40),
  couriers: Number(process.env.SEED_COURIERS || 300),
  orders: Number(process.env.SEED_ORDERS || 50000),
  drops: Number(process.env.SEED_DROPS || 3000),
};

(async () => {
  const db = new Client({ connectionString: url });
  await db.connect();
  const t0 = Date.now();
  const step = async (label, sql, params = []) => {
    const t = Date.now();
    const r = await db.query(sql, params);
    console.log(`${label.padEnd(28)} ${String(r.rowCount ?? "").padStart(7)} rows  ${((Date.now() - t) / 1000).toFixed(1)} s`);
  };
  const already = await db.query(`SELECT count(*)::int AS n FROM "User" WHERE email LIKE 'lt-%@loadtest.invalid'`);
  if (already.rows[0].n > 0) {
    console.log("Load-test data is already there; nothing to do. (Recreate the database to seed again.)");
    await db.end();
    return;
  }
  // The password of every seeded account (local test data only)
  const hash = await bcrypt.hash("loadtest-password-1", 10);

  await db.query("BEGIN");
  await step("customers", `
    INSERT INTO "User"(email, name, "passwordHash", role, latitude, longitude, locale, "updatedAt")
    SELECT 'lt-c' || g || '@loadtest.invalid', 'Load Customer ' || g, $1, 'CUSTOMER',
           60.15 + random() * 0.12, 24.85 + random() * 0.2, CASE WHEN random() < 0.6 THEN 'fi' ELSE 'en' END, now()
    FROM generate_series(1, ${N.customers}) g`, [hash]);
  await step("vendors", `
    INSERT INTO "User"(email, name, "passwordHash", role, "updatedAt")
    SELECT 'lt-v' || g || '@loadtest.invalid', 'Load Vendor ' || g, $1, 'VENDOR', now() FROM generate_series(1, ${N.stores}) g`, [hash]);
  await step("stores", `
    INSERT INTO "Store"("ownerId", name, description, category, "isVerified", latitude, longitude, address, phone,
                        rating, "totalReviews", "prepMinutes", "updatedAt", "createdAt")
    SELECT u.id, 'Loadtest Shop ' || u.id, 'Second-hand and new fashion in Helsinki',
           (ARRAY['APPAREL','THRIFT','ACCESSORIES','COSMETICS','HANDMADE'])[1 + floor(random() * 5)::int]::"StoreCategory",
           true, 60.15 + random() * 0.12, 24.85 + random() * 0.2, 'Testikatu ' || u.id || ', 00100 Helsinki', '+358401234567',
           round((3 + random() * 2)::numeric, 1), floor(random() * 200)::int, 10, now(), now() - random() * interval '200 days'
    FROM "User" u WHERE u.email LIKE 'lt-v%@loadtest.invalid'`);
  await step("products", `
    INSERT INTO "Product"("storeId", name, description, category, condition, images, tags, "salePriceCents",
                          "stockQuantity", "isAvailable", "isSecondHand", "isEcoFriendly", "isFeatured", "updatedAt", "createdAt")
    SELECT s.id,
           (ARRAY['Vintage','Wool','Linen','Denim','Silk','Organic','Classic','Oversized','Cropped','Pleated'])[1 + floor(random() * 10)::int] || ' ' ||
           (ARRAY['dress','jacket','coat','shirt','jeans','skirt','sweater','bag','scarf','boots','blazer','top'])[1 + floor(random() * 12)::int] || ' ' || g,
           'Carefully kept piece in good condition. Measurements in the photos. ' || md5(random()::text),
           (ARRAY['Dress','Jacket','Coat','Shirt','Jeans','Skirt','Sweater','Bag','Scarf','Shoes'])[1 + floor(random() * 10)::int],
           (ARRAY['NEW','LIKE_NEW','GOOD','FAIR'])[1 + floor(random() * 4)::int]::"ProductCondition",
           ARRAY['https://res.cloudinary.com/testcloud/image/upload/c_limit,w_1200,q_auto,f_auto/malvoya/products/s' || s.id || '/lt' || g || '.jpg'],
           ARRAY[(ARRAY['vintage','handmade','eco-friendly','designer','wool'])[1 + floor(random() * 5)::int]],
           (900 + floor(random() * 15000))::int, (1 + floor(random() * 20))::int, random() > 0.03,
           random() < 0.4, random() < 0.2, random() < 0.05, now(), now() - random() * interval '120 days'
    FROM "Store" s CROSS JOIN generate_series(1, ${N.productsPerStore}) g
    WHERE s.name LIKE 'Loadtest Shop %'`);
  await step("variants", `
    INSERT INTO "ProductVariant"("productId", size, color, stock, "priceAdjustCents")
    SELECT p.id, sz, (ARRAY['black','white','blue','green','beige'])[1 + floor(random() * 5)::int], floor(random() * 5)::int, 0
    FROM "Product" p CROSS JOIN unnest(ARRAY['S','M','L']) sz
    WHERE p."storeId" IN (SELECT id FROM "Store" WHERE name LIKE 'Loadtest Shop %') AND p.id % 4 = 0`);
  await step("courier users", `
    INSERT INTO "User"(email, name, "passwordHash", role, "updatedAt")
    SELECT 'lt-k' || g || '@loadtest.invalid', 'Load Courier ' || g, $1, 'COURIER', now() FROM generate_series(1, ${N.couriers}) g`, [hash]);
  await step("couriers", `
    INSERT INTO "Courier"("userId", name, "isApproved", "isActive", latitude, longitude, "locationAt", rating, "totalRatings", "updatedAt")
    SELECT u.id, u.name, true, (u.id % 2 = 0),
           CASE WHEN u.id % 2 = 0 THEN 60.15 + random() * 0.12 END, CASE WHEN u.id % 2 = 0 THEN 24.85 + random() * 0.2 END,
           CASE WHEN u.id % 2 = 0 THEN now() END, round((4 + random())::numeric, 1), floor(random() * 300)::int, now()
    FROM "User" u WHERE u.email LIKE 'lt-k%@loadtest.invalid'`);

  // Lookup tables: id arrays to draw from, and each store's first product id (products of a store are consecutive)
  await db.query(`CREATE TEMP TABLE lt_ids AS SELECT
      (SELECT array_agg(id) FROM "User" WHERE email LIKE 'lt-c%@loadtest.invalid') AS customers,
      (SELECT array_agg(id) FROM "Store" WHERE name LIKE 'Loadtest Shop %') AS stores,
      (SELECT array_agg(id) FROM "Courier" WHERE name LIKE 'Load Courier %') AS couriers`);
  await db.query(`CREATE TEMP TABLE lt_store_products AS SELECT "storeId", min(id) AS first_id, count(*)::int AS n FROM "Product"
      WHERE "storeId" IN (SELECT unnest(stores) FROM lt_ids) GROUP BY "storeId"`);

  // Status mix: 75 % delivered, 12 % cancelled, 8 % refunded-after-return-ish (delivered), the rest in flight
  await step("orders", `
    INSERT INTO "Order"("userId", "storeId", "courierId", status, fulfilment, "subtotalCents", "deliveryFeeCents", "commissionCents",
                        "sellerPayoutCents", "totalCents", "paymentStatus", "paidAt", "confirmedAt", "acceptedAt", "pickedUpAt",
                        "deliveredAt", "cancelledAt", "cancelReason", "readyAt", "courierFeeCents", "stripePaymentIntentId",
                        "deliveryAddress", "deliveryLat", "deliveryLng", "etaMinutes", "createdAt", "updatedAt")
    SELECT x.customer, x.store,
           CASE WHEN x.kind IN ('DELIVERED','SHIPPED') THEN x.courier END,
           x.kind::"OrderStatus",
           CASE WHEN random() < 0.08 THEN 'PICKUP' ELSE 'DELIVERY' END::"Fulfilment",
           x.sub, 390, round(x.sub * 0.1)::int, x.sub - round(x.sub * 0.1)::int, x.sub + 390,
           (CASE WHEN x.kind = 'PENDING' AND x.g % 2 = 0 THEN 'PENDING' ELSE 'SUCCEEDED' END)::"PaymentStatus",
           CASE WHEN NOT (x.kind = 'PENDING' AND x.g % 2 = 0) THEN x.created + interval '1 minute' END,
           CASE WHEN x.kind IN ('CONFIRMED','PROCESSING','SHIPPED','DELIVERED') THEN x.created + interval '3 minutes' END,
           CASE WHEN x.kind IN ('SHIPPED','DELIVERED') THEN x.created + interval '6 minutes' END,
           CASE WHEN x.kind IN ('SHIPPED','DELIVERED') THEN x.created + interval '20 minutes' END,
           CASE WHEN x.kind = 'DELIVERED' THEN x.created + interval '40 minutes' END,
           CASE WHEN x.kind = 'CANCELLED' THEN x.created + interval '10 minutes' END,
           CASE WHEN x.kind = 'CANCELLED' THEN (ARRAY['Store did not respond','Declined by store','No courier found','Cancelled by customer'])[1 + floor(random() * 4)::int] END,
           CASE WHEN x.kind IN ('PROCESSING','SHIPPED','DELIVERED') THEN x.created + interval '15 minutes' END,
           650, 'pi_lt_' || x.g, 'Asiakaskatu ' || x.g || ', Helsinki', 60.15 + random() * 0.12, 24.85 + random() * 0.2, 35,
           x.created, x.created + interval '40 minutes'
    FROM (
      SELECT g, r,
             ids.customers[1 + floor(random() * array_length(ids.customers, 1))::int] AS customer,
             ids.stores[1 + floor(random() * array_length(ids.stores, 1))::int] AS store,
             ids.couriers[1 + floor(random() * array_length(ids.couriers, 1))::int] AS courier,
             (1500 + floor(random() * 12000))::int AS sub,
             CASE WHEN r < 0.80 THEN 'DELIVERED' WHEN r < 0.92 THEN 'CANCELLED' WHEN r < 0.95 THEN 'SHIPPED'
                  WHEN r < 0.97 THEN 'PROCESSING' WHEN r < 0.985 THEN 'CONFIRMED' ELSE 'PENDING' END AS kind,
             -- in-flight orders are recent, finished ones spread over 90 days
             CASE WHEN r >= 0.92 THEN now() - random() * interval '3 hours' ELSE now() - random() * interval '90 days' END AS created
      FROM (SELECT g, random() AS r FROM generate_series(1, ${N.orders}) g) gg, lt_ids ids
    ) x`);
  await step("order items", `
    INSERT INTO "OrderItem"("orderId", "productId", quantity, "unitCents")
    SELECT o.id, sp.first_id + floor(random() * sp.n)::int, 1, (o."subtotalCents" / k.cnt)::int
    FROM "Order" o
    JOIN lt_store_products sp ON sp."storeId" = o."storeId"
    CROSS JOIN LATERAL (SELECT 1 + (o.id % 3) AS cnt) k
    CROSS JOIN LATERAL generate_series(1, k.cnt) i
    WHERE o."stripePaymentIntentId" LIKE 'pi_lt_%'`);
  await step("store payouts", `
    INSERT INTO "Payout"("orderId", party, "storeId", "amountCents", status, "releaseAt", "paidAt", "updatedAt", "createdAt")
    SELECT o.id, 'STORE', o."storeId", o."sellerPayoutCents",
           (CASE WHEN o."deliveredAt" + interval '15 days' < now() THEN 'PAID' ELSE 'SCHEDULED' END)::"PayoutStatus",
           o."deliveredAt" + interval '15 days', CASE WHEN o."deliveredAt" + interval '15 days' < now() THEN o."deliveredAt" + interval '15 days' END,
           now(), o."deliveredAt"
    FROM "Order" o WHERE o.status = 'DELIVERED' AND o."stripePaymentIntentId" LIKE 'pi_lt_%'`);
  await step("courier payouts", `
    INSERT INTO "Payout"("orderId", party, "courierId", "amountCents", status, "releaseAt", "paidAt", "updatedAt", "createdAt")
    SELECT o.id, 'COURIER', o."courierId", o."courierFeeCents", 'PAID', o."deliveredAt", o."deliveredAt", now(), o."deliveredAt"
    FROM "Order" o WHERE o.status = 'DELIVERED' AND o."courierId" IS NOT NULL AND o."stripePaymentIntentId" LIKE 'pi_lt_%'`);
  await step("drops", `
    INSERT INTO "Drop"("storeId", "productId", caption, "mediaKind", "mediaPublicId", status, "likeCount", "viewCount",
                       "shareCount", "completeCount", "publishedAt", "rightsConfirmedAt", "updatedAt", "createdAt")
    SELECT sp."storeId", sp.first_id + floor(random() * sp.n)::int, 'New in: ' || g, 'IMAGE',
           'malvoya/drops/s' || sp."storeId" || '/lt-drop-' || g, 'READY', floor(random() * 300)::int, floor(random() * 5000)::int,
           floor(random() * 50)::int, floor(random() * 1000)::int, t, t, now(), t
    FROM generate_series(1, ${N.drops}) g
    CROSS JOIN LATERAL (SELECT * FROM lt_store_products ORDER BY "storeId" OFFSET (floor(random() * ${N.stores}) + g * 0)::int LIMIT 1) sp
    CROSS JOIN LATERAL (SELECT now() - random() * interval '45 days' + g * interval '0 s' AS t) tt`);
  await db.query("COMMIT");
  await step("analyze", "ANALYZE");
  console.log(`Done in ${((Date.now() - t0) / 1000).toFixed(1)} s. Every seeded account's password: loadtest-password-1`);
  await db.end();
})().catch(async (e) => {
  console.error(e.message);
  process.exit(1);
});
