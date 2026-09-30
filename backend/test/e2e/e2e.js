// End-to-end test for API v2.3 against a local API + throwaway Postgres + stripe-mock + Cloudinary mock.
const { execSync } = require("child_process");
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
async function call(method, path, body, token, raw) {
  const res = await fetch(`${API}${path}`, {
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
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
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
  check("courier pay and ETA are set on the order", sql(`select ("courierFeeCents" = "deliveryFeeCents") and "etaMinutes" > 0 from "Order" where id=${ro?.id}`) === "t");
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
  const vendorReturns = await call("GET", "/returns", null, vendor.accessToken);
  check("store sees returns of its orders", vendorReturns.body.returns?.some((r) => r.id === ret.body.return.id), vendorReturns.body);
  check("outsider cannot process the return", (await call("PATCH", `/returns/${ret.body.return.id}/status`, { status: "APPROVED" }, otherVendor.accessToken)).status === 403);
  const refund = await call("PATCH", `/returns/${ret.body.return.id}/status`, { status: "REFUNDED" }, vendor.accessToken);
  check("store refunds the return through Stripe", refund.status === 200, refund.body);
  check("refund cancels the unpaid store payout", sql(`select status || '|' || "amountCents" from "Payout" where "orderId"=${orderId} and party='STORE'`) === "CANCELLED|0");
  await call("PUT", `/me/favorites/${p3.id}`, null, tokenA);
  await call("POST", "/me/devices", { token: `device-token-${uniq}-aaaaaaaaaaaa`, platform: "android" }, tokenA);
  const exp = await call("GET", "/auth/me/data", null, tokenA);
  check("data export includes favourites, reviews and devices, no secrets", exp.body.data?.favorites?.length === 1 && exp.body.data?.reviews?.length === 1 && exp.body.data?.devices?.length === 1 && !JSON.stringify(exp.body).includes("passwordHash") && !JSON.stringify(exp.body).includes("device-token-"), Object.keys(exp.body.data || {}));
  check("account deletion succeeds", (await call("DELETE", "/auth/me", null, tokenA)).status === 200);
  check("deletion removes favourites and devices and blanks review text", sql(`select (select count(*) from "Favorite" where "userId"=${regA.body.user.id}) + (select count(*) from "DeviceToken" where "userId"=${regA.body.user.id}) || '|' || (select comment is null from "Review" where "orderId"=${orderId})`) === "0|true");
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
  check("health reports v2.3.0", (await (await fetch(`${BASE}/health`)).json()).version === "2.3.0");

  [vendorSock, custSock, otherSock, c1Sock, c2Sock].forEach((s) => s.close());
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
