// End-to-end test for API v2.9 against a local API + throwaway Postgres + stripe-mock + Cloudinary mock.
const { execSync, spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { io } = require("socket.io-client");

const BASE = "http://localhost:4555";
const API = `${BASE}/api/v1`;
const WHSEC = "whsec_test_offline_secret";
const CLD_SECRET = "cld_test_secret";
let pass = 0, fail = 0;

function check(name, cond, extra) {
  if (cond) { pass++; console.log(`  ✓ ${name}`); }
  else { fail++; console.log(`  ✗ ${name}`, extra !== undefined ? JSON.stringify(extra).slice(0, 400) : ""); }
}
function sql(q) {
  return execSync(`docker exec -i malvoya-test-db psql -U postgres -d malvoya_test -tA`, { input: q }).toString().trim();
}
let ipSeq = 1;
async function callAt(api, method, path, body, token, raw) {
  const res = await fetch(`${api}${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      // Different client address per call, so the strict sign-in limiter does not trip during the test
      "X-Forwarded-For": `10.9.${Math.floor(ipSeq / 250)}.${ipSeq++ % 250}`,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(raw?.headers || {}),
    },
    body: raw?.body ?? (body ? JSON.stringify(body) : undefined),
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, body: json };
}
const call = (...args) => callAt(API, ...args);

// A second API instance with the fee levers switched on (same database), started for the fee checks only
const testEnv = Object.fromEntries(fs.readFileSync(path.join(__dirname, "test.env"), "utf8").split(/\r?\n/)
  .filter((l) => l && !l.startsWith("#") && l.includes("="))
  .map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
const FEE_BASE = "http://localhost:4556";
const FEE_API = `${FEE_BASE}/api/v1`;
let feeApi = null;
async function startFeeApi(extraEnv) {
  // A previous instance may still be shutting down: wait until the port is free
  for (let i = 0; i < 40; i++) {
    try { await fetch(`${FEE_BASE}/health`); await new Promise((r) => setTimeout(r, 250)); } catch { break; }
  }
  feeApi = spawn(process.execPath, ["dist/index.js"], {
    cwd: path.join(__dirname, "..", ".."),
    env: { ...process.env, ...testEnv, PORT: "4556", PUBLIC_API_URL: FEE_BASE, DISABLE_SCHEDULER: "true", ...extraEnv },
    stdio: "ignore",
  });
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(`${FEE_BASE}/health`)).ok) return true; } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  return false;
}
process.on("exit", () => { if (feeApi) feeApi.kill(); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Finnish wall-clock date/time/weekday of an instant (scheduled delivery slots are in Europe/Helsinki)
function hel(d = new Date()) {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Helsinki", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", weekday: "short", hourCycle: "h23" }).formatToParts(d);
  const g = (t) => p.find((x) => x.type === t).value;
  return { date: `${g("year")}-${g("month")}-${g("day")}`, time: `${g("hour")}:${g("minute")}`, wd: g("weekday").toLowerCase().slice(0, 3) };
}
function connect(token) {
  return new Promise((resolve) => {
    const s = io(BASE, { auth: { token }, transports: ["websocket"], reconnection: false });
    s.events = [];
    s.onAny((ev, data) => s.events.push({ ev, data }));
    s.on("connect", () => resolve(s));
    s.on("connect_error", (e) => { s.connectError = e.message; resolve(s); });
  });
}
function signedWebhook(event) {
  const payload = JSON.stringify(event);
  const t = Math.floor(Date.now() / 1000);
  const sig = crypto.createHmac("sha256", WHSEC).update(`${t}.${payload}`).digest("hex");
  return { body: payload, headers: { "stripe-signature": `t=${t},v1=${sig}` } };
}
const uniq = Date.now();
const sha1 = (x) => crypto.createHash("sha1").update(x).digest("hex");
const uploadSig = (publicId, version) => sha1(`public_id=${publicId}&version=${version}${CLD_SECRET}`);
const ownImage = (storeId, name) => `https://res.cloudinary.com/testcloud/image/upload/c_limit,w_1200,q_auto,f_auto/malvoya/products/s${storeId}/${name}`;
async function seedResource(publicId, info) {
  await fetch("http://localhost:12222/__seed", { method: "POST", body: JSON.stringify({ publicId, info }) });
}
async function register(name, role, extra = {}) {
  const r = await call("POST", "/auth/register", { name, email: `${name.toLowerCase().replace(/\W/g, "")}${uniq}@example.fi`, password: "strong-pass-123", ...(role ? { role } : {}), ...extra });
  return r.body;
}

(async () => {
  console.log("\n— Auth");
  const regA = await call("POST", "/auth/register", { name: "Aino Korhonen", email: `aino${uniq}@example.fi`, password: "correct-horse-1" });
  check("customer can register", regA.status === 201 && regA.body.accessToken, regA);
  const takeover = await call("POST", "/auth/register", { name: "Evil", email: `aino${uniq}@example.fi`, password: "whatever12", role: "VENDOR" });
  check("register with existing email is refused and returns no tokens", takeover.status === 409 && !takeover.body.accessToken, takeover);
  check("cannot self-register as ADMIN", (await call("POST", "/auth/register", { name: "X", email: `x${uniq}@example.fi`, password: "whatever12", role: "ADMIN" })).status === 400);
  check("wrong password rejected", (await call("POST", "/auth/login", { email: `aino${uniq}@example.fi`, password: "wrong-password" })).status === 401);
  const loginA = await call("POST", "/auth/login", { email: `AINO${uniq}@example.fi`, password: "correct-horse-1" });
  check("login works (case-insensitive email)", loginA.status === 200 && loginA.body.accessToken);
  const tokenA = loginA.body.accessToken;
  const r1 = await call("POST", "/auth/refresh", { refreshToken: loginA.body.refreshToken });
  const r2 = await call("POST", "/auth/refresh", { refreshToken: loginA.body.refreshToken });
  check("refresh token rotation (single use)", r1.status === 200 && r2.status === 401);

  // Verified sign-ins (one-time code here; Google, Apple and Firebase phone share the rule) must not
  // open an account made by /register: nobody proved that its email or phone belongs to them.
  const plantCode = (target, code) => sql(`INSERT INTO "OtpCode" (target, "codeHash", "expiresAt")
    VALUES ('${target}', '${crypto.createHash("sha256").update(`${target}:${code}`).digest("hex")}', now() + interval '10 minutes')
    ON CONFLICT (target) DO UPDATE SET "codeHash" = EXCLUDED."codeHash", attempts = 0, "expiresAt" = EXCLUDED."expiresAt"`);
  plantCode(`aino${uniq}@example.fi`, "123456");
  const preHijackEmail = await call("POST", "/auth/otp/verify", { target: `aino${uniq}@example.fi`, code: "123456" });
  check("code sign-in does not open a registered account (unproven email)", preHijackEmail.status === 409 && !preHijackEmail.body.accessToken, preHijackEmail);
  const phoneP = `+35840${String(uniq).slice(-7)}`;
  await call("POST", "/auth/register", { name: "Pre Hijacker", email: `prehijack${uniq}@example.fi`, phone: phoneP, password: "strong-pass-123" });
  plantCode(phoneP, "654321");
  const preHijackPhone = await call("POST", "/auth/otp/verify", { phone: phoneP, code: "654321" });
  check("code sign-in does not open a registered account (unproven phone)", preHijackPhone.status === 409 && !preHijackPhone.body.accessToken, preHijackPhone);
  plantCode(`otp${uniq}@example.fi`, "111111");
  const codeNew = await call("POST", "/auth/otp/verify", { target: `otp${uniq}@example.fi`, code: "111111" });
  plantCode(`otp${uniq}@example.fi`, "222222");
  const codeAgain = await call("POST", "/auth/otp/verify", { target: `otp${uniq}@example.fi`, code: "222222" });
  const rename = await call("PATCH", "/me/profile", { name: "  Otto Koodi  " }, codeNew.body.accessToken);
  check("users can change their display name", rename.status === 200 && rename.body.user?.name === "Otto Koodi", rename.body);
  check("an empty name is refused", (await call("PATCH", "/me/profile", { name: "   " }, codeNew.body.accessToken)).status === 400);
  check("changing a name needs a signed-in user", (await call("PATCH", "/me/profile", { name: "X" })).status === 401);
  check("Google cannot be unlinked from an account without a password", (await call("DELETE", "/auth/google/link", null, codeNew.body.accessToken)).status === 409);
  check("code sign-in creates an account and returns to it", codeNew.status === 200 && codeAgain.status === 200 && codeAgain.body.user?.id === codeNew.body.user?.id, [codeNew, codeAgain]);
  check("password login still works for the registered account", (await call("POST", "/auth/login", { email: `aino${uniq}@example.fi`, password: "correct-horse-1" })).status === 200);

  // Linking Google (the e2e API has no GOOGLE_CLIENT_ID, so token checks stop at 503; the link itself is set in SQL)
  check("sessions say whether Google is linked", regA.body.user?.googleLinked === false, regA.body.user);
  check("linking Google needs a signed-in user", (await call("POST", "/auth/google/link", { idToken: "x" })).status === 401);
  check("linking Google needs an idToken", (await call("POST", "/auth/google/link", {}, tokenA)).status === 400);
  check("linking Google without GOOGLE_CLIENT_ID is unavailable, not a crash", (await call("POST", "/auth/google/link", { idToken: "x" }, tokenA)).status === 503);
  sql(`update "User" set "googleSub" = 'google-sub-${uniq}' where id = ${regA.body.user.id}`);
  const relogin = await call("POST", "/auth/login", { email: `aino${uniq}@example.fi`, password: "correct-horse-1" });
  const unlink = await call("DELETE", "/auth/google/link", null, tokenA);
  check("session shows a linked Google account; unlinking clears it", relogin.body.user?.googleLinked === true && unlink.status === 200 && unlink.body.googleLinked === false && sql(`select "googleSub" is null from "User" where id = ${regA.body.user.id}`) === "t", [relogin.body.user, unlink.body]);

  console.log("\n— Stores, trader info and approval");
  const vendor = await register("Vera", "VENDOR");
  const store = await call("POST", "/stores", { name: `Vera Vintage ${uniq}`, category: "THRIFT", sellerType: "BUSINESS", businessId: "2345678-9", latitude: 60.17, longitude: 24.94, address: "Mannerheimintie 1, Helsinki", prepMinutes: 8 }, vendor.accessToken);
  check("vendor creates a business store with Y-tunnus", store.status === 201 && store.body.store.sellerType === "BUSINESS", store);
  const storeId = store.body.store.id;
  check("business seller must give a valid Y-tunnus", (await call("POST", "/stores", { name: "No ID", category: "APPAREL", sellerType: "BUSINESS" }, (await register("Nina", "VENDOR")).accessToken)).status === 400);
  const privSeller = await call("POST", "/stores", { name: `Pekka's closet ${uniq}`, category: "THRIFT", sellerType: "PRIVATE" }, (await register("Pekka", "VENDOR")).accessToken);
  check("private seller needs no Y-tunnus", privSeller.status === 201 && privSeller.body.store.sellerType === "PRIVATE", privSeller.body);
  check("customer cannot create a store", (await call("POST", "/stores", { name: "Sneaky", category: "OTHER" }, tokenA)).status === 403);
  check("unverified store hidden from public list", (await call("GET", `/stores?search=Vera Vintage ${uniq}`)).body.stores.length === 0);
  const foreignImg = await call("POST", "/products", { name: "Stolen pic", category: "Coat", salePriceCents: 5000, images: ["https://res.cloudinary.com/demo/coat.jpg"] }, vendor.accessToken);
  check("product photos must be the store's own uploads", foreignImg.status === 400, foreignImg.body);
  const prod = await call("POST", "/products", { name: "Wool coat", category: "Coat", salePriceCents: 5000, stockQuantity: 2, images: [ownImage(storeId, "coat")] }, vendor.accessToken);
  check("vendor creates product with own photo", prod.status === 201 && prod.body.product.images.length === 1, prod.body);
  const productId = prod.body.product.id;

  const adminUser = await register("Admin");
  sql(`update "User" set role='ADMIN' where id=${adminUser.user.id}`);
  const adminToken = (await call("POST", "/auth/login", { email: `admin${uniq}@example.fi`, password: "strong-pass-123" })).body.accessToken;
  check("non-admin blocked from admin API", (await call("GET", "/admin/stats", null, tokenA)).status === 403);
  check("admin approves store", (await call("PATCH", `/admin/vendors/${storeId}/approve`, null, adminToken)).status === 200);
  const pub2 = await call("GET", `/stores?search=Vera Vintage ${uniq}&lat=60.18&lng=24.95`);
  const listed = pub2.body.stores[0];
  check("approved store is public with trader info and ETA window", listed?.businessId === "2345678-9" && listed?.etaMinutes > 0 && listed?.etaMaxMinutes === listed?.etaMinutes + 10, listed);
  check("reviewed store cannot relabel itself as a private seller", (await call("POST", "/stores", { name: `Vera Vintage ${uniq}`, category: "THRIFT", sellerType: "PRIVATE" }, vendor.accessToken)).body.store?.sellerType === "BUSINESS");
  const listedFee = listed.deliveryFeeCents;

  console.log("\n— Couriers");
  const c1 = await register("Kalle", "COURIER");
  const c2 = await register("Linnea", "COURIER");
  check("unapproved courier cannot see jobs", (await call("GET", "/orders/available", null, c1.accessToken)).status === 403);
  check("unapproved courier cannot set up payouts", (await call("POST", "/payouts/onboarding", null, c1.accessToken)).status === 403);
  const couriers = (await call("GET", "/admin/couriers", null, adminToken)).body.couriers;
  for (const c of couriers.filter((x) => [c1.user.id, c2.user.id].includes(x.user?.id))) await call("PATCH", `/admin/couriers/${c.id}/approve`, null, adminToken);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.171, longitude: 24.941 }, c1.accessToken);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.2, longitude: 24.9 }, c2.accessToken);
  await call("POST", "/me/devices", { token: `courier-device-${uniq}-xxxxxxxxxxxx`, platform: "android" }, c1.accessToken);

  console.log("\n— Checkout through Stripe (stripe-mock)");
  const realOrder = await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }] }, tokenA);
  check("order creates a PaymentIntent and returns a client secret", realOrder.status === 201 && !!realOrder.body.clientSecret, realOrder.body);
  const ro = realOrder.body.order;
  // Courier pay is separate from the customer fee: 1.24 km straight = 1.6 km route → 4.50 + 1.76 € = 6.26 €, raised to the 6.50 € minimum
  check("courier pay (formula, with minimum) and ETA are set on the order", sql(`select "courierFeeCents" = 650 and ("courierPay"->>'topUpCents')::int = 24 and ("courierPay"->>'distanceKm')::float = 1.6 and "etaMinutes" > 0 from "Order" where id=${ro?.id}`) === "t", sql(`select "courierFeeCents" || ' ' || coalesce("courierPay"::text, '') from "Order" where id=${ro?.id}`));
  check("charged delivery fee equals the advertised fee", ro?.deliveryFeeCents === listedFee, { charged: ro?.deliveryFeeCents, listed: listedFee });
  check("cannot order more than stock", (await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", items: [{ productId, quantity: 5 }] }, tokenA)).status === 400);
  check("customer cancels before the store accepts; stock returns", (await call("POST", `/orders/${ro.id}/cancel`, null, tokenA)).status === 200 && sql(`select "stockQuantity" from "Product" where id=${productId}`) === "2");

  console.log("\n— Payment webhook → store → courier");
  const fee = listedFee;
  const orderId = Number(sql(`insert into "Order" ("userId","storeId","status","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","stripePaymentIntentId","paymentStatus","deliveryAddress","deliveryLat","deliveryLng","updatedAt") values (${regA.body.user.id},${storeId},'PENDING',5000,${fee},${fee},500,4500,${5000 + fee},'pi_test_${uniq}','PENDING','Aleksanterinkatu 5, Helsinki',60.18,24.95,now()) returning id`).split("\n")[0]);
  sql(`insert into "OrderItem" ("orderId","productId","quantity","unitCents") values (${orderId},${productId},1,5000)`);
  sql(`update "Product" set "stockQuantity"=1 where id=${productId}`);

  const vendorSock = await connect(vendor.accessToken);
  const custSock = await connect(tokenA);
  const otherCust = await register("Olli");
  const otherSock = await connect(otherCust.accessToken);
  const c1Sock = await connect(c1.accessToken);
  const c2Sock = await connect(c2.accessToken);
  custSock.emit("track:order", orderId);
  otherSock.emit("track:order", orderId);
  await sleep(300);

  check("vendor cannot accept unpaid order", (await call("PATCH", `/orders/${orderId}/status`, { status: "CONFIRMED" }, vendor.accessToken)).status === 409);
  check("webhook with bad signature rejected", (await call("POST", "/payments/webhook", null, null, { body: JSON.stringify({ id: "evt_x" }), headers: { "stripe-signature": "t=1,v1=bad" } })).status === 400);
  const paidEvt = { id: `evt_paid_${uniq}`, type: "payment_intent.succeeded", data: { object: { id: `pi_test_${uniq}`, amount_received: 5000 + fee, metadata: { type: "ORDER", orderId: String(orderId) } } } };
  check("signed webhook marks order paid", (await call("POST", "/payments/webhook", null, null, signedWebhook(paidEvt))).status === 200 && sql(`select "paymentStatus" from "Order" where id=${orderId}`) === "SUCCEEDED");
  check("webhook replay is idempotent", (await call("POST", "/payments/webhook", null, null, signedWebhook(paidEvt))).body?.duplicate === true);
  await sleep(300);
  check("vendor got real-time order:new", vendorSock.events.some((e) => e.ev === "order:new" && e.data.id === orderId));

  const conf = await call("PATCH", `/orders/${orderId}/status`, { status: "CONFIRMED" }, vendor.accessToken);
  check("vendor accepts paid order", conf.status === 200, conf);
  await sleep(400);
  const offer = c1Sock.events.find((e) => e.ev === "courier:dispatch_offer" && e.data.orderId === orderId)?.data;
  check("nearby courier gets the offer with their pay and without the customer's address", offer && offer.courierFeeCents === fee && !("deliveryAddress" in offer), offer);
  const [acc1, acc2] = await Promise.all([
    call("PATCH", `/orders/${orderId}/assign-courier`, null, c1.accessToken),
    call("PATCH", `/orders/${orderId}/assign-courier`, null, c2.accessToken),
  ]);
  check("exactly one courier wins the job", [acc1.status, acc2.status].sort().join() === "200,409", [acc1.status, acc2.status]);
  const winner = acc1.status === 200 ? { tok: c1.accessToken, user: c1.user } : { tok: c2.accessToken, user: c2.user };
  const loserTok = acc1.status === 200 ? c2.accessToken : c1.accessToken;
  check("courier picks up", (await call("PATCH", `/orders/${orderId}/status`, { status: "SHIPPED" }, winner.tok)).status === 200);
  check("accepted and picked-up times recorded", sql(`select "pickedUpAt" is not null and "acceptedAt" is not null from "Order" where id=${orderId}`) === "t");
  const winnerSock = acc1.status === 200 ? c1Sock : c2Sock;
  winnerSock.emit("courier:update_location", { orderId, lat: 60.2, lng: 24.9 });
  await sleep(400);
  check("no arriving notice while the courier is still far away", sql(`select "arrivingNotifiedAt" is null from "Order" where id=${orderId}`) === "t");
  winnerSock.emit("courier:update_location", { orderId, lat: 60.1801, lng: 24.9502 });
  await sleep(600);
  winnerSock.emit("courier:update_location", { orderId, lat: 60.1802, lng: 24.9501 });
  await sleep(600);
  check("customer is told the courier is arriving, once", sql(`select "arrivingNotifiedAt" is not null from "Order" where id=${orderId}`) === "t" && custSock.events.filter((e) => e.ev === "order:status" && e.data.arriving === true).length === 1, custSock.events.filter((e) => e.ev === "order:status").map((e) => e.data));

  console.log("\n— Handover and proof of delivery");
  check("courier cannot skip the handover step", (await call("PATCH", `/orders/${orderId}/status`, { status: "DELIVERED" }, winner.tok)).status === 409);
  check("other courier cannot get a proof upload slot", (await call("POST", "/media/sign", { kind: "delivery_proof", orderId }, loserTok)).status === 403);
  const proofSlot = await call("POST", "/media/sign", { kind: "delivery_proof", orderId }, winner.tok);
  check("carrying courier gets a private upload slot", proofSlot.status === 200 && proofSlot.body.params.type === "authenticated" && proofSlot.body.publicId.startsWith(`malvoya/proofs/o${orderId}/`), proofSlot.body);
  check("upload slot never exposes the API secret", !JSON.stringify(proofSlot.body).includes(CLD_SECRET));
  const forgedProof = await call("POST", `/orders/${orderId}/deliver`, { method: "PHOTO", upload: { publicId: proofSlot.body.publicId, version: 1, signature: "a".repeat(40) } }, winner.tok);
  check("forged photo proof rejected", forgedProof.status === 400, forgedProof.body);
  const deliver = await call("POST", `/orders/${orderId}/deliver`, { method: "PHOTO", latitude: 60.18, longitude: 24.95, upload: { publicId: proofSlot.body.publicId, version: 17, signature: uploadSig(proofSlot.body.publicId, 17) } }, winner.tok);
  check("courier completes delivery with photo proof", deliver.status === 200 && deliver.body.order.status === "DELIVERED", deliver.body);
  check("handover method and location recorded", sql(`select "deliveredAt" is not null and "deliveredLat" = 60.18 and "handoverMethod" = 'PHOTO' from "Order" where id=${orderId}`) === "t");
  const proofCust = await call("GET", `/orders/${orderId}/proof`, null, tokenA);
  check("customer sees the photo via a signed private link", proofCust.status === 200 && /\/image\/authenticated\/s--[\w-]{8}--\//.test(proofCust.body.proof.photoUrl || ""), proofCust.body);
  check("store cannot see the delivery photo", (await call("GET", `/orders/${orderId}/proof`, null, vendor.accessToken)).status === 404);
  check("other customer cannot see the delivery photo", (await call("GET", `/orders/${orderId}/proof`, null, otherCust.accessToken)).status === 404);
  await sleep(600);
  check("store payout scheduled after the return window", sql(`select status || '|' || "amountCents" || '|' || ("releaseAt" > now() + interval '14 days') from "Payout" where "orderId"=${orderId} and party='STORE'`) === "SCHEDULED|4500|true");
  check("courier payout waits for payout setup", sql(`select status from "Payout" where "orderId"=${orderId} and party='COURIER'`) === "WAITING_FOR_ACCOUNT");

  console.log("\n— Payouts (Stripe Connect via stripe-mock)");
  const onboard = await call("POST", "/payouts/onboarding", null, winner.tok);
  check("approved courier starts Stripe payout onboarding", onboard.status === 200 && /^https?:\/\//.test(onboard.body.url || ""), onboard.body);
  check("Stripe account saved for the courier", sql(`select "stripeAccountId" is not null from "Courier" where "userId"=${winner.user.id}`) === "t");
  check("customers cannot start payout onboarding", (await call("POST", "/payouts/onboarding", null, otherCust.accessToken)).status === 403);
  const st = await call("GET", "/payouts/status", null, winner.tok);
  check("payout status is read from Stripe", st.status === 200 && st.body.hasAccount === true, st.body);
  await sleep(1000);
  const cpId = sql(`select id from "Payout" where "orderId"=${orderId} and party='COURIER'`);
  if (sql(`select status from "Payout" where id=${cpId}`) !== "PAID") {
    // stripe-mock's fixture account may not report an active transfers capability; switch it on as Stripe
    // would, then run the payout through the admin retry path (same code the scheduler uses)
    sql(`update "Courier" set "payoutsEnabled"=true where "userId"=${winner.user.id}; update "Payout" set status='FAILED' where id=${cpId}`);
    const retried = await call("POST", `/admin/payouts/${cpId}/retry`, null, adminToken);
    check("admin retry runs the transfer", retried.status === 200, retried.body);
  }
  const paidRow = sql(`select status || '|' || coalesce("stripeTransferId", '') from "Payout" where id=${cpId}`);
  check("courier is paid by a Stripe transfer", /^PAID\|tr_/.test(paidRow), paidRow);
  const earnings = await call("GET", "/payouts", null, winner.tok);
  check("courier earnings summary", earnings.status === 200 && earnings.body.summary.paidCents === fee, earnings.body.summary);
  check("store cannot see courier earnings", !(await call("GET", "/payouts", null, vendor.accessToken)).body.payouts.some((p) => p.id === Number(cpId)));

  console.log("\n— Verified reviews");
  check("other customer cannot review this order", (await call("POST", `/orders/${orderId}/review`, { storeRating: 1 }, otherCust.accessToken)).status === 404);
  const review = await call("POST", `/orders/${orderId}/review`, { storeRating: 5, courierRating: 4, comment: "Nopea toimitus, kiitos" }, tokenA);
  check("customer reviews a delivered order", review.status === 201, review.body);
  check("one review per order", (await call("POST", `/orders/${orderId}/review`, { storeRating: 1 }, tokenA)).status === 409);
  check("store and courier ratings recalculated", sql(`select rating || '|' || "totalReviews" from "Store" where id=${storeId}`) === "5|1" && sql(`select rating from "Courier" where "userId"=${winner.user.id}`) === "4");
  const pubReviews = await call("GET", `/stores/${storeId}/reviews`);
  check("public reviews show first name + initial and verified purchase", pubReviews.body.reviews[0]?.author === "Aino K." && pubReviews.body.reviews[0]?.verifiedPurchase === true, pubReviews.body);
  check("courier rating is not public", !JSON.stringify(pubReviews.body).includes("courierRating"));
  const hide = await call("PATCH", `/admin/reviews/${review.body.review.id}`, { isHidden: true }, adminToken);
  check("admin hides a review and the rating updates", hide.status === 200 && sql(`select "totalReviews" from "Store" where id=${storeId}`) === "0");
  await call("PATCH", `/admin/reviews/${review.body.review.id}`, { isHidden: false }, adminToken);

  console.log("\n— Honest pricing (Omnibus 30-day rule)");
  const p2 = (await call("POST", "/products", { name: "Silk scarf", category: "Accessories", salePriceCents: 6000, images: [ownImage(storeId, "scarf")] }, vendor.accessToken)).body.product;
  check("new product shows no discount", p2.pricing.previousPriceCents === null && p2.pricing.discountPct === null, p2.pricing);
  await call("PATCH", `/products/${p2.id}`, { salePriceCents: 4800 }, vendor.accessToken);
  check("reduction with < 30 days of history shows no 'was' price", (await call("GET", `/products/${p2.id}`)).body.product.pricing.previousPriceCents === null);
  sql(`update "PriceChange" set "changedAt" = now() - interval '40 days' where "productId"=${p2.id} and "priceCents"=6000`);
  const disc = (await call("GET", `/products/${p2.id}`)).body.product.pricing;
  check("real reduction shows the 30-day lowest price and %", disc.previousPriceCents === 6000 && disc.discountPct === 20, disc);
  sql(`insert into "PriceChange" ("productId","priceCents","changedAt") values (${p2.id}, 3000, now() - interval '20 days')`);
  sql(`update "PriceChange" set "changedAt" = now() where "productId"=${p2.id} and "priceCents"=4800`);
  check("a lower price inside the 30 days cancels the discount claim", (await call("GET", `/products/${p2.id}`)).body.product.pricing.previousPriceCents === null);
  check("public product has no exact stock count", !("stockQuantity" in (await call("GET", `/products/${p2.id}`)).body.product));

  console.log("\n— Sizes and colours");
  const p3res = await call("POST", "/products", { name: "Linen shirt", category: "Shirt", salePriceCents: 3900, images: [ownImage(storeId, "shirt")],
    variants: [{ size: "S", color: "White", stock: 2 }, { size: "M", color: "White", stock: 0 }, { size: "L", color: "Sage", stock: 1, priceAdjustCents: 200 }] }, vendor.accessToken);
  const p3 = p3res.body.product;
  check("product with options; stock is the sum of options", p3res.status === 201 && sql(`select "stockQuantity" from "Product" where id=${p3.id}`) === "3", p3res.body);
  const pub3 = (await call("GET", `/products/${p3.id}`)).body.product;
  check("options show in-stock flags, not counts", pub3.variants.length === 3 && pub3.variants[1].inStock === false && !("stock" in pub3.variants[0]), pub3.variants);
  check("option price includes its adjustment", pub3.variants[2].priceCents === 4100);
  const oos = await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", items: [{ productId: p3.id, variantId: pub3.variants[1].id, quantity: 1 }] }, otherCust.accessToken);
  check("sold-out size cannot be ordered", oos.status === 400 && /out of stock/i.test(oos.body.error || ""), oos.body);
  const sizeM = (await call("GET", "/products/search?size=M")).body.products;
  const sizeS = (await call("GET", "/products/search?size=S&q=linen")).body.products;
  check("search by size finds only products with that size in stock", !sizeM.some((p) => p.id === p3.id) && sizeS.some((p) => p.id === p3.id));
  const upd = await call("PATCH", `/products/${p3.id}`, { variants: [{ id: pub3.variants[0].id, size: "S", color: "White", stock: 5 }, { size: "XL", color: "White", stock: 1 }] }, vendor.accessToken);
  check("store edits options (unused ones deleted, new one added)", upd.status === 200 && upd.body.product.variants.length === 2 && sql(`select "stockQuantity" from "Product" where id=${p3.id}`) === "6", upd.body);
  const sorted = (await call("GET", "/products/search?sort=price_desc&limit=50")).body.products.map((p) => p.pricing.priceCents);
  check("search sorts by price", sorted.length > 1 && sorted.every((v, i) => i === 0 || sorted[i - 1] >= v), sorted);

  console.log("\n— Favourites");
  check("add favourite", (await call("PUT", `/me/favorites/${p3.id}`, null, otherCust.accessToken)).body.isFavorite === true);
  check("favourites list", (await call("GET", "/me/favorites", null, otherCust.accessToken)).body.products.some((p) => p.id === p3.id));
  check("product shows it is a favourite", (await call("GET", `/products/${p3.id}`, null, otherCust.accessToken)).body.product.isFavorite === true);
  await call("DELETE", `/me/favorites/${p3.id}`, null, otherCust.accessToken);
  check("remove favourite", (await call("GET", "/me/favorites", null, otherCust.accessToken)).body.products.length === 0);

  console.log("\n— Media uploads");
  check("customer cannot get a store upload slot", (await call("POST", "/media/sign", { kind: "drop_video" }, otherCust.accessToken)).status === 403);
  const vslot = (await call("POST", "/media/sign", { kind: "drop_video" }, vendor.accessToken)).body;
  check("video slot is signed, scoped to the store and asks for streaming versions", vslot.publicId?.startsWith(`malvoya/drops/s${storeId}/`) && /sp_auto/.test(vslot.params?.eager || "") && vslot.params?.signature?.length === 40, vslot);
  const otherVendor = await register("Otto", "VENDOR");
  await call("POST", "/stores", { name: `Otto Outlet ${uniq}`, category: "APPAREL", sellerType: "BUSINESS", businessId: "1234567-8", latitude: 60.2, longitude: 24.9 }, otherVendor.accessToken);
  const stolen = await call("POST", "/media/confirm", { kind: "drop_video", publicId: vslot.publicId, version: 5, signature: uploadSig(vslot.publicId, 5) }, otherVendor.accessToken);
  check("another store cannot claim someone else's upload", stolen.status === 403, stolen.body);
  const confirmed = await call("POST", "/media/confirm", { kind: "drop_video", publicId: vslot.publicId, version: 5, signature: uploadSig(vslot.publicId, 5) }, vendor.accessToken);
  check("confirmed upload returns streaming, MP4 and poster URLs", /\.m3u8$/.test(confirmed.body.media?.hls || "") && /\.mp4$/.test(confirmed.body.media?.mp4 || "") && /\.jpg$/.test(confirmed.body.media?.poster || ""), confirmed.body);

  console.log("\n— Drops (shoppable videos)");
  await seedResource(vslot.publicId, { duration: 21.5, width: 720, height: 1280, derived: [] });
  const noRights = await call("POST", "/drops", { productId: p3.id, kind: "VIDEO", upload: { publicId: vslot.publicId, version: 5, signature: uploadSig(vslot.publicId, 5) } }, vendor.accessToken);
  check("a drop is refused unless the store confirms it holds the rights (music, logos, people)", noRights.status === 400, noRights.body);
  const d1res = await call("POST", "/drops", { productId: p3.id, caption: "New linen <script>x</script>", kind: "VIDEO", rightsConfirmed: true, upload: { publicId: vslot.publicId, version: 5, signature: uploadSig(vslot.publicId, 5) } }, vendor.accessToken);
  check("store posts a video drop; it waits for processing", d1res.status === 201 && d1res.body.drop.status === "PROCESSING", d1res.body);
  const d1 = d1res.body.drop?.id;
  check("processing drop is not in the feed", !(await call("GET", "/drops/feed?mode=latest")).body.drops.some((d) => d.id === d1));
  const notifyBody = JSON.stringify({ notification_type: "eager", public_id: vslot.publicId, eager: [{ transformation: "sp_auto/m3u8" }] });
  const ts = String(Math.floor(Date.now() / 1000));
  const post = (headers) => fetch(`${API}/media/cloudinary/notify`, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: notifyBody });
  check("media webhook with bad signature rejected", (await post({ "X-Cld-Timestamp": ts, "X-Cld-Signature": "b".repeat(40) })).status === 401);
  const oldTs = String(Number(ts) - 3 * 3600);
  check("old (replayed) media webhook rejected", (await post({ "X-Cld-Timestamp": oldTs, "X-Cld-Signature": sha1(notifyBody + oldTs + CLD_SECRET) })).status === 401);
  check("signed media webhook publishes the drop", (await post({ "X-Cld-Timestamp": ts, "X-Cld-Signature": sha1(notifyBody + ts + CLD_SECRET) })).status === 200 && sql(`select status from "Drop" where id=${d1}`) === "READY");
  const feed = await call("GET", "/drops/feed?lat=60.18&lng=24.95");
  const fd = feed.body.drops.find((d) => d.id === d1);
  check("drop in the For you feed with real product, pricing and delivery info", !!fd && fd.product.id === p3.id && fd.product.pricing.priceCents === 3900 && fd.store.deliveryFeeCents > 0 && fd.store.etaMinutes > 0 && /m3u8$/.test(fd.media.hls), fd);
  check("feed shows a 'why am I seeing this' reason", typeof fd?.reason === "string" && fd.reason.length > 0, fd?.reason);
  check("feed never invents likes or discounts", fd?.likeCount === 0 && fd?.product.pricing.previousPriceCents === null);
  check("ranking explanation is public", (await call("GET", "/drops/ranking")).body.ranking?.personalProfiling === false);

  console.log("\n— Product videos (gallery with sound)");
  const pv = (await call("POST", "/media/sign", { kind: "product_video" }, vendor.accessToken)).body;
  check("store signs a product video upload", pv.ok && pv.resourceType === "video" && pv.publicId?.startsWith(`malvoya/products/s${storeId}/`), pv);
  await seedResource(pv.publicId, { duration: 12, width: 1080, height: 1920, derived: [] });
  const pvUpload = { publicId: pv.publicId, version: 7, signature: uploadSig(pv.publicId, 7) };
  check("customers cannot add product videos", (await call("POST", `/products/${p3.id}/videos`, pvUpload, otherCust.accessToken)).status === 403);
  const pvAdd = await call("POST", `/products/${p3.id}/videos`, pvUpload, vendor.accessToken);
  check("store adds a video to its product; it waits for processing", pvAdd.status === 201 && pvAdd.body.video?.status === "PROCESSING", pvAdd.body);
  check("shoppers do not see a video that is still processing", (await call("GET", `/products/${p3.id}`)).body.product?.videos?.length === 0);
  const pvBody = JSON.stringify({ notification_type: "eager", public_id: pv.publicId, eager: [{ transformation: "sp_auto/m3u8" }] });
  const pvTs = String(Math.floor(Date.now() / 1000));
  await fetch(`${API}/media/cloudinary/notify`, { method: "POST", headers: { "Content-Type": "application/json", "X-Cld-Timestamp": pvTs, "X-Cld-Signature": sha1(pvBody + pvTs + CLD_SECRET) }, body: pvBody });
  const withVideo = (await call("GET", `/products/${p3.id}`)).body.product;
  check("once processed, the product has a streaming video with a poster (no internal status)", withVideo?.videos?.length === 1 && /m3u8$/.test(withVideo.videos[0].hls) && /\.jpg$/.test(withVideo.videos[0].poster) && withVideo.videos[0].status === undefined, withVideo?.videos);
  check("the store page shows the product video too", (await call("GET", `/stores/${storeId}`)).body.store?.products?.find((p) => p.id === p3.id)?.videos?.length === 1);
  check("the same upload cannot be added twice", (await call("POST", `/products/${p3.id}/videos`, pvUpload, vendor.accessToken)).status === 409);
  const otherPv = (await call("POST", "/media/sign", { kind: "product_video" }, otherVendor.accessToken)).body;
  await seedResource(otherPv.publicId, { duration: 10, width: 720, height: 1280, derived: [] });
  const otherUpload = { publicId: otherPv.publicId, version: 1, signature: uploadSig(otherPv.publicId, 1) };
  check("a store cannot add a video to another store's product", (await call("POST", `/products/${p3.id}/videos`, otherUpload, otherVendor.accessToken)).status === 404);
  check("a store cannot attach another store's upload", (await call("POST", `/products/${p3.id}/videos`, otherUpload, vendor.accessToken)).status === 403);
  const longPv = (await call("POST", "/media/sign", { kind: "product_video" }, vendor.accessToken)).body;
  await seedResource(longPv.publicId, { duration: 75, width: 720, height: 1280, derived: [] });
  check("product videos over 60 s are refused", (await call("POST", `/products/${p3.id}/videos`, { publicId: longPv.publicId, version: 1, signature: uploadSig(longPv.publicId, 1) }, vendor.accessToken)).status === 400);
  const pvDel = await call("DELETE", `/products/${p3.id}/videos/${pvAdd.body.video?.id}`, null, vendor.accessToken);
  check("store removes a product video", pvDel.status === 200 && (await call("GET", `/products/${p3.id}`)).body.product?.videos?.length === 0);

  const long = (await call("POST", "/media/sign", { kind: "drop_video" }, vendor.accessToken)).body;
  await seedResource(long.publicId, { duration: 140, width: 720, height: 1280, derived: [] });
  check("videos over 90 s are refused", (await call("POST", "/drops", { productId: p3.id, kind: "VIDEO", rightsConfirmed: true, upload: { publicId: long.publicId, version: 1, signature: uploadSig(long.publicId, 1) } }, vendor.accessToken)).status === 400);
  const notMine = await call("POST", "/drops", { productId: p3.id, kind: "VIDEO", rightsConfirmed: true, upload: { publicId: vslot.publicId, version: 5, signature: uploadSig(vslot.publicId, 5) } }, otherVendor.accessToken);
  check("store cannot post another store's product", notMine.status === 400 || notMine.status === 403, notMine.status);

  check("like a drop", (await call("POST", `/drops/${d1}/like`, null, otherCust.accessToken)).body.likeCount === 1);
  check("liking twice counts once", (await call("POST", `/drops/${d1}/like`, null, otherCust.accessToken)).body.likeCount === 1);
  check("drop shows it is liked by the viewer", (await call("GET", `/drops/${d1}`, null, otherCust.accessToken)).body.drop.likedByMe === true);
  check("unlike", (await call("DELETE", `/drops/${d1}/like`, null, otherCust.accessToken)).body.likeCount === 0);
  check("anonymous users cannot like", (await call("POST", `/drops/${d1}/like`)).status === 401);
  await call("POST", `/drops/${d1}/view`, { installId: "install-abc-123", watchedSec: 5, completed: false });
  await call("POST", `/drops/${d1}/view`, { installId: "install-abc-123", watchedSec: 21, completed: true });
  await call("POST", `/drops/${d1}/view`, { installId: "install-abc-123", watchedSec: 21, completed: true });
  check("repeat views from one device count once; completion counted once", sql(`select "viewCount" || '|' || "completeCount" from "Drop" where id=${d1}`) === "1|1");
  check("watch time is capped at the video length", Number(sql(`select "watchSeconds" from "Drop" where id=${d1}`)) <= 21.5);
  const sh = await call("POST", `/drops/${d1}/share`);
  check("share returns a public link", (sh.body.shareUrl || "").endsWith(`/d/${d1}`) && sh.body.shareCount === 1, sh.body);
  const page = await fetch(`${BASE}/d/${d1}`);
  const html = await page.text();
  check("share page has preview tags and escapes captions", page.status === 200 && html.includes('property="og:image"') && !html.includes("<script>x</script>") && html.includes("&lt;script&gt;"), html.slice(0, 300));
  check("share page allows only Cloudinary images", /img-src https:\/\/res\.cloudinary\.com/.test(page.headers.get("content-security-policy") || ""));
  check("share page for a missing drop still renders", (await fetch(`${BASE}/d/999999`)).status === 200);

  const imgSlot = (await call("POST", "/media/sign", { kind: "drop_image" }, vendor.accessToken)).body;
  await seedResource(imgSlot.publicId, { width: 1080, height: 1350 });
  const imgDrop = await call("POST", "/drops", { productId: p3.id, kind: "IMAGE", rightsConfirmed: true, upload: { publicId: imgSlot.publicId, version: 2, signature: uploadSig(imgSlot.publicId, 2) } }, vendor.accessToken);
  check("photo drops go live immediately", imgDrop.status === 201 && imgDrop.body.drop.status === "READY", imgDrop.body);
  for (let i = 0; i < 3; i++) {
    const sl = (await call("POST", "/media/sign", { kind: "drop_image" }, vendor.accessToken)).body;
    await seedResource(sl.publicId, { width: 1080, height: 1350 });
    await call("POST", "/drops", { productId: p3.id, kind: "IMAGE", rightsConfirmed: true, upload: { publicId: sl.publicId, version: 3, signature: uploadSig(sl.publicId, 3) } }, vendor.accessToken);
  }
  const pg1 = await call("GET", "/drops/feed?limit=3");
  const pg2 = await call("GET", `/drops/feed?limit=3&cursor=${pg1.body.nextCursor}`);
  const ids = [...pg1.body.drops, ...pg2.body.drops].map((d) => d.id);
  check("feed pages with a stable cursor and no duplicates", !!pg1.body.nextCursor && ids.length === new Set(ids).size && ids.length >= 5, ids);
  check("tampered cursor falls back safely", (await call("GET", "/drops/feed?cursor=not-base64!!")).status === 200);
  const latest = (await call("GET", "/drops/feed?mode=latest&limit=20")).body.drops.map((d) => new Date(d.publishedAt).getTime());
  check("Latest mode is chronological", latest.every((t, i) => i === 0 || latest[i - 1] >= t));
  check("store profile lists its drops", (await call("GET", `/stores/${storeId}/drops`)).body.drops.length >= 5);
  const oSlot = (await call("POST", "/media/sign", { kind: "drop_image" }, otherVendor.accessToken)).body;
  await seedResource(oSlot.publicId, { width: 1080, height: 1350 });
  const oProd = (await call("POST", "/products", { name: "Denim", category: "Jeans", salePriceCents: 7000 }, otherVendor.accessToken)).body.product;
  const oDrop = (await call("POST", "/drops", { productId: oProd.id, kind: "IMAGE", rightsConfirmed: true, upload: { publicId: oSlot.publicId, version: 1, signature: uploadSig(oSlot.publicId, 1) } }, otherVendor.accessToken)).body.drop;
  check("unverified store's drops stay out of the feed", !!oDrop && !(await call("GET", "/drops/feed?limit=20&mode=latest")).body.drops.some((d) => d.id === oDrop.id));
  check("another store cannot delete my drop", (await call("DELETE", `/drops/${d1}`, null, otherVendor.accessToken)).status === 404);
  const mine = await call("GET", "/drops/mine", null, vendor.accessToken);
  const m1 = mine.body.drops.find((d) => d.id === d1);
  check("store sees its drops with real stats", m1?.viewCount === 1 && m1?.avgWatchSec > 0, m1);

  console.log("\n— Comments and follows");
  check("anonymous users cannot comment", (await call("POST", `/drops/${d1}/comments`, { body: "hi" })).status === 401);
  check("an empty comment is refused", (await call("POST", `/drops/${d1}/comments`, { body: "   " }, otherCust.accessToken)).status === 400);
  check("comments over 300 characters are refused", (await call("POST", `/drops/${d1}/comments`, { body: "x".repeat(301) }, otherCust.accessToken)).status === 400);
  const cm1 = await call("POST", `/drops/${d1}/comments`, { body: "  Love   this colour! <b>x</b> " }, otherCust.accessToken);
  check("customer comments on a drop; shown by first name, stored as plain text", cm1.status === 201 && cm1.body.comment?.body === "Love this colour! <b>x</b>" && cm1.body.comment.author === "Olli" && cm1.body.comment.mine === true, cm1.body);
  const cm2 = await call("POST", `/drops/${d1}/comments`, { body: "Thank you! Sizes S-L in stock." }, vendor.accessToken);
  check("the store's reply is labelled as the store", cm2.status === 201 && cm2.body.comment?.byStore === true && cm2.body.comment.author === `Vera Vintage ${uniq}`, cm2.body);
  const listedComments = await call("GET", `/drops/${d1}/comments`);
  check("anyone can read comments, newest first, without edit rights", listedComments.body.comments?.length === 2 && listedComments.body.comments[0].id === cm2.body.comment.id && listedComments.body.comments.every((c) => !c.mine && !c.canDelete), listedComments.body);
  check("the drop shows its comment count", (await call("GET", `/drops/${d1}`)).body.drop?.commentCount === 2);
  const commentStranger = await register("Saara");
  check("others cannot delete someone's comment", (await call("DELETE", `/drops/${d1}/comments/${cm1.body.comment.id}`, null, commentStranger.accessToken)).status === 403);
  check("the store can delete a comment on its own drop", (await call("DELETE", `/drops/${d1}/comments/${cm1.body.comment.id}`, null, vendor.accessToken)).status === 200 && (await call("GET", `/drops/${d1}`)).body.drop?.commentCount === 1);
  check("you cannot report your own comment", (await call("POST", `/drops/${d1}/comments/${cm2.body.comment.id}/report`, { reason: "SCAM" }, vendor.accessToken)).status === 400);
  for (const reporter of [otherCust, commentStranger, await register("Riku")]) {
    await call("POST", `/drops/${d1}/comments/${cm2.body.comment.id}/report`, { reason: "HARASSMENT" }, reporter.accessToken);
  }
  check("three distinct reports hide a comment", (await call("GET", `/drops/${d1}/comments`)).body.comments?.length === 0 && (await call("GET", `/drops/${d1}`)).body.drop?.commentCount === 0);
  const reportedComments = await call("GET", "/admin/comments/reported", null, adminToken);
  check("admins see reportedComments comments with reasons", reportedComments.body.comments?.some((c) => c.id === cm2.body.comment.id && c.status === "HIDDEN" && c.reports.length === 3), reportedComments.body);
  check("only admins see reportedComments comments", (await call("GET", "/admin/comments/reported", null, otherCust.accessToken)).status === 403);
  const restoredComment = await call("POST", `/admin/comments/${cm2.body.comment.id}`, { action: "restore" }, adminToken);
  check("an admin can restore a wrongly hidden comment", restoredComment.body.comment?.status === "VISIBLE" && (await call("GET", `/drops/${d1}`)).body.drop?.commentCount === 1, restoredComment.body);

  check("following needs a signed-in user", (await call("PUT", `/stores/${storeId}/follow`)).status === 401);
  const followRes = await call("PUT", `/stores/${storeId}/follow`, null, otherCust.accessToken);
  check("customer follows a store", followRes.body.following === true && followRes.body.followerCount === 1, followRes.body);
  check("following twice counts once", (await call("PUT", `/stores/${storeId}/follow`, null, otherCust.accessToken)).body.followerCount === 1);
  const sPage = (await call("GET", `/stores/${storeId}`, null, otherCust.accessToken)).body.store;
  check("store page shows followers and that you follow it", sPage?.followerCount === 1 && sPage?.followedByMe === true, sPage && { followerCount: sPage.followerCount, followedByMe: sPage.followedByMe });
  const followFeed = await call("GET", "/drops/feed?mode=following", null, otherCust.accessToken);
  check("the Following feed has drops from followed stores, marked as followed", followFeed.body.drops?.some((d) => d.id === d1 && d.store.followedByMe === true && typeof d.commentCount === "number"), followFeed.body);
  check("the Following feed is empty when you follow nobody", (await call("GET", "/drops/feed?mode=following", null, commentStranger.accessToken)).body.drops?.length === 0);
  check("the Following feed needs a signed-in user", (await call("GET", "/drops/feed?mode=following")).status === 401);
  check("unfollow", (await call("DELETE", `/stores/${storeId}/follow`, null, otherCust.accessToken)).body.following === false);

  console.log("\n— Reporting and moderation (DSA)");
  const reporters = [otherCust, await register("Pia"), await register("Rami")];
  check("anonymous report accepted", (await call("POST", `/drops/${d1}/report`, { reason: "SCAM" })).body.received === true);
  check("report needs a valid reason", (await call("POST", `/drops/${d1}/report`, { reason: "I dont like it" }, reporters[0].accessToken)).status === 400);
  for (const r of reporters) await call("POST", `/drops/${d1}/report`, { reason: "COUNTERFEIT", details: "Fake brand" }, r.accessToken);
  check("three independent reports hide the drop pending review", sql(`select status from "Drop" where id=${d1}`) === "REMOVED");
  check("admin sees the open reports", (await call("GET", "/admin/reports", null, adminToken)).body.reports.filter((r) => r.drop.id === d1).length === 4);
  check("admin restores after review", (await call("PATCH", `/admin/drops/${d1}`, { action: "restore" }, adminToken)).body.status === "READY");
  check("removal requires a reason for the store", (await call("PATCH", `/admin/drops/${d1}`, { action: "remove" }, adminToken)).status === 400);
  check("admin removes with a statement of reasons", (await call("PATCH", `/admin/drops/${d1}`, { action: "remove", reason: "Listing uses a protected trademark without permission." }, adminToken)).body.status === "REMOVED");
  check("removed drop is gone for shoppers", (await call("GET", `/drops/${d1}`)).status === 404);
  check("store deletes its own drop", (await call("DELETE", `/drops/${imgDrop.body.drop.id}`, null, vendor.accessToken)).status === 200);
  await sleep(400);
  check("deleted drop's media is erased from storage", (await (await fetch("http://localhost:12222/__destroyed")).json()).includes(imgSlot.publicId));
  const stats = (await call("GET", "/admin/stats", null, adminToken)).body.stats;
  check("admin dashboard counts drops and reports", typeof stats.liveDrops === "number" && typeof stats.openReports === "number", stats);

  console.log("\n— Returns, refunds and GDPR");
  const ret = await call("POST", "/returns", { orderId, reason: "CHANGED_MIND" }, tokenA);
  check("customer starts a return within 14 days of delivery", ret.status === 201, ret.body);
  // Make the store payout due and let the payout job run (the admin retry runs the same job)
  const storePayoutId = sql(`select id from "Payout" where "orderId"=${orderId} and party='STORE'`);
  sql(`update "Payout" set status='FAILED', "releaseAt"=now() - interval '1 day' where id=${storePayoutId}`);
  await call("POST", `/admin/payouts/${storePayoutId}/retry`, null, adminToken);
  check("store is not paid while a return is open", sql(`select status from "Payout" where id=${storePayoutId}`) === "SCHEDULED");
  const vendorReturns = await call("GET", "/returns", null, vendor.accessToken);
  check("store sees returns of its orders", vendorReturns.body.returns?.some((r) => r.id === ret.body.return.id), vendorReturns.body);
  check("outsider cannot process the return", (await call("PATCH", `/returns/${ret.body.return.id}/status`, { status: "APPROVED" }, otherVendor.accessToken)).status === 403);
  const refund = await call("PATCH", `/returns/${ret.body.return.id}/status`, { status: "REFUNDED" }, vendor.accessToken);
  check("store refunds the return through Stripe", refund.status === 200, refund.body);
  check("refund cancels the unpaid store payout", sql(`select status || '|' || "amountCents" from "Payout" where "orderId"=${orderId} and party='STORE'`) === "CANCELLED|0");
  await call("PUT", `/me/favorites/${p3.id}`, null, tokenA);
  await call("POST", "/me/devices", { token: `device-token-${uniq}-aaaaaaaaaaaa`, platform: "android" }, tokenA);
  sql(`update "User" set "googleSub" = 'google-sub-${uniq}' where id = ${regA.body.user.id}`);
  const exp = await call("GET", "/auth/me/data", null, tokenA);
  check("data export includes the linked Google account id", exp.body.data?.googleSub === `google-sub-${uniq}`, exp.body.data?.googleSub);
  check("data export includes favourites, reviews and devices, no secrets", exp.body.data?.favorites?.length === 1 && exp.body.data?.reviews?.length === 1 && exp.body.data?.devices?.length === 1 && !JSON.stringify(exp.body).includes("passwordHash") && !JSON.stringify(exp.body).includes("device-token-"), Object.keys(exp.body.data || {}));
  check("account deletion succeeds", (await call("DELETE", "/auth/me", null, tokenA)).status === 200);
  check("deletion removes favourites and devices and blanks review text", sql(`select (select count(*) from "Favorite" where "userId"=${regA.body.user.id}) + (select count(*) from "DeviceToken" where "userId"=${regA.body.user.id}) || '|' || (select comment is null from "Review" where "orderId"=${orderId})`) === "0|true");
  check("deletion unlinks Google, so it can sign up again", sql(`select "googleSub" is null from "User" where id = ${regA.body.user.id}`) === "t");
  check("order kept for bookkeeping, personal data anonymised", sql(`select u.name || '|' || (o."deliveryAddress" is null) from "User" u join "Order" o on o."userId"=u.id where o.id=${orderId}`) === "Deleted user|true");
  check("deleted user's review shows as former customer", (await call("GET", `/stores/${storeId}/reviews`)).body.reviews[0]?.author === "Former customer");

  console.log("\n— Support and legal pages");
  const sup = await call("POST", "/support", { app: "customer", topic: "Order question", message: "Where is my parcel?" }, otherCust.accessToken);
  check("signed-in user contacts support; reply goes to the account email", sup.status === 201 && sup.body.replyTo === `olli${uniq}@example.fi`, sup.body);
  check("signed-out support needs an email", (await call("POST", "/support", { app: "courier", topic: "Sign up", message: "How do I start?" })).status === 400);
  check("signed-out support with email works", (await call("POST", "/support", { app: "courier", topic: "Sign up", message: "How do I start?", email: "applicant@example.fi" })).status === 201);
  check("admin sees open support requests", (await call("GET", "/admin/support", null, adminToken)).body.requests.some((r) => r.id === sup.body.id));
  check("customer cannot read the support queue", (await call("GET", "/admin/support", null, otherCust.accessToken)).status === 403);
  const legal = await fetch(`${BASE}/legal/privacy`);
  const legalHtml = await legal.text();
  check("privacy policy is published as a web page", legal.status === 200 && legalHtml.includes("<h1>") && legalHtml.includes("<table>") && !/<script/i.test(legalHtml));
  check("all four legal documents are published", (await Promise.all(["terms", "sellers", "couriers"].map((d) => fetch(`${BASE}/legal/${d}`)))).every((r) => r.status === 200));
  check("unknown legal document is 404", (await fetch(`${BASE}/legal/../../etc/passwd`)).status === 404 && (await fetch(`${BASE}/legal/secrets`)).status === 404);
  check("search filters by eco-friendly flag", (await call("GET", "/products/search?eco=true")).status === 200);

  console.log("\n— Store hours, pause switch and the order watchdog");
  sql(`update "Product" set "stockQuantity"=10, "isAvailable"=true where id=${productId}`);
  const orderBody = { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }] };
  const paused = await call("PATCH", `/stores/${storeId}`, { acceptingOrders: false }, vendor.accessToken);
  const pausedList = (await call("GET", `/stores?search=Vera Vintage ${uniq}`)).body.stores[0];
  check("store can pause new orders; shoppers see it", paused.status === 200 && pausedList?.openNow === false && pausedList?.closedReason === "paused", pausedList);
  const pausedOrder = await call("POST", "/orders", orderBody, otherCust.accessToken);
  check("a paused store takes no orders", pausedOrder.status === 409 && /not taking orders/.test(pausedOrder.body?.error), pausedOrder.body);
  check("opening hours are validated", (await call("PATCH", `/stores/${storeId}`, { acceptingOrders: true, openingHours: { mon: [["25:00", "18:00"]] } }, vendor.accessToken)).status === 400);
  const closedAllWeek = { mon: [], tue: [], wed: [], thu: [], fri: [], sat: [], sun: [] };
  await call("PATCH", `/stores/${storeId}`, { acceptingOrders: true, openingHours: closedAllWeek }, vendor.accessToken);
  const closedStore = (await call("GET", `/stores/${storeId}`)).body.store;
  const closedOrder = await call("POST", "/orders", orderBody, otherCust.accessToken);
  check("outside opening hours the store is closed and takes no orders", closedStore?.openNow === false && closedStore?.closedReason === "closed" && closedOrder.status === 409, [closedStore?.openNow, closedOrder.body]);
  const reopened = await call("PATCH", `/stores/${storeId}`, { openingHours: null }, vendor.accessToken);
  check("clearing the hours makes the store always open", reopened.status === 200 && (await call("GET", `/stores/${storeId}`)).body.store?.openNow === true, reopened.body);
  check("only the owner can pause a store", (await call("PATCH", `/stores/${storeId}`, { acceptingOrders: false }, otherCust.accessToken)).status === 403);


  console.log("\n— Scheduled delivery (Tonight / tomorrow slots)");
  const nowHel = hel();
  const tmr = hel(new Date(Date.now() + 86_400_000));
  const minOf = (t) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
  const slotBody = (date, start, end, extra = {}) => ({ ...orderBody, deliverySlot: { date, start, end }, ...extra });
  const paySched = (o) => call("POST", "/payments/webhook", null, null, signedWebhook({
    id: `evt_sched_${o.id}_${uniq}`, type: "payment_intent.succeeded",
    data: { object: { id: o.stripePaymentIntentId, amount_received: o.totalCents, metadata: { type: "ORDER", orderId: String(o.id) } } },
  }));
  const sq = await call("POST", "/orders/quote", { storeId, deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }] }, otherCust.accessToken);
  const expectedSlots = [
    ...["17:00", "19:00"].filter((st) => minOf(st) >= minOf(nowHel.time) + 60).map((st) => `${nowHel.date} ${st}`),
    `${tmr.date} 17:00`, `${tmr.date} 19:00`,
  ];
  const gotSlots = (sq.body.quote?.slots || []).map((x) => `${x.date} ${x.start}`);
  check("quote lists the bookable slots (today from 60 min ahead, and tomorrow) with their fee; no slot picked", sq.status === 200 && gotSlots.join() === expectedSlots.join() && sq.body.quote.slots.every((x) => x.feeCents === fee && x.end === (x.start === "17:00" ? "19:00" : "21:00")) && sq.body.quote.deliverySlot === null, [gotSlots, expectedSlots, sq.body.quote?.slots]);
  const tmrSlot = sq.body.quote?.slots?.find((x) => x.date === tmr.date && x.start === "17:00");
  check("slot labels in English and Finnish", tmrSlot?.label?.en === "Tomorrow 17:00–19:00" && tmrSlot.label.fi === "Huomenna 17.00–19.00", tmrSlot);
  const sqPick = await call("POST", "/orders/quote", { storeId, fulfilment: "PICKUP", items: [{ productId, quantity: 1 }] }, otherCust.accessToken);
  check("pickup quotes offer no delivery slots", sqPick.status === 200 && Array.isArray(sqPick.body.quote.slots) && sqPick.body.quote.slots.length === 0 && sqPick.body.quote.deliverySlot === null, sqPick.body.quote);
  check("a pickup order cannot have a delivery slot (400)", (await call("POST", "/orders/quote", { storeId, fulfilment: "PICKUP", items: [{ productId, quantity: 1 }], deliverySlot: { date: tmr.date, start: "17:00", end: "19:00" } }, otherCust.accessToken)).status === 400);
  const sqPicked = await call("POST", "/orders/quote", { storeId, deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }], deliverySlot: { date: tmr.date, start: "17:00", end: "19:00" } }, otherCust.accessToken);
  check("quote echoes the picked slot with its label and fee", sqPicked.status === 200 && sqPicked.body.quote.deliverySlot?.date === tmr.date && sqPicked.body.quote.deliverySlot.start === "17:00" && sqPicked.body.quote.deliverySlot.label.en === "Tomorrow 17:00–19:00" && sqPicked.body.quote.deliverySlot.feeCents === fee && sqPicked.body.quote.deliveryFeeCents === fee, sqPicked.body.quote);
  const badSlots = [
    slotBody(tmr.date, "10:00", "12:00"), slotBody(tmr.date, "17:00", "21:00"),
    slotBody(hel(new Date(Date.now() - 86_400_000)).date, "17:00", "19:00"), slotBody(hel(new Date(Date.now() + 2 * 86_400_000)).date, "17:00", "19:00"),
    slotBody("2026-02-30", "17:00", "19:00"), slotBody(tmr.date, "5pm", "7pm"),
  ];
  const badStatuses = [];
  for (const b of badSlots) badStatuses.push((await call("POST", "/orders", b, otherCust.accessToken)).status);
  check("slots that are not offered, not today/tomorrow or malformed are refused (400)", badStatuses.every((x) => x === 400), badStatuses);
  const pastToday = ["17:00", "19:00"].find((st) => minOf(st) < minOf(nowHel.time) + 60);
  if (pastToday) {
    const tooSoon = await call("POST", "/orders", slotBody(nowHel.date, pastToday, pastToday === "17:00" ? "19:00" : "21:00"), otherCust.accessToken);
    check("a slot starting in less than 60 minutes is refused (409)", tooSoon.status === 409 && /too soon/.test(tooSoon.body.error || ""), tooSoon.body);
  }
  // Open now, but closed tomorrow evening: tomorrow's slots disappear and cannot be booked
  await call("PATCH", `/stores/${storeId}`, { openingHours: { [nowHel.wd]: [["00:00", "23:59"]], [tmr.wd]: [["00:00", "12:00"]] } }, vendor.accessToken);
  const closedSlots = (await call("POST", "/orders/quote", { storeId, deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }] }, otherCust.accessToken)).body.quote?.slots || [];
  const closedOrder2 = await call("POST", "/orders", slotBody(tmr.date, "17:00", "19:00"), otherCust.accessToken);
  check("slots only when the store is open at the slot start", !closedSlots.some((x) => x.date === tmr.date) && closedOrder2.status === 409 && /closed at that time/.test(closedOrder2.body.error || ""), [closedSlots, closedOrder2.body]);
  await call("PATCH", `/stores/${storeId}`, { openingHours: null }, vendor.accessToken);
  const schedRes = await call("POST", "/orders", slotBody(tmr.date, "17:00", "19:00"), otherCust.accessToken);
  const so = schedRes.body.order;
  check("a scheduled order stores its window (Finnish 17:00–19:00 tomorrow) and promises no minutes-ETA", schedRes.status === 201 && hel(new Date(so.scheduledStart)).date === tmr.date && hel(new Date(so.scheduledStart)).time === "17:00" && hel(new Date(so.scheduledEnd)).time === "19:00" && so.etaMinutes === null && so.deliveryFeeCents === fee && so.courierFeeCents === 650, so);
  check("an order without a slot is as soon as possible", sql(`select "scheduledStart" is null and "etaMinutes" > 0 from "Order" where id=${ro.id}`) === "t");
  c1Sock.events.length = 0; c2Sock.events.length = 0; vendorSock.events.length = 0;
  await paySched(so);
  await sleep(300);
  check("the store's new-order event carries the window", vendorSock.events.some((e) => e.ev === "order:new" && e.data.id === so.id && e.data.scheduledStart && e.data.scheduledEnd));
  check("the store accepts the scheduled order", (await call("PATCH", `/orders/${so.id}/status`, { status: "CONFIRMED" }, vendor.accessToken)).status === 200);
  await sleep(500);
  check("couriers are not offered a scheduled job before slot start − prep time − 15 min", !c1Sock.events.some((e) => e.ev === "courier:dispatch_offer" && e.data.orderId === so.id) && !c2Sock.events.some((e) => e.ev === "courier:dispatch_offer" && e.data.orderId === so.id) && sql(`select ("lastOfferAt" is null) and ("dispatchStartedAt" is null) from "Order" where id=${so.id}`) === "t");
  check("an early scheduled job is not in the courier job list and cannot be taken", !(await call("GET", "/orders/available", null, c1.accessToken)).body.orders?.some((o) => o.id === so.id) && (await call("PATCH", `/orders/${so.id}/assign-courier`, null, c1.accessToken)).status === 409);
  const vendSched = (await call("GET", "/orders", null, vendor.accessToken)).body.orders?.find((o) => o.id === so.id);
  check("the store sees the window on the order", vendSched?.scheduledStart === so.scheduledStart && vendSched?.scheduledEnd === so.scheduledEnd, vendSched);
  // Move the slot to 10 min from now (Vera's prep time 8 min → dispatch is due): the watchdog makes the first offer
  sql(`update "Order" set "scheduledStart" = now() + interval '10 minutes', "scheduledEnd" = now() + interval '130 minutes' where id=${so.id}`);

  // Four stuck orders, aged with SQL, for the watchdog (runs every minute) to resolve
  const stuck = await call("POST", "/orders", orderBody, otherCust.accessToken);
  const unpaidId = stuck.body.order?.id;
  const stockBefore = Number(sql(`select "stockQuantity" from "Product" where id=${productId}`));
  sql(`update "Order" set "createdAt" = now() - interval '40 minutes' where id=${unpaidId}`);
  const mk = (status, extra) => Number(sql(`insert into "Order" ("userId","storeId","status","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","stripePaymentIntentId","paymentStatus","paidAt","deliveryAddress","deliveryLat","deliveryLng","updatedAt"${extra.cols}) values (${otherCust.user.id},${storeId},'${status}',5000,${fee},${fee},500,4500,${5000 + fee},'pi_wd_${extra.tag}_${uniq}','SUCCEEDED',${extra.paidAt},'Aleksanterinkatu 5, Helsinki',60.18,24.95,now()${extra.vals}) returning id`).split("\n")[0]);
  const remindId = mk("PENDING", { tag: "remind", paidAt: "now() - interval '4 minutes'", cols: "", vals: "" });
  const lateStoreId = mk("PENDING", { tag: "late", paidAt: "now() - interval '11 minutes'", cols: "", vals: "" });
  const delayId = mk("CONFIRMED", { tag: "delay", paidAt: "now() - interval '20 minutes'", cols: `,"confirmedAt"`, vals: `,now() - interval '16 minutes'` });
  const noCourierId = mk("CONFIRMED", { tag: "nocourier", paidAt: "now() - interval '55 minutes'", cols: `,"confirmedAt"`, vals: `,now() - interval '50 minutes'` });
  // Reserve & collect: ready but not collected (reminder at 24 h, refund at 72 h); accepted pickup orders never wait for couriers
  const mkPickup = (status, tag, cols, vals) => Number(sql(`insert into "Order" ("userId","storeId","status","fulfilment","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","stripePaymentIntentId","paymentStatus","paidAt","pickupCode","updatedAt"${cols}) values (${otherCust.user.id},${storeId},'${status}','PICKUP',5000,0,0,500,4500,5000,'pi_wd_${tag}_${uniq}','SUCCEEDED',now() - interval '4 days','123456',now()${vals}) returning id`).split("\n")[0]);
  const pickupRemindId = mkPickup("PROCESSING", "pkremind", `,"confirmedAt","readyAt"`, `,now() - interval '26 hours',now() - interval '25 hours'`);
  const pickupLateId = mkPickup("PROCESSING", "pklate", `,"confirmedAt","readyAt"`, `,now() - interval '74 hours',now() - interval '73 hours'`);
  const pickupWaitId = mkPickup("CONFIRMED", "pkwait", `,"confirmedAt"`, `,now() - interval '50 minutes'`);
  const pickupNeverReadyId = mkPickup("CONFIRMED", "pknever", `,"confirmedAt"`, `,now() - interval '25 hours'`);
  // Scheduled: "no courier" timers count from the slot start, not from acceptance; tomorrow's slot is left alone
  const schedLateId = mk("CONFIRMED", { tag: "schedlate", paidAt: "now() - interval '3 hours'", cols: `,"confirmedAt","scheduledStart","scheduledEnd"`, vals: `,now() - interval '2 minutes',now() - interval '50 minutes',now() + interval '70 minutes'` });
  const schedDelayId = mk("CONFIRMED", { tag: "scheddelay", paidAt: "now() - interval '3 hours'", cols: `,"confirmedAt","scheduledStart","scheduledEnd"`, vals: `,now() - interval '3 minutes',now() - interval '16 minutes',now() + interval '104 minutes'` });
  const schedLaterId = mk("CONFIRMED", { tag: "schedlater", paidAt: "now() - interval '3 hours'", cols: `,"confirmedAt","scheduledStart","scheduledEnd"`, vals: `,now() - interval '60 minutes',now() + interval '1 day',now() + interval '1 day 2 hours'` });
  let watched = "";
  for (let i = 0; i < 45 && watched !== "CANCELLED"; i++) {
    await sleep(3000);
    watched = sql(`select status from "Order" where id=${noCourierId}`);
  }
  await sleep(1500);
  const row = (id, cols) => sql(`select ${cols} from "Order" where id=${id}`);
  check("watchdog: an unpaid checkout is cancelled and its stock released", row(unpaidId, `status || '|' || "cancelReason"`) === "CANCELLED|Payment was not completed" && Number(sql(`select "stockQuantity" from "Product" where id=${productId}`)) === stockBefore + 1, row(unpaidId, `status || '|' || coalesce("cancelReason",'')`));
  check("watchdog: a store that has not answered gets one reminder", row(remindId, `status || '|' || ("storeRemindedAt" is not null)`) === "PENDING|true");
  check("watchdog: an order the store never answered is refunded", row(lateStoreId, `status || '|' || "paymentStatus" || '|' || "cancelReason"`) === "CANCELLED|REFUNDED|The store did not respond in time");
  check("watchdog: jobs nobody took are offered again and the customer hears about the delay", row(delayId, `status || '|' || ("lastOfferAt" is not null) || '|' || ("courierSearchNotifiedAt" is not null)`) === "CONFIRMED|true|true");
  check("watchdog: with no courier at all the order is refunded", row(noCourierId, `status || '|' || "paymentStatus" || '|' || "cancelReason"`) === "CANCELLED|REFUNDED|No courier was available");
  for (let i = 0; i < 10 && sql(`select status from "Order" where id=${pickupLateId}`) !== "CANCELLED"; i++) await sleep(1000);
  await sleep(500);
  check("watchdog: a pickup order not collected after 24 h gets one reminder and stays ready", row(pickupRemindId, `status || '|' || ("pickupRemindedAt" is not null)`) === "PROCESSING|true");
  check("watchdog: a pickup order not collected within 72 h is cancelled and refunded", row(pickupLateId, `status || '|' || "paymentStatus" || '|' || "cancelReason"`) === "CANCELLED|REFUNDED|Not collected in time", row(pickupLateId, `status || '|' || coalesce("cancelReason",'')`));
  check("watchdog: a pickup order accepted but never marked ready within 24 h is refunded", row(pickupNeverReadyId, `status || '|' || "paymentStatus" || '|' || "cancelReason"`) === "CANCELLED|REFUNDED|The store did not get the order ready in time", row(pickupNeverReadyId, `status || '|' || coalesce("cancelReason",'')`));
  check("watchdog: an accepted pickup order is never offered to couriers or cancelled for lack of one", row(pickupWaitId, `status || '|' || ("lastOfferAt" is null)`) === "CONFIRMED|true");
  check("watchdog: a scheduled order is first offered to couriers shortly before its slot; the customer is told once", row(so.id, `status || '|' || ("lastOfferAt" is not null) || '|' || ("dispatchStartedAt" is not null) || '|' || ("courierSearchNotifiedAt" is null)`) === "CONFIRMED|true|true|true", row(so.id, `status || '|' || coalesce("lastOfferAt"::text,'-') || '|' || coalesce("dispatchStartedAt"::text,'-')`));
  const soJob = (await call("GET", "/orders/available", null, c1.accessToken)).body.orders?.find((o) => o.id === so.id);
  check("once dispatch started, couriers see the job with its window", !!soJob && !!soJob.scheduledEnd && !!soJob.offeredAt, soJob);
  check("watchdog: a scheduled order with no courier 45 min after its slot start is refunded", row(schedLateId, `status || '|' || "cancelReason"`) === "CANCELLED|No courier was available", row(schedLateId, `status || '|' || coalesce("cancelReason",'')`));
  check("watchdog: the delay notice counts from the slot start (accepted 3 min ago, slot started 16 min ago)", row(schedDelayId, `status || '|' || ("courierSearchNotifiedAt" is not null) || '|' || ("dispatchStartedAt" is not null)`) === "CONFIRMED|true|true");
  check("watchdog: tomorrow's scheduled order is not offered or cancelled yet (accepted an hour ago)", row(schedLaterId, `status || '|' || ("lastOfferAt" is null) || '|' || ("dispatchStartedAt" is null)`) === "CONFIRMED|true|true");
  check("store acceptance records when it happened", sql(`select "confirmedAt" is not null from "Order" where id=${orderId}`) === "t");

  console.log("\n— Tips and app updates");
  const tipped = await call("POST", "/orders", { ...orderBody, tipCents: 200 }, otherCust.accessToken);
  const to = tipped.body.order;
  check("a tip is added to the total and paid to the courier in full", tipped.status === 201 && to.tipCents === 200 && to.totalCents === 5000 + to.deliveryFeeCents + 200 && to.courierFeeCents === 650 + 200 && sql(`select ("courierPay"->>'tipCents')::int from "Order" where id=${to?.id}`) === "200" && to.commissionCents === 500 && !("courierPay" in to), to);
  check("tips are capped at 20 €", (await call("POST", "/orders", { ...orderBody, tipCents: 5000 }, otherCust.accessToken)).status === 400);
  const cfg = await call("GET", "/app-config?app=customer&build=5");
  check("apps learn whether their build is still supported", cfg.status === 200 && cfg.body.updateRequired === false && cfg.body.maintenance?.active === false && cfg.body.storeUrl.includes("com.malvoya.customer"), cfg.body);
  check("app config rejects unknown apps", (await call("GET", "/app-config?app=evil")).status === 400);

  console.log("\n— Fees, exact quotes and promo codes");
  sql(`update "Product" set "stockQuantity"=50 where id=${productId}`);
  const MONEY = ["subtotalCents", "deliveryFeeCents", "serviceFeeCents", "smallOrderFeeCents", "discountCents", "tipCents", "totalCents"];
  const sameMoney = (q, o) => !!q && !!o && MONEY.every((k) => q[k] === o[k]);
  const stockOf = (id) => Number(sql(`select "stockQuantity" from "Product" where id=${id}`));
  const addr = "Aleksanterinkatu 5, Helsinki";
  const quoteBody = { storeId, deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }], tipCents: 150 };
  const quote = (body, tok, api = API) => callAt(api, "POST", "/orders/quote", body, tok);
  const order = (body, tok, api = API) => callAt(api, "POST", "/orders", { deliveryAddress: addr, ...body }, tok);
  const payOrder = (o) => call("POST", "/payments/webhook", null, null, signedWebhook({
    id: `evt_promo_${o.id}_${uniq}`, type: "payment_intent.succeeded",
    data: { object: { id: o.stripePaymentIntentId, amount_received: o.totalCents, metadata: { type: "ORDER", orderId: String(o.id) } } },
  }));

  const sysDefault = (await call("GET", "/admin/system", null, adminToken)).body;
  check("fee levers are off by default and listed in system status", sysDefault.pricing?.serviceFeePercent === 0 && sysDefault.pricing?.smallOrderThresholdCents === 0 && sysDefault.pricing?.minChargeCents === 50 && sysDefault.version === "2.9.0", sysDefault.pricing);
  const stockBeforeQuote = stockOf(productId);
  const ordersBeforeQuote = sql(`select count(*) from "Order" where "userId"=${otherCust.user.id}`);
  const q0 = await quote(quoteBody, otherCust.accessToken);
  const qq = q0.body?.quote;
  check("quote: exact total with no extra fees by default", q0.status === 200 && qq.serviceFeeCents === 0 && qq.smallOrderFeeCents === 0 && qq.smallOrderThresholdCents === 0 && qq.discountCents === 0 && qq.promo === null && qq.promoError === null && qq.totalCents === 5000 + qq.deliveryFeeCents + 150 && qq.deliveryFeeCents === fee, q0.body);
  check("quote says whether the store is open", qq?.store?.openNow === true && qq.store.closedReason === null && "opensAt" in qq.store, qq?.store);
  check("a quote reserves no stock and creates no order", stockOf(productId) === stockBeforeQuote && sql(`select count(*) from "Order" where "userId"=${otherCust.user.id}`) === ordersBeforeQuote);
  const o0 = await order(quoteBody, otherCust.accessToken);
  check("the order charges exactly the quoted price", o0.status === 201 && sameMoney(qq, o0.body.order) && o0.body.order.promoCodeId === null, [qq, o0.body.order]);
  check("quote needs a signed-in customer", (await quote(quoteBody)).status === 401 && (await quote(quoteBody, vendor.accessToken)).status === 403);
  const badItemQ = await quote({ ...quoteBody, items: [{ productId: 999999, quantity: 1 }] }, otherCust.accessToken);
  const badItemO = await order({ ...quoteBody, items: [{ productId: 999999, quantity: 1 }] }, otherCust.accessToken);
  check("quote refuses unknown items like checkout does", badItemQ.status === 400 && badItemQ.status === badItemO.status && badItemQ.body.error === badItemO.body.error, [badItemQ.body, badItemO.body]);
  check("quote refuses more than the stock like checkout does", (await quote({ ...quoteBody, items: [{ productId, quantity: 20 }, { productId, quantity: 20 }, { productId, quantity: 20 }] }, otherCust.accessToken)).status === 400);
  check("quote for an unknown store is 404", (await quote({ ...quoteBody, storeId: 999999 }, otherCust.accessToken)).status === 404);

  console.log("\n— Promo codes (admin)");
  const mkPromo = (body, tok = adminToken) => call("POST", "/admin/promo-codes", body, tok);
  check("promo codes need a signed-in admin", (await call("GET", "/admin/promo-codes")).status === 401);
  check("customers cannot list, create or change promo codes", (await call("GET", "/admin/promo-codes", null, otherCust.accessToken)).status === 403 && (await mkPromo({ code: `HACK${uniq}`, description: "free stuff", kind: "PERCENT", value: 100 }, otherCust.accessToken)).status === 403 && (await call("PATCH", "/admin/promo-codes/1", { active: true }, vendor.accessToken)).status === 403);
  const ten = await mkPromo({ code: `ten-${uniq}`, description: "10 % off", kind: "PERCENT", value: 10 });
  check("admin creates a code; it is stored in capitals", ten.status === 201 && ten.body.promoCode.code === `TEN-${uniq}` && ten.body.promoCode.perUserLimit === 1 && ten.body.promoCode.active === true, ten.body);
  check("codes are unique (any case)", (await mkPromo({ code: `Ten-${uniq}`, description: "again", kind: "AMOUNT", value: 100 })).status === 409);
  check("a percentage above 100 is refused", (await mkPromo({ code: `BAD-${uniq}`, description: "bad one", kind: "PERCENT", value: 150 })).status === 400);

  console.log("\n— Promo codes at checkout");
  const pirjo = await register("Pirjo");
  const qTen = (await quote({ ...quoteBody, promoCode: ` ten-${uniq} ` }, pirjo.accessToken)).body.quote;
  check("percentage code: 10 % of the items off, shown with its description", qTen?.discountCents === 500 && qTen.totalCents === 5000 + fee + 150 - 500 && qTen.promo?.code === `TEN-${uniq}` && qTen.promo?.description === "10 % off" && qTen.promoError === null, qTen);
  const oTen = await order({ ...quoteBody, promoCode: `TEN-${uniq}` }, pirjo.accessToken);
  const ot = oTen.body.order;
  check("an order with a code charges the quoted price", oTen.status === 201 && sameMoney(qTen, ot) && ot.promoCodeId === ten.body.promoCode.id && ot.promoCode?.code === `TEN-${uniq}`, oTen.body);
  check("Malvoya pays the discount: store and courier pay are not reduced", ot?.commissionCents === 500 && ot?.sellerPayoutCents === 4500 && ot?.courierFeeCents === 650 + 150, ot);
  check("an unpaid order does not use the code up", sql(`select count(*) from "PromoRedemption" where "promoCodeId"=${ten.body.promoCode.id}`) === "0");
  check("an unknown code is reported, the quote still works", (await quote({ ...quoteBody, promoCode: "NOPE-NOPE" }, pirjo.accessToken)).body.quote?.promoError?.includes("not valid"));

  const seven = await mkPromo({ code: `SEVEN-${uniq}`, description: "7 € off from 60 €", kind: "AMOUNT", value: 700, minSubtotalCents: 6000 });
  const qLow = await quote({ ...quoteBody, promoCode: `SEVEN-${uniq}` }, pirjo.accessToken);
  check("amount code below its minimum: no discount and a readable reason", seven.status === 201 && qLow.status === 200 && qLow.body.quote.discountCents === 0 && qLow.body.quote.promo === null && /60,00/.test(qLow.body.quote.promoError || ""), qLow.body);
  const qHigh = (await quote({ ...quoteBody, items: [{ productId, quantity: 2 }], promoCode: `SEVEN-${uniq}` }, pirjo.accessToken)).body.quote;
  check("amount code at or above its minimum takes the amount off", qHigh?.discountCents === 700 && qHigh.totalCents === 10000 + fee + 150 - 700, qHigh);
  const stockBeforeRefused = stockOf(productId);
  const oLow = await order({ ...quoteBody, promoCode: `SEVEN-${uniq}` }, pirjo.accessToken);
  check("checkout refuses a code that does not apply (409), and takes no stock", oLow.status === 409 && /60,00/.test(oLow.body.error || "") && stockOf(productId) === stockBeforeRefused, oLow.body);

  const yesterday = new Date(Date.now() - 86_400_000).toISOString();
  const tomorrow = new Date(Date.now() + 86_400_000).toISOString();
  await mkPromo({ code: `OLD-${uniq}`, description: "Summer sale", kind: "PERCENT", value: 20, endsAt: yesterday });
  check("an expired code gives no discount", /expired/.test((await quote({ ...quoteBody, promoCode: `OLD-${uniq}` }, pirjo.accessToken)).body.quote?.promoError || ""));
  const oOld = await order({ ...quoteBody, promoCode: `OLD-${uniq}` }, pirjo.accessToken);
  check("checkout refuses an expired code with a readable error", oOld.status === 409 && /expired/.test(oOld.body.error || ""), oOld.body);
  await mkPromo({ code: `SOON-${uniq}`, description: "Starts tomorrow", kind: "PERCENT", value: 20, startsAt: tomorrow });
  check("a code that has not started gives no discount", /not active yet/.test((await quote({ ...quoteBody, promoCode: `SOON-${uniq}` }, pirjo.accessToken)).body.quote?.promoError || ""));
  const off = await call("PATCH", `/admin/promo-codes/${ten.body.promoCode.id}`, { active: false }, adminToken);
  check("admin deactivates a code; it stops working", off.status === 200 && off.body.promoCode.active === false && /not valid/.test((await quote({ ...quoteBody, promoCode: `TEN-${uniq}` }, pirjo.accessToken)).body.quote?.promoError || ""), off.body);
  await call("PATCH", `/admin/promo-codes/${ten.body.promoCode.id}`, { active: true }, adminToken);

  const first = await mkPromo({ code: `FIRST-${uniq}`, description: "5 € off your first order", kind: "AMOUNT", value: 500, firstOrderOnly: true });
  check("first-order code works for a new customer", (await quote({ ...quoteBody, promoCode: `FIRST-${uniq}` }, pirjo.accessToken)).body.quote?.discountCents === 500);
  check("first-order code is refused for a customer with paid orders", /first order/.test((await quote({ ...quoteBody, promoCode: `FIRST-${uniq}` }, otherCust.accessToken)).body.quote?.promoError || ""));

  const once = await mkPromo({ code: `ONCE-${uniq}`, description: "3 € off, one use", kind: "AMOUNT", value: 300, maxRedemptions: 1 });
  const oOnce = (await order({ ...quoteBody, promoCode: `ONCE-${uniq}` }, pirjo.accessToken)).body.order;
  check("an order with a limited code is created", oOnce?.discountCents === 300, oOnce);
  check("paying the order uses the code (once, even if Stripe repeats itself)", (await payOrder(oOnce)).status === 200 && (await payOrder(oOnce)).status === 200 && sql(`select count(*) || '|' || sum("discountCents") from "PromoRedemption" where "promoCodeId"=${once.body.promoCode.id}`) === "1|300");
  check("a code with no uses left is used up for everyone", /run out/.test((await quote({ ...quoteBody, promoCode: `ONCE-${uniq}` }, otherCust.accessToken)).body.quote?.promoError || "") && (await order({ ...quoteBody, promoCode: `ONCE-${uniq}` }, otherCust.accessToken)).status === 409);
  check("after the first paid order the first-order code no longer applies", /first order/.test((await quote({ ...quoteBody, promoCode: `FIRST-${uniq}` }, pirjo.accessToken)).body.quote?.promoError || ""));
  const cancelOnce = await call("POST", `/orders/${oOnce.id}/cancel`, null, pirjo.accessToken);
  check("cancelling before delivery gives the code back", cancelOnce.status === 200 && sql(`select count(*) from "PromoRedemption" where "promoCodeId"=${once.body.promoCode.id}`) === "0" && (await quote({ ...quoteBody, promoCode: `ONCE-${uniq}` }, otherCust.accessToken)).body.quote?.discountCents === 300, cancelOnce.body);
  check("a cancelled order does not count as a first order", (await quote({ ...quoteBody, promoCode: `FIRST-${uniq}` }, pirjo.accessToken)).body.quote?.discountCents === 500);

  const twice = await mkPromo({ code: `PERUSER-${uniq}`, description: "2 € off", kind: "AMOUNT", value: 200 });
  const oTw = (await order({ ...quoteBody, promoCode: `PERUSER-${uniq}` }, pirjo.accessToken)).body.order;
  await payOrder(oTw);
  check("each customer can use a code once by default", /already used/.test((await quote({ ...quoteBody, promoCode: `PERUSER-${uniq}` }, pirjo.accessToken)).body.quote?.promoError || "") && (await quote({ ...quoteBody, promoCode: `PERUSER-${uniq}` }, otherCust.accessToken)).body.quote?.discountCents === 200);
  const listP = await call("GET", "/admin/promo-codes", null, adminToken);
  const lp = listP.body.promoCodes?.find((p) => p.id === twice.body.promoCode.id);
  check("admin list shows how often a code was used and the discount given", listP.status === 200 && lp?.redemptionCount === 1 && lp?.discountGivenCents === 200, lp);
  const ended = await call("PATCH", `/admin/promo-codes/${twice.body.promoCode.id}`, { endsAt: yesterday }, adminToken);
  check("admin ends a campaign; paid orders keep their discount", ended.status === 200 && /expired/.test((await quote({ ...quoteBody, promoCode: `PERUSER-${uniq}` }, otherCust.accessToken)).body.quote?.promoError || "") && sql(`select "discountCents" from "Order" where id=${oTw.id}`) === "200");
  check("changing an unknown code is 404", (await call("PATCH", "/admin/promo-codes/999999", { active: false }, adminToken)).status === 404);

  const socks = (await call("POST", "/products", { name: "Wool socks", category: "Socks", salePriceCents: 100, stockQuantity: 20, images: [ownImage(storeId, "socks")] }, vendor.accessToken)).body.product;
  await mkPromo({ code: `BIG-${uniq}`, description: "1000 € off", kind: "AMOUNT", value: 100000 });
  const qBig = (await quote({ ...quoteBody, tipCents: 0, items: [{ productId: socks.id, quantity: 1 }], promoCode: `BIG-${uniq}` }, otherCust.accessToken)).body.quote;
  check("a discount never exceeds the item subtotal", qBig?.discountCents === 100 && qBig.totalCents === qBig.deliveryFeeCents && qBig.totalCents >= 50, qBig);
  // The 0,50 € floor only bites when delivery is below 0,50 €, which the API never charges: check the engine directly
  Object.assign(process.env, testEnv);
  const engine = require(path.join(__dirname, "..", "..", "dist", "utils", "pricing.js"));
  const zeroFees = { serviceFeePercent: 0, serviceFeeMinCents: 0, serviceFeeMaxCents: 0, smallOrderThresholdCents: 0, smallOrderFeeCents: 0 };
  const floor = engine.calcCheckoutPricing({ subtotalCents: 100, commissionRate: 0.1, deliveryFeeCents: 0, promo: { kind: "AMOUNT", value: 1000, maxDiscountCents: null }, config: zeroFees, courierFeeShare: 1 });
  check("a discount never takes the charge below 0,50 € (Stripe minimum)", floor.discountCents === 50 && floor.totalCents === 50 && floor.commissionCents === 10 && floor.sellerPayoutCents === 90, floor);
  const capped = engine.calcCheckoutPricing({ subtotalCents: 20000, commissionRate: 0.1, deliveryFeeCents: 190, promo: { kind: "PERCENT", value: 50, maxDiscountCents: 1500 }, config: zeroFees, courierFeeShare: 1 });
  check("a percentage code respects its maximum discount", capped.discountCents === 1500 && capped.totalCents === 20000 + 190 - 1500, capped);

  console.log("\n— Reserve & collect (pickup)");
  const payNow = (o, api = API) => callAt(api, "POST", "/payments/webhook", null, null, signedWebhook({
    id: `evt_pk_${o.id}_${uniq}`, type: "payment_intent.succeeded",
    data: { object: { id: o.stripePaymentIntentId, amount_received: o.totalCents, metadata: { type: "ORDER", orderId: String(o.id) } } },
  }));
  const pickupBody = { storeId, fulfilment: "PICKUP", items: [{ productId, quantity: 1 }] };
  const pq = await call("POST", "/orders/quote", pickupBody, otherCust.accessToken);
  check("pickup quote: no delivery fee, with the store's name and address", pq.status === 200 && pq.body.quote.fulfilment === "PICKUP" && pq.body.quote.deliveryFeeCents === 0 && pq.body.quote.tipCents === 0 && pq.body.quote.totalCents === 5000 && pq.body.quote.pickup?.storeName === `Vera Vintage ${uniq}` && pq.body.quote.pickup?.address === "Mannerheimintie 1, Helsinki", pq.body);
  const dq = (await call("POST", "/orders/quote", { storeId, deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }] }, otherCust.accessToken)).body.quote;
  check("delivery quotes say DELIVERY and have no pickup block", dq?.fulfilment === "DELIVERY" && !("pickup" in dq) && dq.deliveryFeeCents > 0, dq);
  const tipQ = await call("POST", "/orders/quote", { ...pickupBody, tipCents: 100 }, otherCust.accessToken);
  const tipO = await call("POST", "/orders", { ...pickupBody, tipCents: 100 }, otherCust.accessToken);
  check("a pickup order cannot carry a tip (400)", tipQ.status === 400 && tipO.status === 400 && /tip/i.test(tipO.body.error || ""), [tipQ.body, tipO.body]);
  check("a delivery order still needs an address", (await call("POST", "/orders", { storeId, items: [{ productId, quantity: 1 }] }, otherCust.accessToken)).status === 400);
  const poRes = await call("POST", "/orders", { ...pickupBody, notes: "I'll come at five" }, otherCust.accessToken);
  const po = poRes.body.order;
  check("pickup order without an address: no delivery fee, no courier pay, same commission", poRes.status === 201 && po.fulfilment === "PICKUP" && po.deliveryFeeCents === 0 && po.courierFeeCents === 0 && po.deliveryAddress === null && po.totalCents === 5000 && po.commissionCents === 500 && sql(`select "courierPay" is null from "Order" where id=${po.id}`) === "t", poRes.body);
  check("no pickup code before payment", !po.pickupCode && sql(`select "pickupCode" is null from "Order" where id=${po.id}`) === "t");
  await payNow(po);
  check("payment creates a 6-digit pickup code", sql(`select "pickupCode" ~ '^[0-9]{6}$' from "Order" where id=${po.id}`) === "t");
  const pkCode = sql(`select "pickupCode" from "Order" where id=${po.id}`);
  check("the customer does not see the code before the store accepts", (await call("GET", `/orders/${po.id}`, null, otherCust.accessToken)).body.order?.pickupCode === null);
  c1Sock.events.length = 0;
  check("store accepts the pickup order", (await call("PATCH", `/orders/${po.id}/status`, { status: "CONFIRMED" }, vendor.accessToken)).status === 200);
  await sleep(500);
  check("couriers are never offered pickup orders", !c1Sock.events.some((e) => e.ev === "courier:dispatch_offer" && e.data.orderId === po.id) && sql(`select "lastOfferAt" is null from "Order" where id=${po.id}`) === "t" && !(await call("GET", "/orders/available", null, c1.accessToken)).body.orders?.some((o) => o.id === po.id));
  check("a courier cannot take a pickup order", (await call("PATCH", `/orders/${po.id}/assign-courier`, null, c2.accessToken)).status === 409);
  const custView = (await call("GET", `/orders/${po.id}`, null, otherCust.accessToken)).body.order;
  const custListed = (await call("GET", "/orders", null, otherCust.accessToken)).body.orders?.find((o) => o.id === po.id);
  check("the customer sees the pickup code (order and list) once accepted", custView?.pickupCode === pkCode && custView.fulfilment === "PICKUP" && custListed?.pickupCode === pkCode, [custView?.pickupCode, custListed?.pickupCode]);
  const vendView = (await call("GET", `/orders/${po.id}`, null, vendor.accessToken)).body.order;
  const vendListed = (await call("GET", "/orders", null, vendor.accessToken)).body.orders?.find((o) => o.id === po.id);
  const adminListed = (await call("GET", "/admin/orders", null, adminToken)).body.orders?.find((o) => o.id === po.id);
  check("store and admin get the order with its fulfilment but never the code", vendView?.fulfilment === "PICKUP" && !("pickupCode" in vendView) && vendListed?.fulfilment === "PICKUP" && !("pickupCode" in vendListed) && !!adminListed && !("pickupCode" in adminListed) && !JSON.stringify([vendView, vendListed, adminListed]).includes(`"${pkCode}"`), [vendView, vendListed]);
  check("handing over before the order is ready is refused", (await call("POST", `/orders/${po.id}/collect`, { code: pkCode }, vendor.accessToken)).status === 409);
  const ready = await call("PATCH", `/orders/${po.id}/status`, { status: "PROCESSING" }, vendor.accessToken);
  check("store marks the order ready; readyAt is set", ready.status === 200 && !!ready.body.order?.readyAt && !("pickupCode" in ready.body.order), ready.body);
  check("a pickup order cannot be shipped", (await call("PATCH", `/orders/${po.id}/status`, { status: "SHIPPED" }, vendor.accessToken)).status === 409);
  check("another store cannot hand it over; a customer cannot either", (await call("POST", `/orders/${po.id}/collect`, { code: pkCode }, otherVendor.accessToken)).status === 404 && (await call("POST", `/orders/${po.id}/collect`, { code: pkCode }, otherCust.accessToken)).status === 403);
  const wrongCode = pkCode === "000000" ? "111111" : "000000";
  const tries = [];
  for (let i = 0; i < 5; i++) tries.push(await call("POST", `/orders/${po.id}/collect`, { code: wrongCode }, vendor.accessToken));
  check("wrong codes: 400 with the attempts left (4, 3, 2, 1)", tries.slice(0, 4).every((t, i) => t.status === 400 && t.body.ok === false && t.body.attemptsLeft === 4 - i && typeof t.body.error === "string"), tries.map((t) => t.body));
  check("the fifth wrong code locks the handover for 15 minutes", tries[4].status === 400 && tries[4].body.attemptsLeft === 0 && !!tries[4].body.lockedUntil && sql(`select "pickupLockedUntil" > now() + interval '14 minutes' from "Order" where id=${po.id}`) === "t", tries[4].body);
  const whileLocked = await call("POST", `/orders/${po.id}/collect`, { code: pkCode }, vendor.accessToken);
  check("while locked even the right code is refused", whileLocked.status === 400 && whileLocked.body.attemptsLeft === 0 && sql(`select status from "Order" where id=${po.id}`) === "PROCESSING", whileLocked.body);
  sql(`update "Order" set "pickupLockedUntil" = now() - interval '1 minute' where id=${po.id}`);
  const collected = await call("POST", `/orders/${po.id}/collect`, { code: ` ${pkCode} ` }, vendor.accessToken);
  check("the right code hands the order over: DELIVERED, handover PICKUP, withdrawal period starts", collected.status === 200 && collected.body.order?.status === "DELIVERED" && collected.body.order.handoverMethod === "PICKUP" && !!collected.body.order.deliveredAt && !("pickupCode" in collected.body.order), collected.body);
  await sleep(700);
  check("collection schedules the store payout after the return window; no courier payout", sql(`select status || '|' || "amountCents" || '|' || ("releaseAt" > now() + interval '14 days') from "Payout" where "orderId"=${po.id} and party='STORE'`) === "SCHEDULED|4500|true" && sql(`select count(*) from "Payout" where "orderId"=${po.id} and party='COURIER'`) === "0");
  check("after collection the customer no longer gets the code", (await call("GET", `/orders/${po.id}`, null, otherCust.accessToken)).body.order?.pickupCode === null);
  check("a collected order cannot be collected again", (await call("POST", `/orders/${po.id}/collect`, { code: pkCode }, vendor.accessToken)).status === 409);

  console.log("\n— Returning some items");
  // A delivered order: 2 × 30 € + 1 × 40 €, 3 € delivery, 10 € promo discount (paid by Malvoya), store payout 90 € pending
  const p2stock = () => Number(sql(`select "stockQuantity" from "Product" where id=${p2.id}`));
  const pStock = () => Number(sql(`select "stockQuantity" from "Product" where id=${productId}`));
  const rOrder = Number(sql(`insert into "Order" ("userId","storeId","status","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","discountCents","stripePaymentIntentId","paymentStatus","paidAt","deliveredAt","deliveryAddress","updatedAt") values (${otherCust.user.id},${storeId},'DELIVERED',10000,300,300,1000,9000,9300,1000,'pi_ret_${uniq}','SUCCEEDED',now(),now(),'Aleksanterinkatu 5, Helsinki',now()) returning id`).split("\n")[0]);
  const lineA = Number(sql(`insert into "OrderItem" ("orderId","productId","quantity","unitCents") values (${rOrder},${productId},2,3000) returning id`).split("\n")[0]);
  const lineB = Number(sql(`insert into "OrderItem" ("orderId","productId","quantity","unitCents") values (${rOrder},${p2.id},1,4000) returning id`).split("\n")[0]);
  sql(`insert into "Payout" ("orderId","party","storeId","amountCents","status","releaseAt","updatedAt") values (${rOrder},'STORE',${storeId},9000,'SCHEDULED',now() + interval '15 days',now())`);
  check("you cannot return more than you bought", (await call("POST", "/returns", { orderId: rOrder, reason: "CHANGED_MIND", items: [{ orderItemId: lineA, quantity: 3 }] }, otherCust.accessToken)).status === 400);
  check("you cannot return a line of another order", (await call("POST", "/returns", { orderId: rOrder, reason: "CHANGED_MIND", items: [{ orderItemId: 999999, quantity: 1 }] }, otherCust.accessToken)).status === 400);
  check("someone else cannot return your items", (await call("POST", "/returns", { orderId: rOrder, reason: "CHANGED_MIND", items: [{ orderItemId: lineA, quantity: 1 }] }, pirjo.accessToken)).status === 404);
  const ret1 = await call("POST", "/returns", { orderId: rOrder, reason: "CHANGED_MIND", items: [{ orderItemId: lineA, quantity: 1 }] }, otherCust.accessToken);
  const r1i = ret1.body.return?.items?.[0];
  check("customer returns one of two coats; the return lists the item and the expected refund (30 € − 3 € discount share)", ret1.status === 201 && ret1.body.return.items.length === 1 && r1i?.orderItemId === lineA && r1i.quantity === 1 && r1i.name === "Wool coat" && r1i.unitCents === 3000 && ret1.body.return.refundCents === null && ret1.body.return.expectedRefundCents === 2700, ret1.body);
  check("only what is left can be returned again", (await call("POST", "/returns", { orderId: rOrder, reason: "CHANGED_MIND", items: [{ orderItemId: lineA, quantity: 2 }] }, otherCust.accessToken)).status === 400);
  const stockA0 = pStock(), stockB0 = p2stock();
  const ref1 = await call("PATCH", `/returns/${ret1.body.return?.id}/status`, { status: "REFUNDED" }, vendor.accessToken);
  check("partial refund: the item price less its share of the discount, no delivery fee", ref1.status === 200 && ref1.body.return?.refundCents === 2700 && ref1.body.return.items?.length === 1 && sql(`select "refundedCents" || '|' || status from "Order" where id=${rOrder}`) === "2700|DELIVERED", ref1.body);
  check("partial refund: the store payout drops by the item less its commission (90 € − 27 €); only that item goes back into stock", sql(`select status || '|' || "amountCents" from "Payout" where "orderId"=${rOrder} and party='STORE'`) === "SCHEDULED|6300" && pStock() === stockA0 + 1 && p2stock() === stockB0);
  const ret2 = await call("POST", "/returns", { orderId: rOrder, reason: "CHANGED_MIND" }, otherCust.accessToken);
  const r2items = (ret2.body.return?.items || []).map((i) => `${i.orderItemId}x${i.quantity}`).sort().join();
  check("a return without items covers what is left of the order", ret2.status === 201 && r2items === [`${lineA}x1`, `${lineB}x1`].sort().join() && ret2.body.return.expectedRefundCents === 6600, ret2.body);
  check("nothing left to return: 409", (await call("POST", "/returns", { orderId: rOrder, reason: "CHANGED_MIND" }, otherCust.accessToken)).status === 409);
  const vendRet = (await call("GET", "/returns", null, vendor.accessToken)).body.returns?.find((r) => r.id === ret2.body.return?.id);
  check("the store's return list shows the items and the order", vendRet?.items?.length === 2 && vendRet.order?.id === rOrder && !("returns" in vendRet.order), vendRet);
  const ref2 = await call("PATCH", `/returns/${ret2.body.return?.id}/status`, { status: "REFUNDED" }, vendor.accessToken);
  check("the return that completes the order also refunds the delivery fee: total refunded = everything paid", ref2.status === 200 && ref2.body.return?.refundCents === 6600 && sql(`select "refundedCents" || '|' || status || '|' || "paymentStatus" from "Order" where id=${rOrder}`) === "9300|REFUNDED|REFUNDED", ref2.body);
  check("the store payout is fully taken back; the rest goes back into stock", sql(`select status || '|' || "amountCents" from "Payout" where "orderId"=${rOrder} and party='STORE'`) === "CANCELLED|0" && pStock() === stockA0 + 2 && p2stock() === stockB0 + 1);

  console.log("\n— Transparent courier pay (formula)");
  const cpEngine = require(path.join(__dirname, "..", "..", "dist", "utils", "courierPay.js"));
  const payCfg = { mode: "formula", baseCents: 450, perKmCents: 110, minCents: 650, roadFactor: 1.3, approachFreeKm: 2, approachPerKmCents: 50, waitFreeMinutes: 5, waitPerMinCents: 20, waitMaxCents: 400, feeShare: 1 };
  const payAt = (km, extra = {}) => cpEngine.calcCourierPay({ straightKm: km, deliveryFeeCents: 0, config: payCfg, ...extra });
  check("pay formula at known distances: 1 km → 6.50 € minimum, 3 km → 8.79 €, 6 km → 13.08 €", payAt(1).distanceKm === 1.3 && payAt(1).topUpCents === 57 && payAt(1).totalCents === 650 && payAt(3).distanceKm === 3.9 && payAt(3).distanceCents === 429 && payAt(3).totalCents === 879 && payAt(6).totalCents === 1308, [1, 3, 6].map((k) => payAt(k).totalCents));
  check("waiting pay: first 5 min free, then 0.20 €/min, capped at 4 €", payAt(3, { waitMinutes: 5 }).waitCents === 0 && payAt(3, { waitMinutes: 12 }).waitCents === 140 && payAt(3, { waitMinutes: 90 }).waitCents === 400);
  check("ride to the shop beyond 2 km is paid; tips are added in full", payAt(3, { approachStraightKm: 4 }).approachKm === 5.2 && payAt(3, { approachStraightKm: 4 }).approachCents === 160 && payAt(3, { approachStraightKm: 1 }).approachCents === 0 && payAt(3, { tipCents: 300 }).totalCents === 1179);
  // A later settings change (here: free waiting cut to 0 and a lower rate) must not touch a job already priced
  const cheaperCfg = { ...payCfg, waitFreeMinutes: 0, waitPerMinCents: 5, approachPerKmCents: 10 };
  const priced = payAt(3);
  const waitedLater = cpEngine.withWaiting(priced, 12, cheaperCfg);
  const rodeLater = cpEngine.withApproach(priced, 4, cheaperCfg);
  check("a job keeps the pay rates it was offered with, even if settings change later", waitedLater.waitCents === 140 && rodeLater.approachCents === 160, [waitedLater.waitCents, rodeLater.approachCents]);
  const payRule = payAt(1).summary;
  check("the pay rule is one sentence in English and Finnish", payRule.en === "Every delivery pays 4.50 € plus 1.10 € per km from shop to customer (at least 6.50 €), plus 0.50 €/km for the ride to the shop beyond 2 km, plus 0.20 €/min for waiting at the shop after 5 minutes, and you keep 100 % of tips." && payRule.fi.startsWith("Jokainen toimitus maksaa 4,50 €") && payRule.fi.includes("Juomarahat ovat 100 % sinun"), payRule);
  const sysPay = (await call("GET", "/admin/system", null, adminToken)).body.pricing;
  const payEx = (k) => sysPay?.courierPay?.examples?.find((e) => e.straightKm === k);
  check("system status shows courier pay settings and the delivery margin on 1/3/6 km jobs", sysPay?.courierPay?.mode === "formula" && sysPay.courierPay.baseCents === 450 && sysPay.courierPay.summary?.en === payRule.en && sysPay.deliveryFee?.baseCents === 190 && payEx(1)?.customerFeeCents === 190 && payEx(1)?.courierPayCents === 650 && payEx(1)?.marginCents === -460 && payEx(3)?.customerFeeCents === 265 && payEx(3)?.courierPayCents === 879 && payEx(6)?.customerFeeCents === 415 && payEx(6)?.courierPayCents === 1308, sysPay);

  const farRes = await call("POST", "/orders", { storeId, deliveryAddress: "Kauppakatu 1, Helsinki", deliveryLat: 60.2, deliveryLng: 24.98, items: [{ productId, quantity: 1 }], tipCents: 100 }, otherCust.accessToken);
  const far = farRes.body.order;
  check("a 4 km order: the customer pays 3.15 € delivery; courier pay 4.50 € + 5.2 km × 1.10 € + tip", farRes.status === 201 && far.deliveryFeeCents === 315 && sql(`select ("courierPay"->>'distanceKm') || '|' || ("courierPay"->>'distanceCents') || '|' || ("courierPay"->>'topUpCents') from "Order" where id=${far?.id}`) === "5.2|572|0" && far.courierFeeCents === 1022 + 100 && far.totalCents === 5000 + 315 + 100, far);
  await payOrder(far);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.171, longitude: 24.941 }, c1.accessToken);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.2, longitude: 24.9 }, c2.accessToken);
  c1Sock.events.length = 0;
  c2Sock.events.length = 0;
  check("store accepts the 4 km order", (await call("PATCH", `/orders/${far.id}/status`, { status: "CONFIRMED" }, vendor.accessToken)).status === 200);
  await sleep(600);
  const farOffer1 = c1Sock.events.find((e) => e.ev === "courier:dispatch_offer" && e.data.orderId === far.id)?.data;
  const farOffer2 = c2Sock.events.find((e) => e.ev === "courier:dispatch_offer" && e.data.orderId === far.id)?.data;
  check("offers show the pay breakdown and explanation before accepting (courier at the shop: no ride pay)", farOffer1?.courierPay?.totalCents === 1122 && farOffer1.courierFeeCents === 1122 && farOffer1.courierPay.approachCents === 0 && farOffer1.courierPay.waitCents === 0 && farOffer1.courierPay.explanation?.en.includes("5.2 km × 1.10 €/km") && farOffer1.courierPay.explanation?.fi.includes("5,2 km × 1,10 €/km"), farOffer1?.courierPay);
  check("offers say when the job was first offered", !!farOffer1?.offeredAt && Math.abs(new Date(farOffer1.offeredAt).getTime() - Date.now()) < 60_000, farOffer1?.offeredAt);
  check("a courier 4 km from the shop sees the ride to the shop in their offer", farOffer2?.courierPay?.approachKm === 5.2 && farOffer2.courierPay.approachCents === 160 && farOffer2.courierPay.totalCents === 1282 && farOffer2.courierFeeCents === 1282, farOffer2?.courierPay);
  const farJob = (await call("GET", "/orders/available", null, c2.accessToken)).body.orders?.find((o) => o.id === far.id);
  check("the job list shows the same breakdown, the pay rule and the waiting policy", farJob?.courierPay?.totalCents === 1282 && farJob.courierFeeCents === 1282 && farJob.courierPay.summary?.en === payRule.en && /5 min/.test(farJob.courierPay.waitPolicy?.en || "") && /not ready/.test(farJob.courierPay.waitPolicy?.en || "") && /ei ole valmis/.test(farJob.courierPay.waitPolicy?.fi || "") && !!farJob.offeredAt && !("deliveryAddress" in farJob), farJob);
  // Ride-to-shop pay cannot be inflated with a made-up or old position
  await call("POST", "/courier/status", { isOnline: true, latitude: 69.9, longitude: 27.0 }, c1.accessToken);
  const tooFar = await call("PATCH", `/orders/${far.id}/assign-courier`, null, c1.accessToken);
  check("a courier far away (fresh position beyond 7.5 km) cannot take the job", tooFar.status === 409 && /too far/.test(tooFar.body.error || "") && sql(`select "courierId" is null from "Order" where id=${far.id}`) === "t", tooFar.body);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.171, longitude: 24.941 }, c1.accessToken);
  const engineCfg = { mode: "formula", baseCents: 450, perKmCents: 110, minCents: 650, roadFactor: 1.3, approachFreeKm: 2, approachPerKmCents: 50, approachMaxKm: 7.5, waitFreeMinutes: 5, waitPerMinCents: 20, waitMaxCents: 400, feeShare: 1 };
  const farRide = require(path.join(__dirname, "..", "..", "dist", "utils", "courierPay.js")).calcCourierPay({ straightKm: 3, deliveryFeeCents: 0, approachStraightKm: 900, config: engineCfg });
  check("the paid ride to the shop is capped at 7.5 km straight (9.8 km route): at most 3.90 €", farRide.approachCents === Math.round((9.8 - 2) * 50), farRide.approachCents);
  c2Sock.events.length = 0;
  const farAcc = await call("PATCH", `/orders/${far.id}/assign-courier`, null, c2.accessToken);
  check("on acceptance the ride to the shop is fixed from the courier's position", farAcc.status === 200 && sql(`select "courierFeeCents" from "Order" where id=${far.id}`) === "1282", farAcc.body);
  await sleep(300);
  check("other couriers hear that the job is taken", c1Sock.events.some((e) => e.ev === "courier:offer_closed" && e.data.orderId === far.id && e.data.reason === "taken"));
  check("checking in far from the shop is refused (the waiting clock needs a position at the shop)", (await call("POST", `/orders/${far.id}/arrived-at-store`, null, c2.accessToken)).status === 409);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.1702, longitude: 24.9402 }, c2.accessToken);
  check("only the assigned courier can check in at the shop", (await call("POST", `/orders/${far.id}/arrived-at-store`, null, c1.accessToken)).status === 404);
  const arrived1 = await call("POST", `/orders/${far.id}/arrived-at-store`, null, c2.accessToken);
  const arrived2 = await call("POST", `/orders/${far.id}/arrived-at-store`, null, c2.accessToken);
  check("the courier checks in at the shop (idempotent)", arrived1.status === 200 && !!arrived1.body.order?.courierArrivedAt && arrived2.status === 200 && arrived2.body.order?.courierArrivedAt === arrived1.body.order.courierArrivedAt, [arrived1.body, arrived2.body]);
  // Accepted 40 min ago (expected ride 5.2 km at 15 km/h ≈ 21 min), at the shop for the last 12 min, store never marked it ready
  sql(`update "Order" set "courierArrivedAt" = now() - interval '12 minutes', "acceptedAt" = now() - interval '40 minutes' where id=${far.id}`);
  check("pickup after waiting at the shop", (await call("PATCH", `/orders/${far.id}/status`, { status: "SHIPPED" }, c2.accessToken)).status === 200);
  const farMine = (await call("GET", "/orders/courier/mine", null, c2.accessToken)).body.orders?.find((o) => o.id === far.id);
  check("waiting beyond 5 min is added at pickup: 12 min → 7 × 0.20 € = 1.40 €", farMine?.courierPay?.waitMinutes === 12 && farMine.courierPay.waitCents === 140 && farMine.courierPay.totalCents === 1422 && farMine.courierFeeCents === 1422 && !!farMine.courierArrivedAt && farMine.courierPay.explanation.en.includes("waiting 12 min = 1.40 €"), farMine?.courierPay);
  check("checking in after pickup is refused", (await call("POST", `/orders/${far.id}/arrived-at-store`, null, c2.accessToken)).status === 409);
  const farDone = await call("POST", `/orders/${far.id}/deliver`, { method: "IN_PERSON" }, c2.accessToken);
  await sleep(800);
  check("the courier payout is exactly the explained total", farDone.status === 200 && sql(`select "amountCents" from "Payout" where "orderId"=${far.id} and party='COURIER'`) === "1422");
  // Charge 54.15 €: the store's 45.00 € is reserved on it, so the courier's 14.22 € (> 9.15 € left) is paid from Malvoya's balance
  const farCp = sql(`select id from "Payout" where "orderId"=${far.id} and party='COURIER'`);
  if (sql(`select status from "Payout" where id=${farCp}`) !== "PAID") {
    sql(`update "Courier" set "stripeAccountId" = coalesce("stripeAccountId", 'acct_e2e_${uniq}'), "payoutsEnabled" = true where "userId"=${c2.user.id}; update "Payout" set status='FAILED' where id=${farCp}`);
    await call("POST", `/admin/payouts/${farCp}/retry`, null, adminToken);
  }
  check("payout above what is left of the charge is not tied to it (Stripe would refuse the store's transfer)", sql(`select status || '|' || "amountCents" || '|' || "linkedToCharge" from "Payout" where id=${farCp}`) === "PAID|1422|false");
  check("a payout that fits in the charge is tied to it", sql(`select "linkedToCharge" from "Payout" where id=${cpId}`) === "t");
  const sysOver = (await call("GET", "/admin/system", null, adminToken)).body;
  check("system status flags orders that pay out more than was charged", sysOver.attention?.some((a) => /more than the customer paid/.test(a)), sysOver.attention);
  // An old position gives no ride pay
  const stale = (await call("POST", "/orders", { storeId, deliveryAddress: "Kauppakatu 1, Helsinki", deliveryLat: 60.2, deliveryLng: 24.98, items: [{ productId, quantity: 1 }] }, otherCust.accessToken)).body.order;
  await payOrder(stale);
  await call("PATCH", `/orders/${stale.id}/status`, { status: "CONFIRMED" }, vendor.accessToken);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.2, longitude: 24.9 }, c1.accessToken);
  sql(`update "Courier" set "locationAt" = now() - interval '10 minutes' where "userId"=${c1.user.id}`);
  const staleAcc = await call("PATCH", `/orders/${stale.id}/assign-courier`, null, c1.accessToken);
  check("a courier whose position is old gets no ride-to-shop pay", staleAcc.status === 200 && sql(`select ("courierPay"->>'approachCents')::int || '|' || coalesce("courierPay"->>'approachKm', 'null') from "Order" where id=${stale.id}`) === "0|null", staleAcc.body);
  check("the customer's order view has no courier pay breakdown", !("courierPay" in ((await call("GET", `/orders/${stale.id}`, null, otherCust.accessToken)).body.order || { courierPay: 1 })) && !("courierPay" in ((await call("GET", `/orders/${stale.id}`, null, vendor.accessToken)).body.order || { courierPay: 1 })) && !!(await call("GET", "/orders/courier/mine", null, c1.accessToken)).body.orders?.find((o) => o.id === stale.id)?.courierPay);
  // Store ready 3 min after the courier checked in: waiting stops when the store marks it ready
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.1702, longitude: 24.9402 }, c1.accessToken);
  await call("POST", `/orders/${stale.id}/arrived-at-store`, null, c1.accessToken);
  await call("PATCH", `/orders/${stale.id}/status`, { status: "PROCESSING" }, vendor.accessToken);
  sql(`update "Order" set "acceptedAt" = now() - interval '60 minutes', "courierArrivedAt" = now() - interval '20 minutes', "readyAt" = now() - interval '11 minutes' where id=${stale.id}`);
  await call("PATCH", `/orders/${stale.id}/status`, { status: "SHIPPED" }, c1.accessToken);
  check("waiting counts only until the store marked the order ready (20 min at the shop, ready after 9 → 9 min)", sql(`select ("courierPay"->>'waitMinutes') || '|' || ("courierPay"->>'waitCents') from "Order" where id=${stale.id}`) === "9|80");
  await call("POST", `/orders/${stale.id}/deliver`, { method: "IN_PERSON" }, c1.accessToken);

  console.log("\n— Catalogue import: Shopify feed");
  let shopPrice = "49.90", shopStock = 3;
  const shopFeed = () => [
    {
      id: 1001, title: "Linen Dress", product_type: "Dresses", tags: "summer, linen",
      body_html: "<p>Soft <b>linen</b> &amp; cotton</p><script>alert(1)</script>",
      options: [{ name: "Koko", position: 1 }, { name: "Väri", position: 2 }],
      variants: [
        { id: 1, option1: "S", option2: "Musta", price: shopPrice, inventory_quantity: shopStock, barcode: "6412345678901" },
        { id: 2, option1: "M", option2: "Musta", price: (Number(shopPrice) + 3).toFixed(2), inventory_quantity: 0 },
      ],
      images: [{ src: "https://cdn.shopify.test/files/dress1.jpg?v=1", position: 1 }, { src: "//cdn.shopify.test/files/dress2.jpg", position: 2 }],
    },
    {
      id: 1002, title: "Leather Boots", product_type: "", tags: ["vintage"],
      variants: [{ id: 3, title: "Default Title", option1: "Default Title", price: "89.00", available: true }],
      images: [{ src: "https://cdn.shopify.test/files/boots.jpg", position: 1 }],
    },
    { id: 1003, title: "", variants: [{ id: 4, price: "5.00" }] },
    { id: 1004, title: "No photo bag", product_type: "Bags", variants: [{ id: 5, option1: "Default Title", price: "20", inventory_quantity: 2 }], images: [] },
  ];
  let shopCurrency = "EUR";
  const shopSrv = require("http").createServer((req, res) => {
    const u = new URL(req.url, "http://localhost");
    if (u.pathname === "/meta.json") { res.writeHead(200, { "Content-Type": "application/json" }); return res.end(JSON.stringify({ name: "Mock shop", currency: shopCurrency })); }
    if (u.pathname !== "/products.json") { res.writeHead(404); return res.end(); }
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ products: Number(u.searchParams.get("page") || 1) === 1 ? shopFeed() : [] }));
  });
  await new Promise((r) => shopSrv.listen(12223, r));
  const importer = await register("Ilona", "VENDOR");
  const impStore = (await call("POST", "/stores", { name: `Ilona Imports ${uniq}`, category: "APPAREL", sellerType: "PRIVATE", latitude: 60.17, longitude: 24.94 }, importer.accessToken)).body.store;
  await call("PATCH", `/admin/vendors/${impStore.id}/approve`, null, adminToken);
  const waitJob = async (id, tok = importer.accessToken) => {
    for (let i = 0; i < 120; i++) {
      const j = (await call("GET", `/products/import/${id}`, null, tok)).body?.job;
      if (j && (j.status === "DONE" || j.status === "FAILED")) return j;
      await sleep(250);
    }
    return null;
  };
  const ownList = async () => (await call("GET", `/stores/${impStore.id}/products?limit=50`, null, importer.accessToken)).body.products;
  const shopImport = (body, tok = importer.accessToken) => call("POST", "/products/import/shopify", body, tok);
  check("import needs the store's rights confirmation (literally true)", (await shopImport({ shopUrl: "http://localhost:12223" })).status === 400 && (await shopImport({ shopUrl: "http://localhost:12223", rightsConfirmed: "yes" })).status === 400);
  const unapprovedImport = await shopImport({ shopUrl: "http://localhost:12223", rightsConfirmed: true }, otherVendor.accessToken);
  check("a store that is not approved yet cannot import", unapprovedImport.status === 403, unapprovedImport.body);
  check("customers cannot import", (await shopImport({ shopUrl: "http://localhost:12223", rightsConfirmed: true }, otherCust.accessToken)).status === 403);
  const ssrf = [];
  for (const u of ["http://127.0.0.1:5432", "https://localhost", "https://169.254.169.254/latest/meta-data", "https://10.0.0.5", "https://[::1]", "https://shop.internal", "https://user:pw@example.com", "http://example.com", "https://example.com:8443", "localhost:4555", "file:///etc/passwd"]) {
    ssrf.push((await shopImport({ shopUrl: u, rightsConfirmed: true })).status);
  }
  check("internal addresses, IPs, ports, credentials and plain http are refused (SSRF guard)", ssrf.every((s) => s === 400), ssrf);
  const sj = await shopImport({ shopUrl: "http://localhost:12223/collections/all", rightsConfirmed: true });
  check("Shopify import starts in the background (202)", sj.status === 202 && sj.body.job?.status === "QUEUED" && sj.body.job.source === "SHOPIFY" && Array.isArray(sj.body.job.errors), sj.body);
  const job1 = await waitJob(sj.body.job?.id);
  check("the job finishes with counts: 4 found, 3 created, 1 skipped", job1?.status === "DONE" && job1.total === 4 && job1.created === 3 && job1.updated === 0 && job1.skipped === 1 && !!job1.finishedAt, job1);
  check("problems are listed per item: a missing name (error), missing stock levels (warning)", job1?.errors.some((e) => e.level === "error" && /name/i.test(e.message)) && job1.errors.some((e) => e.level === "warning" && /stock/i.test(e.message) && e.item === "Leather Boots"), job1?.errors);
  let own = await ownList();
  const dress = own.find((p) => p.externalId === "1001");
  const boots = own.find((p) => p.externalId === "1002");
  check("imported products are hidden drafts linked to the job", own.length === 3 && own.every((p) => p.isAvailable === false && p.importJobId === sj.body.job.id && p.externalSource === "SHOPIFY"), own.map((p) => [p.name, p.isAvailable]));
  check("Shopify mapping: name, plain-text description, category, price, size/colour options with price differences, GTIN", dress?.name === "Linen Dress" && dress.description === "Soft linen & cotton" && dress.category === "Clothing" && dress.salePriceCents === 4990 && dress.variants.length === 2 && dress.variants[0].size === "S" && dress.variants[0].color === "Musta" && dress.variants[1].priceAdjustCents === 300 && dress.variants[0].stock === 3 && dress.stockQuantity === 3 && dress.gtin === "6412345678901", dress);
  check("a vintage tag and no stock levels: Good condition, stock 1, category from the title", boots?.condition === "GOOD" && boots.isSecondHand === true && boots.stockQuantity === 1 && boots.category === "Shoes" && boots.variants.length === 0, boots);
  check("photos are copied into the store's own Cloudinary folder; products never hold remote URLs", own.every((p) => p.images.every((u) => u.startsWith(`https://res.cloudinary.com/testcloud/image/upload/c_limit,w_1200,q_auto,f_auto/malvoya/products/s${impStore.id}/imp-`))) && dress?.images.length === 2 && !JSON.stringify(own).includes("shopify.test"), own.map((p) => p.images));
  const uploads1 = await (await fetch("http://localhost:12222/__uploads")).json();
  check("the copies are signed server-side uploads of the shop's photo URLs", uploads1.some((u) => u.file === "https://cdn.shopify.test/files/dress1.jpg?v=1") && uploads1.some((u) => u.file === "https://cdn.shopify.test/files/dress2.jpg") && uploads1.every((u) => u.public_id.startsWith(`malvoya/products/s${impStore.id}/imp-`)), uploads1);
  check("imported prices start the 30-day price history", sql(`select count(*) from "PriceChange" where "productId"=${dress?.id}`) === "1");
  check("a draft cannot be opened by anyone but its store", (await call("GET", `/products/${dress?.id}`)).status === 404 && (await call("GET", `/products/${dress?.id}`, null, otherCust.accessToken)).status === 404 && (await call("GET", `/products/${dress?.id}`, null, importer.accessToken)).status === 200);
  check("drafts are not public", (await call("GET", `/stores/${impStore.id}/products`)).body.products.length === 0 && !(await call("GET", `/products/search?q=${encodeURIComponent("Linen Dress")}`)).body.products.some((p) => p.id === dress?.id));
  const pub1 = await call("POST", `/products/import/${sj.body.job.id}/publish`, null, importer.accessToken);
  const publicNow = (await call("GET", `/stores/${impStore.id}/products`)).body.products.map((p) => p.id).sort();
  check("publishing shows the drafts with a photo and a price, not the one without a photo", pub1.status === 200 && pub1.body.published === 2 && publicNow.join() === [dress?.id, boots?.id].sort().join(), [pub1.body, publicNow]);
  shopPrice = "44.90";
  shopStock = 5;
  const sj2 = await shopImport({ shopUrl: "http://localhost:12223", rightsConfirmed: true });
  const job2 = await waitJob(sj2.body.job?.id);
  own = await ownList();
  const dress2 = own.find((p) => p.externalId === "1001");
  check("re-importing updates price and stock instead of duplicating", job2?.status === "DONE" && job2.created === 0 && job2.updated === 3 && own.length === 3 && dress2?.salePriceCents === 4490 && dress2.variants.length === 2 && dress2.variants[0].stock === 5 && dress2.variants[0].id === dress?.variants[0].id, [job2, dress2]);
  check("the new price joins the price history; published products stay published", sql(`select count(*) from "PriceChange" where "productId"=${dress?.id}`) === "2" && dress2?.isAvailable === true);
  check("photos already copied are not uploaded again", (await (await fetch("http://localhost:12222/__uploads")).json()).length === uploads1.length && dress2?.images.join() === dress?.images.join());
  check("publishing the re-import changes nothing that is already public", (await call("POST", `/products/import/${sj2.body.job?.id}/publish`, null, importer.accessToken)).body.published === 0);
  check("the store deletes (hides) a published imported product", (await call("DELETE", `/products/${boots?.id}`, null, importer.accessToken)).status === 200);
  const sj3 = await shopImport({ shopUrl: "http://localhost:12223", rightsConfirmed: true });
  const job3 = await waitJob(sj3.body.job?.id);
  const pubAgain = await call("POST", `/products/import/${sj3.body.job?.id}/publish`, null, importer.accessToken);
  check("re-importing and publishing never brings back a product the store deleted", job3?.status === "DONE" && pubAgain.body.published === 0 && sql(`select "isAvailable" from "Product" where id=${boots?.id}`) === "f", [job3?.status, pubAgain.body]);
  shopCurrency = "SEK";
  const sjSek = await shopImport({ shopUrl: "http://localhost:12223", rightsConfirmed: true });
  const jobSek = await waitJob(sjSek.body.job?.id);
  check("a shop that prices in another currency is refused with a clear job error", jobSek?.status === "FAILED" && jobSek.errors.some((e) => /SEK/.test(e.message) && /euros/.test(e.message)) && jobSek.created === 0, jobSek);
  shopCurrency = "EUR";
  check("another store cannot see or publish the import", (await call("GET", `/products/import/${sj.body.job.id}`, null, vendor.accessToken)).status === 404 && (await call("POST", `/products/import/${sj.body.job.id}/publish`, null, vendor.accessToken)).status === 404);
  const impJobs = await call("GET", "/products/import", null, importer.accessToken);
  check("the store lists its recent imports, newest first", impJobs.status === 200 && impJobs.body.jobs?.length === 4 && impJobs.body.jobs[0].id === sjSek.body.job?.id && impJobs.body.jobs[3].id === sj.body.job?.id, impJobs.body);
  await new Promise((r) => shopSrv.close(r));

  console.log("\n— Catalogue import: CSV");
  const csvText = [
    "name;description;category;price;size;colour;stock;image_urls;condition;gtin;external_id",
    'Wool sweater;"Warm ""merino"" wool";Neuleet;59,90;S;Grey;2;https://img.example.com/a.jpg|https://img.example.com/b.jpg;new;;SW-1',
    "Wool sweater;Warm;Neuleet;62,90;M;Grey;1;;new;;SW-1",
    "Silk scarf;;Accessories;19.5;;;;https://img.example.com/s.jpg;LIKE_NEW;40123455;",
    "Bad price;;;abc;;;;;;;",
    "Broken condition;;;10;;;;;mint;;",
    "Cap;;Hats;15;;;;http://insecure.example.com/c.jpg;;;CAP-1",
  ].join("\r\n");
  const csvImport = (body, tok = importer.accessToken) => call("POST", "/products/import/csv", body, tok);
  check("CSV import needs the rights confirmation", (await csvImport({ csv: csvText })).status === 400);
  check("a CSV without a price column is refused", (await csvImport({ csv: "name;stock\nX;1", rightsConfirmed: true })).status === 400);
  check("a CSV over 1 MB is refused with 413", (await csvImport({ csv: "name,price\n" + "x".repeat(1_100_000), rightsConfirmed: true })).status === 413);
  const hugeCsv = await csvImport({ csv: "x".repeat(2_000_000), rightsConfirmed: true });
  check("a body over the route's own limit gets a readable 413; other routes keep 100 kB", hugeCsv.status === 413 && /1 MB/.test(hugeCsv.body?.error || "") && (await call("POST", "/support", { app: "customer", topic: "x", message: "y".repeat(200_000) }, otherCust.accessToken)).status === 413, hugeCsv.body);
  const cj = await csvImport({ csv: csvText, rightsConfirmed: true });
  check("CSV import starts (202)", cj.status === 202 && cj.body.job?.source === "CSV", cj.body);
  const cjob = await waitJob(cj.body.job?.id);
  check("CSV: rows with the same external_id become one product; bad rows are reported, not fatal", cjob?.status === "DONE" && cjob.total === 5 && cjob.created === 3 && cjob.skipped === 2 && cjob.errors.some((e) => e.item === "row 5" && /price/.test(e.message)) && cjob.errors.some((e) => e.item === "row 6" && /condition/.test(e.message)) && cjob.errors.some((e) => e.level === "warning" && /https/.test(e.message)), cjob);
  own = await ownList();
  const sweater = own.find((p) => p.externalId === "id:SW-1");
  const scarf = own.find((p) => p.name === "Silk scarf");
  const cap = own.find((p) => p.externalId === "id:CAP-1");
  check("CSV mapping: options with price differences, quoted text, comma decimals, category mapping", sweater?.salePriceCents === 5990 && sweater.variants.length === 2 && sweater.variants[1].priceAdjustCents === 300 && sweater.stockQuantity === 3 && sweater.description === 'Warm "merino" wool' && sweater.category === "Clothing" && sweater.images.length === 2 && sweater.isAvailable === false, sweater);
  check("CSV: dot decimals, condition and GTIN; an http photo is skipped", scarf?.salePriceCents === 1950 && scarf.condition === "LIKE_NEW" && scarf.gtin === "40123455" && scarf.category === "Accessories" && cap?.images.length === 0 && cap.category === "Accessories", [scarf, cap]);
  const cj2 = await csvImport({ csv: csvText, rightsConfirmed: true });
  const cjob2 = await waitJob(cj2.body.job?.id);
  check("re-importing the same CSV updates, never duplicates", cjob2?.created === 0 && cjob2.updated === 3 && (await ownList()).length === 6, cjob2);
  check("publishing the CSV import shows only the products with a photo", (await call("POST", `/products/import/${cj2.body.job?.id}/publish`, null, importer.accessToken)).body.published === 2);
  const cj3 = await csvImport({ csv: "name,price\nShirt,12,90\nCap,15\n", rightsConfirmed: true });
  const cjob3 = await waitJob(cj3.body.job?.id);
  check("a row with more cells than the header (unquoted 12,90) is reported with how to fix it", cjob3?.status === "DONE" && cjob3.created === 1 && cjob3.errors.some((e) => e.item === "row 2" && /quotes/.test(e.message)), cjob3);
  const imported = Number(sql(`select count(*) from "ImportJob" where "storeId"=${impStore.id} and "createdAt" > now() - interval '1 day'`));
  sql(`insert into "ImportJob" ("storeId","source","status","rightsConfirmedAt","updatedAt") select ${impStore.id}, 'CSV', 'DONE', now(), now() from generate_series(1, ${Math.max(0, 10 - imported)})`);
  const limited = await csvImport({ csv: "name,price\nX,1", rightsConfirmed: true });
  check("at most 10 imports per store per day (429)", limited.status === 429, limited.body);



  console.log("\n— Catalogue import: WooCommerce (read-only REST API keys)");
  const CK = `ck_${"a1".repeat(20)}`, CS = `cs_${"b2".repeat(20)}`;
  let wooCurrency = "EUR";
  const wooSeen = [];
  const wooProducts = [
    { id: 201, name: "Merino Cardigan", type: "variable", status: "publish", description: "<p>Soft <em>merino</em> wool</p>", categories: [{ name: "Knitwear" }], tags: [], images: [{ src: "https://cdn.woo.test/cardigan-1.jpg" }, { src: "https://cdn.woo.test/cardigan-2.jpg" }] },
    { id: 202, name: "Leather Belt", type: "simple", status: "publish", price: "35.00", regular_price: "35.00", stock_status: "instock", manage_stock: false, categories: [{ name: "Accessories" }], tags: [{ name: "Vintage" }], images: [{ src: "https://cdn.woo.test/belt.jpg" }] },
    { id: 203, name: "Gift set", type: "grouped", status: "publish", images: [] },
    { id: 204, name: "Mystery item", type: "simple", status: "publish", price: "", images: [] },
  ];
  const wooVariations = [
    { id: 1, price: "79.00", attributes: [{ name: "Size", option: "S" }, { name: "Colour", option: "Grey" }], manage_stock: true, stock_quantity: 2, global_unique_id: "6412345678901" },
    { id: 2, price: "85.00", attributes: [{ name: "pa_size", option: "M" }, { name: "Colour", option: "Grey" }], manage_stock: false, stock_status: "outofstock" },
  ];
  const wooSrv = require("http").createServer((req, res) => {
    const u = new URL(req.url, "http://localhost");
    wooSeen.push({ url: req.url, auth: req.headers.authorization || "", method: req.method });
    const json = (code, body) => { res.writeHead(code, { "Content-Type": "application/json" }); res.end(JSON.stringify(body)); };
    if (req.headers.authorization !== `Basic ${Buffer.from(`${CK}:${CS}`).toString("base64")}`) return json(401, { code: "woocommerce_rest_cannot_view" });
    if (u.pathname === "/wp-json/wc/v3/settings/general/woocommerce_currency") return json(200, { id: "woocommerce_currency", value: wooCurrency });
    if (u.pathname === "/wp-json/wc/v3/settings/tax/woocommerce_prices_include_tax") return json(200, { id: "woocommerce_prices_include_tax", value: "yes" });
    if (u.pathname === "/wp-json/wc/v3/products") return json(200, Number(u.searchParams.get("page") || 1) === 1 ? wooProducts : []);
    if (u.pathname === "/wp-json/wc/v3/products/201/variations") return json(200, wooVariations);
    json(404, { code: "rest_no_route" });
  });
  await new Promise((r) => wooSrv.listen(12223, r));
  const wilma = await register("Wilma", "VENDOR");
  const wStore = (await call("POST", "/stores", { name: `Wilma Woo ${uniq}`, category: "APPAREL", sellerType: "BUSINESS", businessId: "4567890-1", latitude: 60.17, longitude: 24.94 }, wilma.accessToken)).body.store;
  await call("PATCH", `/admin/vendors/${wStore.id}/approve`, null, adminToken);
  const wooImport = (body, tok = wilma.accessToken) => call("POST", "/products/import/woocommerce", body, tok);
  const wooBody = { siteUrl: "http://localhost:12223/shop", consumerKey: CK, consumerSecret: CS, rightsConfirmed: true };
  check("WooCommerce import validates the keys and the rights confirmation", (await wooImport({ ...wooBody, consumerKey: "nope" })).status === 400 && (await wooImport({ ...wooBody, consumerSecret: CK })).status === 400 && (await wooImport({ ...wooBody, rightsConfirmed: undefined })).status === 400 && (await wooImport({ ...wooBody, extra: 1 })).status === 400);
  check("WooCommerce import uses the same SSRF guard", (await wooImport({ ...wooBody, siteUrl: "https://127.0.0.1" })).status === 400 && (await wooImport({ ...wooBody, siteUrl: "http://example.com" })).status === 400);
  check("customers cannot import from WooCommerce", (await wooImport(wooBody, otherCust.accessToken)).status === 403);
  const wj = await wooImport(wooBody);
  check("WooCommerce import starts in the background (202)", wj.status === 202 && wj.body.job?.source === "WOOCOMMERCE" && wj.body.job.shopDomain === "localhost:12223", wj.body);
  const wjob = await waitJob(wj.body.job?.id, wilma.accessToken);
  check("WooCommerce job: 4 found, 2 created, grouped and unpriced products skipped with reasons", wjob?.status === "DONE" && wjob.total === 4 && wjob.created === 2 && wjob.skipped === 2 && wjob.errors.some((e) => e.item === "Gift set" && e.level === "error") && wjob.errors.some((e) => e.item === "Mystery item" && /price/i.test(e.message)), wjob);
  const wOwn = (await call("GET", `/stores/${wStore.id}/products?limit=50`, null, wilma.accessToken)).body.products;
  const cardigan = wOwn?.find((x) => x.externalId === "201");
  const belt = wOwn?.find((x) => x.externalId === "202");
  check("WooCommerce mapping: variations become size/colour options with price differences and stock, GTIN, plain-text description", cardigan?.name === "Merino Cardigan" && cardigan.externalSource === "WOOCOMMERCE" && cardigan.salePriceCents === 7900 && cardigan.description === "Soft merino wool" && cardigan.category === "Clothing" && cardigan.variants.length === 2 && cardigan.variants[0].size === "S" && cardigan.variants[0].color === "Grey" && cardigan.variants[0].stock === 2 && cardigan.variants[1].size === "M" && cardigan.variants[1].stock === 0 && cardigan.variants[1].priceAdjustCents === 600 && cardigan.gtin === "6412345678901" && cardigan.images.length === 2 && cardigan.isAvailable === false, cardigan);
  check("WooCommerce mapping: a simple vintage product, stock not tracked → 1 with a warning, photos re-hosted", belt?.salePriceCents === 3500 && belt.condition === "GOOD" && belt.stockQuantity === 1 && belt.category === "Accessories" && belt.images.every((u) => u.includes(`/malvoya/products/s${wStore.id}/imp-`)) && wjob.errors.some((e) => e.item === "Leather Belt" && /stock/.test(e.message)), belt);
  const keyLeak = wooSeen.some((r) => r.url.includes("ck_") || r.url.includes("cs_")) || wooSeen.some((r) => r.method !== "GET");
  check("the keys go only in the Authorization header of GET requests to the shop, never in a URL", wooSeen.length > 0 && !keyLeak && wooSeen.every((r) => r.url.startsWith("/wp-json/wc/v3/")), wooSeen.slice(0, 5));
  check("the keys are not stored anywhere", sql(`select count(*) from "ImportJob" where "errors"::text ~ '(ck|cs)_' or coalesce("sourceRef",'') ~ '(ck|cs)_'`) === "0" && !JSON.stringify(wj.body).includes(CS));
  check("publishing the WooCommerce import shows the products with a photo", (await call("POST", `/products/import/${wj.body.job.id}/publish`, null, wilma.accessToken)).body.published === 2);
  const wj2 = await wooImport(wooBody);
  const wjob2 = await waitJob(wj2.body.job?.id, wilma.accessToken);
  check("re-importing from WooCommerce updates instead of duplicating", wjob2?.status === "DONE" && wjob2.created === 0 && wjob2.updated === 2, wjob2);
  const wBad = await wooImport({ ...wooBody, consumerSecret: `cs_${"c3".repeat(20)}` });
  const wjBad = await waitJob(wBad.body.job?.id, wilma.accessToken);
  check("wrong keys fail the job with a clear message", wjBad?.status === "FAILED" && wjBad.errors.some((e) => /refused the API keys/.test(e.message)), wjBad);
  wooCurrency = "USD";
  const wUsd = await wooImport(wooBody);
  const wjUsd = await waitJob(wUsd.body.job?.id, wilma.accessToken);
  check("a WooCommerce shop that sells in another currency is refused", wjUsd?.status === "FAILED" && wjUsd.errors.some((e) => /USD/.test(e.message)) && wjUsd.created === 0, wjUsd);
  await new Promise((r) => wooSrv.close(r));

  console.log("\n— DAC7 seller data (tax info)");
  const stinaV = await register("Stina", "VENDOR");
  const stina = (await call("POST", "/stores", { name: `Stina <b>Studio</b> ${uniq}`, category: "APPAREL", sellerType: "BUSINESS", businessId: "3456789-0", latitude: 60.16, longitude: 24.93, address: "Bulevardi 3, Helsinki" }, stinaV.accessToken)).body.store;
  await call("PATCH", `/admin/vendors/${stina.id}/approve`, null, adminToken);
  const paulaV = await register("Paula", "VENDOR");
  const paula = (await call("POST", "/stores", { name: `Paula's wardrobe ${uniq}`, category: "THRIFT", sellerType: "PRIVATE", latitude: 60.19, longitude: 24.96 }, paulaV.accessToken)).body.store;
  const taxGet = (tok) => call("GET", "/stores/my/tax-info", null, tok);
  const taxPut = (body, tok) => call("PUT", "/stores/my/tax-info", body, tok);
  const t0 = await taxGet(stinaV.accessToken);
  check("a new store has no tax data yet and is told what is missing", t0.status === 200 && t0.body.taxInfo === null && t0.body.taxInfoComplete === false && t0.body.missing.includes("legalName") && t0.body.missing.includes("address") && !t0.body.missing.includes("businessId") && t0.body.canSaveTin === true, t0.body);
  check("/stores/my says the tax data is incomplete", (await call("GET", "/stores/my", null, stinaV.accessToken)).body.store?.taxInfoComplete === false);
  const sysTax = (await call("GET", "/admin/system", null, adminToken)).body;
  check("system status counts live stores missing tax data", sysTax.attention?.some((a) => /missing tax data \(DAC7\)/.test(a)) && sysTax.integrations?.dataEncryption?.configured === true, sysTax.attention);
  check("tax data is the store owner's (customers 403, no token 401)", (await taxGet(otherCust.accessToken)).status === 403 && (await call("GET", "/stores/my/tax-info")).status === 401);
  const stinaTax = { legalName: "+Stina Studio Oy", addressLine: "Bulevardi 3 A 5", postalCode: "00120", city: "Helsinki", country: "fi" };
  check("a Finnish postal code has 5 digits", (await taxPut({ ...stinaTax, postalCode: "120" }, stinaV.accessToken)).status === 400);
  const badVat = await taxPut({ ...stinaTax, vatNumber: "FI12345678" }, stinaV.accessToken);
  check("a Finnish VAT number must match the store's Y-tunnus", badVat.status === 400 && /FI34567890/.test(badVat.body.error || ""), badVat.body);
  check("unknown fields are refused", (await taxPut({ ...stinaTax, iban: "FI00" }, stinaV.accessToken)).status === 400);
  const t1 = await taxPut({ ...stinaTax, vatNumber: "fi 3456 7890" }, stinaV.accessToken);
  check("business seller saves legal name, VAT number and registered address; Y-tunnus comes from the store", t1.status === 200 && t1.body.taxInfoComplete === true && t1.body.taxInfo.vatNumber === "FI34567890" && t1.body.taxInfo.businessId === "3456789-0" && t1.body.taxInfo.country === "FI" && t1.body.taxInfo.dateOfBirth === null && t1.body.taxInfo.tinMasked === null, t1.body);
  check("/stores/my and the admin vendor list say the tax data is complete", (await call("GET", "/stores/my", null, stinaV.accessToken)).body.store?.taxInfoComplete === true && (await call("GET", "/admin/vendors", null, adminToken)).body.stores?.find((x) => x.id === stina.id)?.taxInfoComplete === true && !JSON.stringify((await call("GET", "/admin/vendors", null, adminToken)).body).includes("tinEncrypted"));
  const paulaTax = { legalName: "Paula Virtanen", dateOfBirth: "1952-10-13", addressLine: "Mannerheimintie 100 B 7", postalCode: "00250", city: "Helsinki" };
  const noTin = await taxPut(paulaTax, paulaV.accessToken);
  check("a private seller must give a tax ID", noTin.status === 400 && /tax identification/.test(noTin.body.error || ""), noTin.body);
  check("an invalid henkilötunnus is refused (check character)", (await taxPut({ ...paulaTax, tin: "131052-308A" }, paulaV.accessToken)).status === 400);
  check("the henkilötunnus must match the date of birth", /does not match/.test((await taxPut({ ...paulaTax, dateOfBirth: "1952-10-14", tin: "131052-308T" }, paulaV.accessToken)).body.error || ""));
  check("sellers must be adults", /18/.test((await taxPut({ ...paulaTax, dateOfBirth: "2015-01-01", tin: "131052-308T" }, paulaV.accessToken)).body.error || ""));
  const t2 = await taxPut({ ...paulaTax, tin: "131052-308t" }, paulaV.accessToken);
  check("private seller saves name, date of birth, tax ID and address; the tax ID comes back masked", t2.status === 200 && t2.body.taxInfoComplete === true && t2.body.taxInfo.tinMasked === "•••••-308T" && t2.body.taxInfo.dateOfBirth === "1952-10-13" && !JSON.stringify(t2.body).includes("131052"), t2.body);
  check("the tax ID is encrypted at rest (AES-256-GCM), never stored in clear", sql(`select "tinEncrypted" like 'v1:%' and "tinEncrypted" not like '%308T%' and "tinEncrypted" not like '%131052%' from "StoreTaxInfo" where "storeId"=${paula.id}`) === "t");
  const t3 = await taxPut({ ...paulaTax, city: "Espoo", postalCode: "02100" }, paulaV.accessToken);
  check("updating without re-entering the tax ID keeps the saved one", t3.status === 200 && t3.body.taxInfo.city === "Espoo" && t3.body.taxInfo.tinMasked === "•••••-308T", t3.body);
  // Paula's ciphertext copied onto Vera's store must not decrypt there (checked in the DAC7 report below)
  sql(`insert into "StoreTaxInfo" ("storeId","legalName","tinEncrypted","addressLine","postalCode","city","country","updatedAt") select ${storeId}, 'Vera Vintage Oy', "tinEncrypted", 'Mannerheimintie 1', '00100', 'Helsinki', 'FI', now() from "StoreTaxInfo" where "storeId"=${paula.id}`);

  console.log("\n— Monthly store statements");
  // Stina's month: A paid out, B with one of two items returned, D fully refunded; C was delivered 40 days ago
  const mkS = (vals) => Number(sql(`insert into "Order" ("userId","storeId","status","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","paymentStatus","paidAt","deliveredAt","refundedCents","discountCents","updatedAt") values (${otherCust.user.id},${stina.id},${vals}, now()) returning id`).split("\n")[0]);
  const sA = mkS(`'DELIVERED',10000,190,650,1000,9000,9690,'SUCCEEDED',now() - interval '5 minutes',now() - interval '3 minutes',0,500`);
  const sB = mkS(`'DELIVERED',4000,190,650,400,3600,4190,'SUCCEEDED',now() - interval '5 minutes',now() - interval '2 minutes',2000,0`);
  const sD = mkS(`'REFUNDED',3000,190,650,300,2700,3190,'REFUNDED',now() - interval '5 minutes',now() - interval '1 minute',3190,0`);
  const sC = mkS(`'DELIVERED',2000,190,650,200,1800,2190,'SUCCEEDED',now() - interval '41 days',now() - interval '40 days',0,0`);
  sql(`update "Order" set "userId"=${stinaV.user.id} where id=${sC}`); // another buyer (keeps the analytics cohorts simple)
  sql(`insert into "OrderItem" ("orderId","productId","quantity","unitCents") values (${sA},${productId},1,10000),(${sC},${productId},1,2000),(${sD},${productId},1,3000)`);
  const sBline = Number(sql(`insert into "OrderItem" ("orderId","productId","quantity","unitCents") values (${sB},${productId},2,2000) returning id`).split("\n")[0]);
  const sBret = Number(sql(`insert into "Return" ("orderId","userId","reason","status","refundCents","updatedAt") values (${sB},${otherCust.user.id},'CHANGED_MIND','REFUNDED',2000,now()) returning id`).split("\n")[0]);
  sql(`insert into "ReturnItem" ("returnId","orderItemId","quantity") values (${sBret},${sBline},1)`);
  sql(`insert into "Return" ("orderId","userId","reason","status","refundCents","updatedAt") values (${sD},${otherCust.user.id},'CHANGED_MIND','REFUNDED',3190,now())`);
  sql(`insert into "Payout" ("orderId","party","storeId","amountCents","status","releaseAt","paidAt","updatedAt") values (${sA},'STORE',${stina.id},9000,'PAID',now(),now(),now()),(${sB},'STORE',${stina.id},1800,'SCHEDULED',now() + interval '15 days',null,now()),(${sD},'STORE',${stina.id},0,'CANCELLED',now() + interval '15 days',null,now()),(${sC},'STORE',${stina.id},1800,'SCHEDULED',now(),null,now())`);
  const month = hel().date.slice(0, 7);
  const stm = await call("GET", `/stores/my/statements?month=${month}`, null, stinaV.accessToken);
  const rowOf = (id) => stm.body.orders?.find((o) => o.id === id);
  check("statement lists the month's delivered orders only, oldest first", stm.status === 200 && stm.body.month === month && stm.body.orders?.map((o) => o.id).join() === [sA, sB, sD].join(), stm.body);
  check("statement row: sales at full price (discount is Malvoya's), commission rate, payout and its status", rowOf(sA)?.itemsCents === 10000 && rowOf(sA).refundsCents === 0 && rowOf(sA).commissionRate === 0.1 && rowOf(sA).commissionCents === 1000 && rowOf(sA).payoutCents === 9000 && rowOf(sA).payoutStatus === "PAID" && !!rowOf(sA).deliveredAt, rowOf(sA));
  check("a partial return takes back the goods less their commission (refund claw-back)", rowOf(sB)?.refundsCents === 2000 && rowOf(sB).commissionCents === 200 && rowOf(sB).payoutCents === 1800 && rowOf(sB).payoutStatus === "SCHEDULED", rowOf(sB));
  check("a fully refunded order: everything back, no commission, no payout", rowOf(sD)?.refundsCents === 3000 && rowOf(sD).commissionCents === 0 && rowOf(sD).payoutCents === 0 && rowOf(sD).payoutStatus === "CANCELLED", rowOf(sD));
  const tt = stm.body.totals;
  check("statement totals: sales, refunds, commission, payouts sent and pending", tt?.salesCents === 17000 && tt.refundsCents === 5000 && tt.commissionCents === 1200 && tt.payoutsSentCents === 9000 && tt.payoutsPendingCents === 1800 && tt.salesCents - tt.refundsCents - tt.commissionCents === tt.payoutsSentCents + tt.payoutsPendingCents, tt);
  const admStm = await call("GET", `/admin/stores/${stina.id}/statements?month=${month}`, null, adminToken);
  check("admins get the same statement for any store", admStm.status === 200 && JSON.stringify(admStm.body.totals) === JSON.stringify(tt) && (await call("GET", `/admin/stores/999999/statements?month=${month}`, null, adminToken)).status === 404 && (await call("GET", `/admin/stores/${stina.id}/statements?month=${month}`, null, stinaV.accessToken)).status === 403);
  check("statements are per store and owner-only; the month is validated", (await call("GET", `/stores/my/statements?month=${month}`, null, paulaV.accessToken)).body.orders?.length === 0 && (await call("GET", `/stores/my/statements?month=${month}`, null, otherCust.accessToken)).status === 403 && (await call("GET", "/stores/my/statements?month=2026-13", null, stinaV.accessToken)).status === 400);
  const stRes = await fetch(`${API}/stores/my/statements/${month}.html`, { headers: { Authorization: `Bearer ${stinaV.accessToken}` } });
  const stHtml = await stRes.text();
  check("printable statement: titled 'not a VAT invoice', store name escaped, Y-tunnus, Malvoya's details as placeholders, no scripts", stRes.status === 200 && /text\/html/.test(stRes.headers.get("content-type") || "") && stHtml.includes("Statement — not a VAT invoice") && stHtml.includes("Stina &lt;b&gt;Studio&lt;/b&gt;") && !stHtml.includes("<b>Studio") && stHtml.includes("3456789-0") && stHtml.includes("+Stina Studio Oy") && stHtml.includes("[COMPANY LEGAL NAME]") && stHtml.includes(`#${sA}`) && !/<script/i.test(stHtml) && (stRes.headers.get("content-security-policy") || "").startsWith("default-src 'none'"), stHtml.slice(0, 400));
  check("the printable statement needs the owner's token", (await fetch(`${API}/stores/my/statements/${month}.html`)).status === 401 && (await fetch(`${API}/stores/my/statements/2026-1.html`, { headers: { Authorization: `Bearer ${stinaV.accessToken}` } })).status === 404);

  console.log("\n— DAC7 report (admin)");
  // Paula sold one item this year
  const pO = mkS(`'DELIVERED',2500,190,650,250,2250,2690,'SUCCEEDED',now() - interval '5 minutes',now() - interval '4 minutes',0,0`);
  sql(`update "Order" set "storeId"=${paula.id} where id=${pO}`);
  const year = Number(hel().date.slice(0, 4));
  const cInYear = sql(`select extract(year from (("deliveredAt" at time zone 'UTC') at time zone 'Europe/Helsinki'))::int from "Order" where id=${sC}`) === String(year);
  const d7 = await call("GET", `/admin/dac7?year=${year}`, null, adminToken);
  const dS = d7.body.sellers?.find((x) => x.storeId === stina.id);
  const dP = d7.body.sellers?.find((x) => x.storeId === paula.id);
  const q = `q${Math.floor((Number(hel().date.slice(5, 7)) - 1) / 3) + 1}`;
  check("DAC7: sales count excludes fully refunded orders; consideration is net of commission; fees per quarter", d7.status === 200 && dS?.sales === 2 + (cInYear ? 1 : 0) && dS.considerationCents.total === 10800 + (cInYear ? 1800 : 0) && dS.feesCents.total === 1200 + (cInYear ? 200 : 0) && dS.considerationCents[q] >= 10800 && dS.feesCents[q] >= 1200, dS);
  check("DAC7: business identity (legal name, Y-tunnus, VAT number, address)", dS?.identity?.legalName === "+Stina Studio Oy" && dS.identity.businessId === "3456789-0" && dS.identity.vatNumber === "FI34567890" && dS.identity.address?.postalCode === "00120" && dS.identity.tin === null && dS.taxInfoComplete === true, dS?.identity);
  check("DAC7: the private seller's tax ID is decrypted for the admin report only", dP?.identity?.tin === "131052-308T" && dP.identity.dateOfBirth === "1952-10-13" && dP.sales === 1 && dP.considerationCents.total === 2250 && dP.feesCents.total === 250, dP);
  check("DAC7: sellers under the de-minimis (< 30 sales and ≤ 2 000 €) are flagged exempt", dS?.exempt === true && dP?.exempt === true && d7.body.deMinimis?.salesBelow === 30 && d7.body.dueBy === `${year + 1}-01-31`);
  check("DAC7: live stores missing tax data are listed", d7.body.missingTaxData?.some((x) => x.storeId === impStore.id && x.missing.includes("tin")) && d7.body.missingTaxData.every((x) => Array.isArray(x.missing) && x.missing.length > 0) && !d7.body.missingTaxData.some((x) => x.storeId === stina.id), d7.body.missingTaxData);
  const dV = d7.body.sellers?.find((x) => x.storeId === storeId);
  check("DAC7: a tax-ID ciphertext copied to another store does not decrypt there", dV?.identity?.tin === null && dV.identity.tinUnreadable === true, dV?.identity);
  check("DAC7 report is admin-only; the year is validated", (await call("GET", `/admin/dac7?year=${year}`, null, stinaV.accessToken)).status === 403 && (await call("GET", "/admin/dac7?year=19x", null, adminToken)).status === 400);
  const csvRes = await fetch(`${API}/admin/dac7.csv?year=${year}`, { headers: { Authorization: `Bearer ${adminToken}` } });
  const csvBody = await csvRes.text();
  check("DAC7 CSV: header, one line per seller, cells that start a formula are neutralised", csvRes.status === 200 && /text\/csv/.test(csvRes.headers.get("content-type") || "") && /attachment; filename="malvoya-dac7-\d{4}\.csv"/.test(csvRes.headers.get("content-disposition") || "") && csvBody.includes("store_id,store_name,seller_type,legal_name") && csvBody.includes(",'+Stina Studio Oy,") && !csvBody.includes(",+Stina Studio Oy,") && csvBody.includes("131052-308T"), csvBody.slice(0, 600));
  check("DAC7 CSV is admin-only", (await fetch(`${API}/admin/dac7.csv?year=${year}`, { headers: { Authorization: `Bearer ${paulaV.accessToken}` } })).status === 403);

  console.log("\n— Fees switched on (second API instance with fee env vars, old courier pay rule, no Cloudinary)");
  const feeUp = await startFeeApi({ SERVICE_FEE_PERCENT: "5", SERVICE_FEE_MIN_CENTS: "49", SERVICE_FEE_MAX_CENTS: "300", SMALL_ORDER_THRESHOLD_CENTS: "6000", SMALL_ORDER_FEE_CENTS: "150", COURIER_PAY_MODE: "fee_share", CLOUDINARY_CLOUD_NAME: "", DATA_ENCRYPTION_KEY: "", DELIVERY_SLOTS: "00:00-23:59,25:00-26:00", SCHEDULED_DELIVERY_DISCOUNT_CENTS: "100" });
  check("API starts with fee settings", feeUp);
  const qF = (await quote({ ...quoteBody, tipCents: 0 }, otherCust.accessToken, FEE_API)).body.quote;
  check("service fee (5 %) and small-order fee are added below the threshold", qF?.serviceFeeCents === 250 && qF.smallOrderFeeCents === 150 && qF.smallOrderThresholdCents === 6000 && qF.totalCents === 5000 + fee + 250 + 150, qF);
  const oF = await order({ ...quoteBody, tipCents: 0 }, otherCust.accessToken, FEE_API);
  check("the order with fees charges exactly the quoted price; fees are Malvoya's, not the store's", oF.status === 201 && sameMoney(qF, oF.body.order) && oF.body.order.commissionCents === 500 && oF.body.order.sellerPayoutCents === 4500, oF.body);
  check("fee_share mode still works: the courier gets the delivery fee (plus tip), with a breakdown", oF.body.order?.courierFeeCents === fee && sql(`select ("courierPay"->>'mode') || '|' || ("courierPay"->>'baseCents') from "Order" where id=${oF.body.order?.id}`) === `fee_share|${fee}`, oF.body.order);
  const qF2 = (await quote({ ...quoteBody, tipCents: 0, items: [{ productId, quantity: 2 }] }, otherCust.accessToken, FEE_API)).body.quote;
  check("service fee is capped at its maximum; no small-order fee above the threshold", qF2?.serviceFeeCents === 300 && qF2.smallOrderFeeCents === 0, qF2);
  const qF3 = (await quote({ ...quoteBody, tipCents: 0, items: [{ productId: socks.id, quantity: 1 }] }, otherCust.accessToken, FEE_API)).body.quote;
  check("service fee has its minimum", qF3?.serviceFeeCents === 49 && qF3.smallOrderFeeCents === 150, qF3);
  const qF4 = (await quote({ ...quoteBody, promoCode: `TEN-${uniq}` }, otherCust.accessToken, FEE_API)).body.quote;
  check("fees, tip and promo together add up", qF4?.discountCents === 500 && qF4.totalCents === 5000 + fee + 250 + 150 + 150 - 500, qF4);
  const sysF = (await callAt(FEE_API, "GET", "/admin/system", null, adminToken)).body;
  check("system status shows the fee settings in use", sysF.pricing?.serviceFeePercent === 5 && sysF.pricing?.serviceFeeMaxCents === 300 && sysF.pricing?.smallOrderFeeCents === 150, sysF.pricing);
  check("paying an order with fees works (the webhook checks the exact amount)", (await payOrder(oF.body.order)).status === 200 && sql(`select "paymentStatus" from "Order" where id=${oF.body.order.id}`) === "SUCCEEDED");

  const fq = (await quote({ ...quoteBody, tipCents: 0 }, otherCust.accessToken, FEE_API)).body.quote;
  check("DELIVERY_SLOTS and the scheduled-delivery discount: slots from the env, discount off the delivery fee", fq?.slots?.map((x) => `${x.date} ${x.start}-${x.end}`).join() === `${tmr.date} 00:00-23:59` && fq.slots[0].feeCents === fee - 100 && fq.deliveryFeeCents === fee, fq?.slots);
  const fo = await order({ ...quoteBody, tipCents: 0, deliverySlot: { date: tmr.date, start: "00:00", end: "23:59" } }, otherCust.accessToken, FEE_API);
  check("a scheduled order pays the discounted delivery fee; courier pay is unchanged (Malvoya pays the discount)", fo.status === 201 && fo.body.order.deliveryFeeCents === fee - 100 && fo.body.order.courierFeeCents === fee && fo.body.order.totalCents === 5000 + fee - 100 + 250 + 150, fo.body.order);
  check("a slot that has already started is refused (409)", (await order({ ...quoteBody, deliverySlot: { date: hel().date, start: "00:00", end: "23:59" } }, otherCust.accessToken, FEE_API)).status === 409);
  const noKeyGet = (await callAt(FEE_API, "GET", "/stores/my/tax-info", null, paulaV.accessToken)).body;
  check("without DATA_ENCRYPTION_KEY the app is told tax IDs cannot be saved, and the saved one is not readable", noKeyGet.canSaveTin === false && noKeyGet.taxInfo?.tinMasked === "•••••" && noKeyGet.taxInfoComplete === true, noKeyGet);
  const noKeyPut = await callAt(FEE_API, "PUT", "/stores/my/tax-info", { ...paulaTax, tin: "131052-308T" }, paulaV.accessToken);
  check("without DATA_ENCRYPTION_KEY saving a tax ID is refused with a clear 503", noKeyPut.status === 503 && /secure storage is not set up/.test(noKeyPut.body.error || ""), noKeyPut.body);
  check("...other details can still be updated (the saved tax ID is kept)", (await callAt(FEE_API, "PUT", "/stores/my/tax-info", paulaTax, paulaV.accessToken)).status === 200 && sql(`select "tinEncrypted" like 'v1:%' from "StoreTaxInfo" where "storeId"=${paula.id}`) === "t");
  const sysNoKey = (await callAt(FEE_API, "GET", "/admin/system", null, adminToken)).body;
  check("system status says the encryption key is missing", sysNoKey.integrations?.dataEncryption?.configured === false && sysNoKey.attention?.some((a) => /DATA_ENCRYPTION_KEY/.test(a)) && sysNoKey.scheduledDelivery?.discountCents === 100 && sysNoKey.scheduledDelivery?.slots?.length === 1, [sysNoKey.integrations?.dataEncryption, sysNoKey.scheduledDelivery]);
  const noMedia = await callAt(FEE_API, "POST", "/products/import/csv", { csv: csvText, rightsConfirmed: true }, importer.accessToken);
  check("without Cloudinary the import is switched off (503), like uploads", noMedia.status === 503 && (await callAt(FEE_API, "POST", "/products/import/shopify", { shopUrl: "http://localhost:12223", rightsConfirmed: true }, importer.accessToken)).status === 503 && (await callAt(FEE_API, "POST", "/products/import/woocommerce", { siteUrl: "http://localhost:12223", consumerKey: `ck_${"a1".repeat(20)}`, consumerSecret: `cs_${"b2".repeat(20)}`, rightsConfirmed: true }, importer.accessToken)).status === 503, noMedia.body);
  feeApi.kill();
  feeApi = null;

  const rev = (await call("GET", "/admin/stats", null, adminToken)).body.stats;
  check("admin stats show Malvoya's revenue", rev.serviceFeeCents >= 250 && rev.smallOrderFeeCents >= 150 && rev.discountCents >= 200 && rev.commissionCents > 0 && rev.netPlatformRevenueCents === rev.commissionCents + rev.serviceFeeCents + rev.smallOrderFeeCents + rev.deliveryMarginCents - rev.discountCents, rev);
  const marginSql = Number(sql(`select coalesce(sum("deliveryFeeCents" - ("courierFeeCents" - "tipCents")), 0) from "Order" where "paymentStatus" = 'SUCCEEDED' and status <> 'CANCELLED'`));
  check("delivery margin = delivery fees − courier pay without tips (may be negative)", rev.deliveryMarginCents === marginSql, [rev.deliveryMarginCents, marginSql]);

  console.log("\n— Per-store commission (admin)");
  const setRate = (rate, tok = adminToken) => call("PATCH", `/admin/vendors/${storeId}/commission`, { commissionRate: rate }, tok);
  check("only admins change commission", (await setRate(0.15, otherCust.accessToken)).status === 403 && (await setRate(0.15, vendor.accessToken)).status === 403 && (await call("PATCH", `/admin/vendors/${storeId}/commission`, { commissionRate: 0.15 })).status === 401);
  check("commission must be 0–50 % with at most two decimals", (await setRate(0.6)).status === 400 && (await setRate(-0.1)).status === 400 && (await setRate(0.125)).status === 400 && (await setRate("0.15")).status === 400);
  check("unknown store is 404", (await call("PATCH", "/admin/vendors/999999/commission", { commissionRate: 0.1 }, adminToken)).status === 404);
  const oldCommission = sql(`select "commissionCents" from "Order" where id=${o0.body.order.id}`);
  const rateRes = await setRate(0.15);
  check("admin sets a store's commission to 15 %; the change is logged with who and the old value", rateRes.status === 200 && rateRes.body.store?.commissionRate === 0.15 && rateRes.body.change?.adminId === adminUser.user.id && rateRes.body.change?.oldValue?.commissionRate === 0.1 && rateRes.body.change?.newValue?.commissionRate === 0.15, rateRes.body);
  const listedRate = (await call("GET", "/admin/vendors", null, adminToken)).body.stores?.find((s) => s.id === storeId)?.commissionRate;
  const hist = await call("GET", `/admin/vendors/${storeId}/commission-history`, null, adminToken);
  check("the vendor list shows the rate; the history names the admin", listedRate === 0.15 && hist.body.history?.[0]?.admin?.email === `admin${uniq}@example.fi`, [listedRate, hist.body]);
  const newRateOrder = (await order({ ...quoteBody, tipCents: 0 }, otherCust.accessToken)).body.order;
  check("new orders use the new rate; existing orders keep theirs", newRateOrder?.commissionCents === 750 && newRateOrder.sellerPayoutCents === 4250 && sql(`select "commissionCents" from "Order" where id=${o0.body.order.id}`) === oldCommission && oldCommission === "500", [newRateOrder, oldCommission]);
  await setRate(0.1);

  console.log("\n— Referrals (off by default; on in a second API instance)");
  const refOff = await call("GET", "/me/referral", null, otherCust.accessToken);
  const myCode = refOff.body.code;
  check("every customer gets an invite code and link, but invites are off by default", refOff.status === 200 && refOff.body.enabled === false && refOff.body.discountCents === 0 && refOff.body.rewardCents === 0 && /^[A-HJKMNP-Z2-9]{8}$/.test(myCode || "") && refOff.body.shareUrl === `${BASE}/r/${myCode}` && refOff.body.invited === 0 && typeof refOff.body.terms?.fi === "string", refOff.body);
  check("the code stays the same", (await call("GET", "/me/referral", null, otherCust.accessToken)).body.code === myCode);
  check("invite codes are for customers", (await call("GET", "/me/referral", null, vendor.accessToken)).status === 403 && (await call("GET", "/me/referral")).status === 401);
  const newbie = await register("Noora");
  const offQuote = (await quote({ ...quoteBody, promoCode: myCode }, newbie.accessToken)).body.quote;
  check("while invites are off an invite code gives nothing", offQuote?.discountCents === 0 && /not valid/.test(offQuote.promoError || ""), offQuote);
  const offPage = await fetch(`${BASE}/r/${myCode}`);
  check("while invites are off the invite page says it is not valid", offPage.status === 404 && /no longer valid/.test(await offPage.text()));
  check("a promo code cannot take a customer's invite code", (await mkPromo({ code: myCode, description: "shadow", kind: "AMOUNT", value: 100 })).status === 409);

  const refUp = await startFeeApi({ REFERRAL_DISCOUNT_CENTS: "500", REFERRAL_REWARD_CENTS: "300", ANDROID_APP_SHA256: `${"ab:".repeat(31)}cd, ${"12:".repeat(31)}EF, not-a-fingerprint` });
  check("API starts with invites switched on", refUp);
  const refOn = (await callAt(FEE_API, "GET", "/me/referral", null, otherCust.accessToken)).body;
  check("with invites on: same code, 5 € for the friend, 3 € reward, honest terms", refOn.enabled === true && refOn.code === myCode && refOn.discountCents === 500 && refOn.rewardCents === 300 && refOn.shareUrl === `${FEE_BASE}/r/${myCode}` && refOn.terms?.en.includes("5.00 €") && refOn.terms.en.includes("3.00 €") && refOn.terms.fi.includes("5,00"), refOn);
  const selfQ = (await quote({ ...quoteBody, promoCode: myCode }, otherCust.accessToken, FEE_API)).body.quote;
  check("you cannot use your own invite code", selfQ?.discountCents === 0 && /own invite/.test(selfQ.promoError || "") && (await order({ ...quoteBody, promoCode: myCode }, otherCust.accessToken, FEE_API)).status === 409, selfQ);
  check("an existing customer cannot use an invite code", /first order/.test((await quote({ ...quoteBody, promoCode: myCode }, pirjo.accessToken, FEE_API)).body.quote?.promoError || ""));
  const inviteQ = (await quote({ storeId, fulfilment: "PICKUP", items: [{ productId, quantity: 1 }], promoCode: myCode.toLowerCase() }, newbie.accessToken, FEE_API)).body.quote;
  check("a new customer gets 5 € off with the invite code", inviteQ?.discountCents === 500 && inviteQ.totalCents === 4500 && inviteQ.promo?.code === myCode && inviteQ.promoError === null, inviteQ);
  const inviteO = await order({ storeId, fulfilment: "PICKUP", items: [{ productId, quantity: 1 }], promoCode: myCode }, newbie.accessToken, FEE_API);
  const io = inviteO.body.order;
  check("the order charges the quoted price; Malvoya pays the discount; who invited is not in the payload", inviteO.status === 201 && io.discountCents === 500 && io.totalCents === 4500 && io.commissionCents === 500 && io.sellerPayoutCents === 4500 && io.promoCodeId === null && !("referrerId" in io), inviteO.body);
  check("nothing is recorded before payment", sql(`select count(*) from "Referral" where "refereeId"=${newbie.user.id}`) === "0");
  await payNow(io, FEE_API);
  check("payment records one referral", sql(`select count(*) || '|' || max("referrerId") from "Referral" where "refereeId"=${newbie.user.id}`) === `1|${otherCust.user.id}`);
  const invitePage = await fetch(`${FEE_BASE}/r/${myCode.toLowerCase()}`);
  const invHtml = await invitePage.text();
  check("the invite page explains the offer and shows the code", invitePage.status === 200 && invHtml.includes("5,00 €") && invHtml.includes(myCode) && !/<script/i.test(invHtml) && /img-src https:\/\/res\.cloudinary\.com/.test(invitePage.headers.get("content-security-policy") || ""), invHtml.slice(0, 300));
  const badInvite = await fetch(`${FEE_BASE}/r/${encodeURIComponent("<script>alert(1)</script>")}`);
  check("an unknown invite code shows 'no longer valid' and echoes nothing", badInvite.status === 404 && !/<script/i.test(await badInvite.text()));
  await callAt(FEE_API, "PATCH", `/orders/${io.id}/status`, { status: "CONFIRMED" }, vendor.accessToken);
  await callAt(FEE_API, "PATCH", `/orders/${io.id}/status`, { status: "PROCESSING" }, vendor.accessToken);
  const ioCode = sql(`select "pickupCode" from "Order" where id=${io.id}`);
  const ioDone = await callAt(FEE_API, "POST", `/orders/${io.id}/collect`, { code: ioCode }, vendor.accessToken);
  await sleep(800);
  const reward = sql(`select p.code || '|' || p.value || '|' || p."maxRedemptions" || '|' || p."perUserLimit" || '|' || p."userId" || '|' || (r."rewardedAt" is not null) from "Referral" r join "PromoCode" p on p.id = r."rewardPromoCodeId" where r."orderId"=${io.id}`);
  const rewardCode = reward.split("|")[0];
  check("when the friend's first order is collected, the referrer gets a personal one-time 3 € code", ioDone.status === 200 && /^KIITOS-[A-HJKMNP-Z2-9]{6}\|300\|1\|1\|/.test(reward) && reward.endsWith(`|${otherCust.user.id}|true`), reward);
  const refAfter = (await callAt(FEE_API, "GET", "/me/referral", null, otherCust.accessToken)).body;
  check("the referrer sees one invited friend and one reward", refAfter.invited === 1 && refAfter.rewarded === 1, refAfter);
  check("only the referrer can use the reward code", /not valid/.test((await quote({ ...quoteBody, promoCode: rewardCode }, pirjo.accessToken)).body.quote?.promoError || "") && (await quote({ ...quoteBody, promoCode: rewardCode }, otherCust.accessToken)).body.quote?.discountCents === 300);
  check("one invite per new customer: the friend cannot use another invite", /first order/.test((await quote({ ...quoteBody, promoCode: myCode }, newbie.accessToken, FEE_API)).body.quote?.promoError || ""));
  const sysRef = (await callAt(FEE_API, "GET", "/admin/system", null, adminToken)).body;
  check("system status shows referral settings and counts", sysRef.referrals?.enabled === true && sysRef.referrals.discountCents === 500 && sysRef.referrals.rewardCents === 300 && sysRef.referrals.referrals >= 1 && sysRef.referrals.rewarded >= 1 && sysRef.referrals.discountGivenCents >= 500 && sysRef.appLinks?.fingerprints === 2 && sysRef.pickup?.holdHours === 72, sysRef.referrals);
  const links = await fetch(`${FEE_BASE}/.well-known/assetlinks.json`);
  const linksJson = await links.json();
  check("assetlinks.json lists the customer app with its valid fingerprints (upper case)", links.status === 200 && /application\/json/.test(links.headers.get("content-type") || "") && linksJson.length === 1 && linksJson[0].relation[0] === "delegate_permission/common.handle_all_urls" && linksJson[0].target.namespace === "android_app" && linksJson[0].target.package_name === "com.malvoya.customer" && linksJson[0].target.sha256_cert_fingerprints.join() === [`${"AB:".repeat(31)}CD`, `${"12:".repeat(31)}EF`].join(), linksJson);
  feeApi.kill();
  feeApi = null;
  const sysRefOff = (await call("GET", "/admin/system", null, adminToken)).body;
  check("system status: invites off by default, pickup timers listed", sysRefOff.referrals?.enabled === false && sysRefOff.pickup?.reminderHours === 24 && sysRefOff.pickup?.holdHours === 72 && sysRefOff.appLinks?.fingerprints === 0, [sysRefOff.referrals, sysRefOff.pickup]);
  const noLinks = await fetch(`${BASE}/.well-known/assetlinks.json`);
  check("without ANDROID_APP_SHA256 assetlinks.json is an empty list", noLinks.status === 200 && JSON.stringify(await noLinks.json()) === "[]");

  console.log("\n— Store share page");
  const evilProd = await call("POST", "/products", { name: "Tee <script>alert(1)</script>", category: "Shirt", salePriceCents: 2500, images: [ownImage(storeId, "tee")] }, vendor.accessToken);
  const sPageRes = await fetch(`${BASE}/s/${storeId}`);
  const sHtml = await sPageRes.text();
  check("store share page: name, products with prices, open-in-app and Play links, everything escaped", evilProd.status === 201 && sPageRes.status === 200 && sHtml.includes(`Vera Vintage ${uniq}`) && sHtml.includes("Tee &lt;script&gt;alert(1)&lt;/script&gt;") && !/<script/i.test(sHtml) && sHtml.includes("25,00 €") && sHtml.includes("intent://") && sHtml.includes("package=com.malvoya.customer") && sHtml.includes("play.google.com/store/apps/details?id=com.malvoya.customer"), sHtml.slice(0, 400));
  check("store share page allows only Cloudinary images and no scripts", (sPageRes.headers.get("content-security-policy") || "").startsWith("default-src 'none'; img-src https://res.cloudinary.com"));
  check("unknown or unapproved stores have no share page", (await fetch(`${BASE}/s/999999`)).status === 404 && (await fetch(`${BASE}/s/abc`)).status === 404 && (await fetch(`${BASE}/s/${privSeller.body.store.id}`)).status === 404);

  console.log("\n— Launch alerts and system status");
  check("launch alert needs a location", (await call("PUT", "/me/launch-alert", { area: "Tampere" }, otherCust.accessToken)).status === 400);
  check("launch alert needs a signed-in user", (await call("PUT", "/me/launch-alert", { latitude: 61.4978, longitude: 23.761 })).status === 401);
  const wait = await call("PUT", "/me/launch-alert", { latitude: 61.4978, longitude: 23.761, area: "Tampere keskusta" }, otherCust.accessToken);
  check("customer asks to hear when Malvoya opens near them", wait.status === 200 && (await call("GET", "/me/launch-alert", null, otherCust.accessToken)).body.alert?.area === "Tampere keskusta", wait.body);
  const demand = await call("GET", "/admin/launch-demand", null, adminToken);
  check("admin sees where people are waiting", demand.status === 200 && demand.body.demand.some((d) => d.areas.includes("Tampere keskusta")), demand.body);
  const tampereVendor = await register("Tuula", "VENDOR");
  const farStore = await call("POST", "/stores", { name: `Tampere Thrift ${uniq}`, category: "THRIFT", sellerType: "PRIVATE", latitude: 61.5, longitude: 23.77 }, tampereVendor.accessToken);
  const goLive = await call("PATCH", `/admin/vendors/${farStore.body.store.id}/approve`, null, adminToken);
  check("approving a store nearby notifies the people waiting, once", goLive.status === 200 && goLive.body.launchAlertsSent === 1 && (await call("PATCH", `/admin/vendors/${farStore.body.store.id}/approve`, null, adminToken)).body.launchAlertsSent === 0, goLive.body);
  check("a store far away notifies nobody", (await call("PATCH", `/admin/vendors/${storeId}/approve`, null, adminToken)).body.launchAlertsSent === 0);
  const status = await call("GET", "/admin/system", null, adminToken);
  check("system status says what is switched on, without secrets", status.status === 200 && status.body.integrations?.payments?.mode === "test" && status.body.marketplace?.liveStores >= 2 && !JSON.stringify(status.body).includes("sk_test_123") && !JSON.stringify(status.body).includes("cld_test_secret"), status.body);
  check("system status lists the background jobs", status.body.backgroundJobs?.some((j) => j.name === "order-watchdog" && j.lastRunAt), status.body.backgroundJobs);
  check("system status is admin-only", (await call("GET", "/admin/system", null, otherCust.accessToken)).status === 403);
  check("leaving the waitlist works", (await call("DELETE", "/me/launch-alert", null, otherCust.accessToken)).status === 200 && (await call("GET", "/me/launch-alert", null, otherCust.accessToken)).body.alert === null);


  console.log("\n— Analytics (admin)");
  const an = await call("GET", "/admin/analytics", null, adminToken);
  const at = an.body.totals;
  const rangeSql = `"paidAt" >= ((date_trunc('day', now() at time zone 'Europe/Helsinki') - interval '27 days') at time zone 'Europe/Helsinki') at time zone 'UTC'`;
  check("analytics: last 28 Finnish days by default, one row per day", an.status === 200 && an.body.range?.days === 28 && an.body.daily?.length === 28 && an.body.range.to === hel().date && an.body.daily[27].date === hel().date, an.body.range);
  check("analytics: orders paid and GMV match the orders", at?.ordersPaid === Number(sql(`select count(*) from "Order" where ${rangeSql}`)) && at.gmvCents === Number(sql(`select coalesce(sum("subtotalCents"),0) from "Order" where ${rangeSql}`)) && at.ordersPaid === an.body.daily.reduce((t, d) => t + d.ordersPaid, 0), [at?.ordersPaid, at?.gmvCents]);
  check("analytics: cancellations by reason", at?.cancelledByReason?.store_timeout >= 1 && at.cancelledByReason.no_courier >= 2 && at.cancelledByReason.customer >= 1 && at.cancelledByReason.pickup_not_collected >= 1 && at.cancelledByReason.store_not_ready >= 1 && at.cancelled === Object.values(at.cancelledByReason).reduce((a, b) => a + b, 0), at?.cancelledByReason);
  const netSql = Number(sql(`select coalesce(sum("commissionCents" + "serviceFeeCents" + "smallOrderFeeCents" + "deliveryFeeCents" - ("courierFeeCents" - "tipCents") - "discountCents"),0) from "Order" where "paymentStatus"='SUCCEEDED' and status <> 'CANCELLED' and ${rangeSql}`));
  check("analytics: net platform revenue uses the admin-stats rule", at?.revenue?.netPlatformRevenueCents === netSql && at.revenue.netPlatformRevenueCents === an.body.daily.reduce((t, d) => t + d.netRevenueCents, 0), [at?.revenue, netSql]);
  check("analytics: store acceptance rate and median time to accept", at?.storeAcceptance?.accepted >= 1 && at.storeAcceptance.timedOut >= 1 && at.storeAcceptance.rate > 0 && at.storeAcceptance.rate < 1 && typeof at.storeAcceptance.medianSecondsToAccept === "number", at?.storeAcceptance);
  check("analytics: on-time deliveries, median delivery time, returns and refunds", at?.onTimeDelivery?.measured >= 1 && at.onTimeDelivery.onTime >= 1 && at.onTimeDelivery.rate <= 1 && typeof at.medianDeliveryMinutes === "number" && at.returns?.ordersWithReturn >= 2 && at.returns.orderRate > 0 && at.returns.itemRate > 0 && at.refunds?.refundedCents > 0, [at?.onTimeDelivery, at?.medianDeliveryMinutes, at?.returns, at?.refunds]);
  check("analytics: new customers, repeat customers within 30 days and the waiting list", at?.customers?.newCustomers >= 1 && at.customers.repeatWithin30Days?.cohort >= 1 && at.customers.repeatWithin30Days.repeaters >= 1 && typeof at.waitlist === "number" && at.customers.signups >= 1, at?.customers);
  const anDay = await call("GET", `/admin/analytics?from=${hel().date}&to=${hel().date}`, null, adminToken);
  check("analytics: a custom range", anDay.status === 200 && anDay.body.daily?.length === 1 && anDay.body.range.from === hel().date);
  check("analytics: bad ranges are refused; admin only", (await call("GET", "/admin/analytics?from=2026-10-10&to=2026-10-01", null, adminToken)).status === 400 && (await call("GET", "/admin/analytics?from=2026-13-01", null, adminToken)).status === 400 && (await call("GET", "/admin/analytics?from=2020-01-01&to=2026-01-01", null, adminToken)).status === 400 && (await call("GET", "/admin/analytics", null, otherCust.accessToken)).status === 403);

  console.log("\n— Background jobs and input hardening");
  const leaseSql = `INSERT INTO "JobLease" ("name","lockedUntil") VALUES ('t${uniq}', now() + interval '1 minute') ON CONFLICT ("name") DO UPDATE SET "lockedUntil" = now() + interval '1 minute' WHERE "JobLease"."lockedUntil" < now() RETURNING "name"`;
  const firstLine = (q) => sql(q).split(/\r?\n/)[0];
  check("job lease: first instance wins, second waits", firstLine(leaseSql) === `t${uniq}` && firstLine(leaseSql) === "INSERT 0 0");
  const bad = await fetch(`${API}/auth/login`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{not json" });
  check("malformed JSON → 400, not 500", bad.status === 400);
  check("non-numeric ids → 404", (await call("GET", "/drops/abc")).status === 404 && (await call("GET", "/orders/abc", null, otherCust.accessToken)).status === 404);
  check("huge search input rejected", (await call("GET", `/products/search?q=${"a".repeat(200)}`)).status === 400);
  const cors = await fetch(`${API}/stores`, { headers: { Origin: "https://evil.example" } });
  check("CORS does not allow unknown origins", !cors.headers.get("access-control-allow-origin"));
  check("health reports v2.9.0", (await (await fetch(`${BASE}/health`)).json()).version === "2.9.0");

  [vendorSock, custSock, otherSock, c1Sock, c2Sock].forEach((s) => s.close());
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
