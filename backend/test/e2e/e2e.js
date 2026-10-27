// End-to-end test for API v2.13 against a local API + throwaway Postgres + stripe-mock + Cloudinary mock.
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
    // ADMIN_MFA_REQUIRED=false: some runs use NODE_ENV=production, where admins would otherwise need two-step sign-in first
    env: { ...process.env, ...testEnv, PORT: "4556", PUBLIC_API_URL: FEE_BASE, DISABLE_SCHEDULER: "true", ADMIN_MFA_REQUIRED: "false", ...extraEnv },
    stdio: "ignore",
  });
  // Up to 90 s: a cold start on a busy machine can take over 20 s
  for (let i = 0; i < 180; i++) {
    try { if ((await fetch(`${FEE_BASE}/health`)).ok) return true; } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  return false;
}
process.on("exit", () => { if (feeApi) feeApi.kill(); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// PRH/YTJ open data mock (2.11): the API's business-ID lookup goes here (PRH_API_TEST_HOST=localhost:12224), never to
// the real register. Fixture companies are made up for the test ("Testi …") and exist only in this mock.
const prhRequests = [];
const prhFixtures = {
  "7654321-2": { names: [{ name: "Testi Kauppa Oy", type: "1", version: 1, registrationDate: "2015-03-01" }], status: "2", tradeRegisterStatus: "1", registrationDate: "2015-03-01" },
  "1112223-0": { names: [{ name: "Testi Lopetettu Oy", type: "1", version: 1 }], status: "2", tradeRegisterStatus: "4", registrationDate: "2001-05-02", endDate: "2020-01-31" },
  "9876543-0": { names: [{ name: "Iiro Ateljee Oy", type: "1", version: 1 }, { name: "Vanha Nimi Oy", type: "1", version: 2, endDate: "2019-01-01" }], status: "2", tradeRegisterStatus: "1", registrationDate: "2019-06-10" },
};
let prhDownOnce = new Set(["9876543-0"]); // the first lookup of this one gets a 503 (register unavailable)
const prhServer = require("http").createServer((req, res) => {
  const u = new URL(req.url, "http://localhost");
  prhRequests.push(u.pathname + u.search);
  const id = u.searchParams.get("businessId");
  if (u.pathname !== "/opendata-ytj-api/v3/companies" || !id) { res.writeHead(400); return res.end("{}"); }
  if (prhDownOnce.has(id)) { prhDownOnce.delete(id); res.writeHead(503, { "Content-Type": "application/json" }); return res.end('{"message":"down"}'); }
  const f = prhFixtures[id];
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify(f ? { totalResults: 1, companies: [{ businessId: { value: id, registrationDate: f.registrationDate, source: "3" }, ...f }] } : { totalResults: 0, companies: [] }));
});
prhServer.listen(12224);
process.on("exit", () => prhServer.close());
// Finnish wall-clock date/time/weekday of an instant (scheduled delivery slots are in Europe/Helsinki)
function hel(d = new Date()) {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Helsinki", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", weekday: "short", hourCycle: "h23" }).formatToParts(d);
  const g = (t) => p.find((x) => x.type === t).value;
  return { date: `${g("year")}-${g("month")}-${g("day")}`, time: `${g("hour")}:${g("minute")}`, wd: g("weekday").toLowerCase().slice(0, 3) };
}
/** Emits with an acknowledgement; null after 5 s without one. */
function ack(sock, ev, ...args) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(null), 5000);
    sock.emit(ev, ...args, (reply) => { clearTimeout(timer); resolve(reply); });
  });
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
  // Everyone accepts their agreement at sign-up (stores and couriers must, 2.10; customers too, since 2.11 orders need it)
  const terms = extra.acceptTerms === false ? {} : { acceptTerms: true };
  if (extra.acceptTerms === false) { extra = { ...extra }; delete extra.acceptTerms; }
  const r = await call("POST", "/auth/register", { name, email: `${name.toLowerCase().replace(/\W/g, "")}${uniq}@example.fi`, password: "strong-pass-123", ...(role ? { role } : {}), ...terms, ...extra });
  return r.body;
}

// 2.12: what a store needs before it can publish: the product safety pledge and a manufacturer record (GPSR Art. 19)
async function sellerReady(token, country = "FI") {
  await call("POST", "/stores/my/safety-pledge", { accept: true }, token);
  const m = await call("POST", "/stores/my/operators", { name: `Testi Valmistaja ${country}`, addressLine: "Teollisuuskatu 1", postalCode: "00510", city: "Helsinki", countryCode: country, email: "info@valmistaja.example.fi" }, token);
  return m.body.operator?.id;
}
const wool100 = [{ component: "main", fibres: [{ fibre: "wool", percent: 100 }] }];
/** The required information of a clothing product (fibre composition + the GPSR block), for a business seller. */
const clothing = (mfr, slug = "clothing-tops", extra = {}) => ({
  categorySlug: slug, audience: "UNISEX", attributes: { brand: "Testi", fibreComposition: wool100 },
  manufacturerId: mfr, productModel: "T-100", noWarnings: true, ...extra,
});
/** EAN-13 with its check digit, from 12 digits. */
function ean13(d12) {
  const sum = d12.split("").reduce((t, c, i) => t + Number(c) * (i % 2 === 0 ? 1 : 3), 0);
  return d12 + ((10 - (sum % 10)) % 10);
}

(async () => {
  console.log("\n— Auth");
  const regA = await call("POST", "/auth/register", { name: "Aino Korhonen", email: `aino${uniq}@example.fi`, password: "correct-horse-1", acceptTerms: true });
  check("customer can register", regA.status === 201 && regA.body.accessToken, regA);
  const takeover = await call("POST", "/auth/register", { name: "Evil", email: `aino${uniq}@example.fi`, password: "whatever12", role: "VENDOR", acceptTerms: true });
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

  console.log("\n— Forgot, reset and change password (2.10)");
  check("sessions say whether the account has a password", regA.body.user?.hasPassword === true && codeNew.body.user?.hasPassword === false, [regA.body.user, codeNew.body.user]);
  const meA = await call("GET", "/me", null, tokenA);
  check("GET /me returns the account with hasPassword and googleLinked", meA.status === 200 && meA.body.user?.hasPassword === true && meA.body.user.googleLinked === false && !("passwordHash" in meA.body.user), meA.body);
  const reija = await call("POST", "/auth/register", { name: "Reija Reset", email: `reija${uniq}@example.fi`, password: "old-password-1" });
  const reijaLogin2 = await call("POST", "/auth/login", { email: `reija${uniq}@example.fi`, password: "old-password-1" }); // "another device"
  const resetTarget = `pwreset:reija${uniq}@example.fi`;
  const resetRow = () => sql(`select count(*) from "OtpCode" where target = '${resetTarget}'`);
  const forgot = await call("POST", "/auth/password/forgot", { email: ` Reija${uniq}@Example.fi ` });
  const forgotUnknown = await call("POST", "/auth/password/forgot", { email: `nobody-${uniq}@example.fi` });
  check("forgot password: the same 200 for an existing and an unknown address (no enumeration)", forgot.status === 200 && forgotUnknown.status === 200 && JSON.stringify(forgot.body) === JSON.stringify(forgotUnknown.body) && JSON.stringify(forgot.body) === '{"ok":true}', [forgot.body, forgotUnknown.body]);
  check("forgot password refuses a malformed address (400)", (await call("POST", "/auth/password/forgot", { email: "not-an-email" })).status === 400 && (await call("POST", "/auth/password/forgot", {})).status === 400);
  for (let i = 0; i < 20 && resetRow() !== "1"; i++) await sleep(100);
  check("a reset code is stored hashed (15 minutes) for an account with a password; none for an unknown address", resetRow() === "1" && sql(`select "expiresAt" between now() + interval '14 minutes' and now() + interval '16 minutes' and length("codeHash") = 64 from "OtpCode" where target = '${resetTarget}'`) === "t" && sql(`select count(*) from "OtpCode" where target = 'pwreset:nobody-${uniq}@example.fi'`) === "0");
  await call("POST", "/auth/password/forgot", { email: `otp${uniq}@example.fi` });
  await sleep(300);
  check("an account without a password gets a 'no password needed' note, never a reset code", sql(`select count(*) from "OtpCode" where target = 'pwreset:otp${uniq}@example.fi'`) === "0");
  const limitEmail = `limit-${uniq}@example.fi`;
  const limited3 = [];
  for (let i = 0; i < 4; i++) limited3.push((await call("POST", "/auth/password/forgot", { email: limitEmail })).status);
  check("forgot password is rate-limited per address (3 an hour, any account or none)", limited3.join() === "200,200,200,429", limited3);
  check("a reset code cannot be used to sign in", (await call("POST", "/auth/otp/verify", { target: resetTarget, code: "123456" })).status === 401);
  // The code itself is only in the email (never logged): plant a known one like the sign-in tests do
  const plantReset = (code) => sql(`update "OtpCode" set "codeHash" = '${crypto.createHash("sha256").update(`${resetTarget}:${code}`).digest("hex")}', attempts = 0 where target = '${resetTarget}'`);
  plantReset("246810");
  check("reset with a wrong code is 400", (await call("POST", "/auth/password/reset", { email: `reija${uniq}@example.fi`, code: "111111", password: "new-password-2" })).status === 400);
  check("reset needs a password like registration (8+)", (await call("POST", "/auth/password/reset", { email: `reija${uniq}@example.fi`, code: "246810", password: "short" })).status === 400);
  await sleep(1100); // access tokens carry whole seconds: the old ones must be older than the reset
  const reset = await call("POST", "/auth/password/reset", { email: `reija${uniq}@example.fi`, code: "246810", password: "new-password-2" });
  check("reset with the emailed code sets the new password", reset.status === 200 && reset.body.ok === true && !reset.body.accessToken, reset.body);
  check("after a reset the old password stops working and the new one works", (await call("POST", "/auth/login", { email: `reija${uniq}@example.fi`, password: "old-password-1" })).status === 401 && (await call("POST", "/auth/login", { email: `reija${uniq}@example.fi`, password: "new-password-2" })).status === 200);
  check("after a reset other devices are signed out (refresh and access tokens refused)", (await call("POST", "/auth/refresh", { refreshToken: reija.body.refreshToken })).status === 401 && (await call("POST", "/auth/refresh", { refreshToken: reijaLogin2.body.refreshToken })).status === 401 && (await call("GET", "/me", null, reija.body.accessToken)).status === 401 && (await call("GET", "/me", null, reijaLogin2.body.accessToken)).status === 401);
  check("a reset code works once", (await call("POST", "/auth/password/reset", { email: `reija${uniq}@example.fi`, code: "246810", password: "another-pass-3" })).status === 400);
  sql(`insert into "OtpCode" (target, "codeHash", "expiresAt") values ('${resetTarget}', 'x', now() + interval '15 minutes') on conflict (target) do update set "expiresAt" = excluded."expiresAt"`);
  plantReset("135790");
  for (let i = 0; i < 5; i++) await call("POST", "/auth/password/reset", { email: `reija${uniq}@example.fi`, code: "000000", password: "another-pass-3" });
  check("after 5 wrong codes even the right one is refused", (await call("POST", "/auth/password/reset", { email: `reija${uniq}@example.fi`, code: "135790", password: "another-pass-3" })).status === 400);
  const reijaNow = await call("POST", "/auth/login", { email: `reija${uniq}@example.fi`, password: "new-password-2" });
  const reijaOther = await call("POST", "/auth/login", { email: `reija${uniq}@example.fi`, password: "new-password-2" });
  check("changing the password needs the current one (400) and a signed-in user", (await call("POST", "/auth/password/change", { currentPassword: "wrong-one-9", newPassword: "changed-pass-4" }, reijaNow.body.accessToken)).status === 400 && (await call("POST", "/auth/password/change", { currentPassword: "new-password-2", newPassword: "changed-pass-4" })).status === 401);
  check("the new password follows the registration rules", (await call("POST", "/auth/password/change", { currentPassword: "new-password-2", newPassword: "short" }, reijaNow.body.accessToken)).status === 400);
  await sleep(1100);
  const changed = await call("POST", "/auth/password/change", { currentPassword: "new-password-2", newPassword: "changed-pass-4" }, reijaNow.body.accessToken);
  check("password change returns a fresh session like login and keeps this device signed in", changed.status === 200 && !!changed.body.accessToken && !!changed.body.refreshToken && changed.body.user?.hasPassword === true && (await call("GET", "/me", null, changed.body.accessToken)).status === 200, changed.body);
  check("password change signs the other devices out", (await call("POST", "/auth/refresh", { refreshToken: reijaOther.body.refreshToken })).status === 401 && (await call("GET", "/me", null, reijaOther.body.accessToken)).status === 401 && (await call("POST", "/auth/login", { email: `reija${uniq}@example.fi`, password: "changed-pass-4" })).status === 200);
  check("an account without a password cannot 'change' one", (await call("POST", "/auth/password/change", { currentPassword: "x", newPassword: "whatever-123" }, codeNew.body.accessToken)).status === 400);

  console.log("\n— Agreements and language (2.10)");
  const noTermsV = await call("POST", "/auth/register", { name: "No Terms", email: `noterms${uniq}@example.fi`, password: "strong-pass-123", role: "VENDOR" });
  const noTermsC = await call("POST", "/auth/register", { name: "No Terms C", email: `notermsc${uniq}@example.fi`, password: "strong-pass-123", role: "COURIER" });
  check("store and courier registration require accepting the agreement (400)", noTermsV.status === 400 && noTermsC.status === 400 && /Seller Terms/.test(noTermsV.body.error || ""), [noTermsV.body.error, noTermsC.body.error]);
  const withTerms = await register("Terhi", "VENDOR");
  check("accepting stores the time and the agreement version (seller terms)", sql(`select ("termsAcceptedAt" is not null) || '|' || "termsVersion" from "User" where id = ${withTerms.user.id}`).match(/^true\|vendor_terms@[0-9a-f]{12}$/) !== null, sql(`select coalesce("termsVersion", '-') from "User" where id = ${withTerms.user.id}`));
  const custTerms = await call("POST", "/auth/register", { name: "Cecilia", email: `cecilia${uniq}@example.fi`, password: "strong-pass-123", acceptTerms: true });
  check("a customer who accepts gets the customer terms version", custTerms.status === 201 && /^terms_of_service@[0-9a-f]{12}$/.test(sql(`select "termsVersion" from "User" where id = ${custTerms.body.user.id}`)));
  const fiTok = custTerms.body.accessToken;
  await call("GET", "/me", null, fiTok, { headers: { "Accept-Language": "fi-FI,fi;q=0.9,en;q=0.5" } });
  await sleep(200);
  check("the app's Accept-Language is stored as the user's language", sql(`select locale from "User" where id = ${custTerms.body.user.id}`) === "fi");
  await call("GET", "/me", null, fiTok, { headers: { "Accept-Language": "sv-SE" } });
  await sleep(200);
  check("any other language is stored as English", sql(`select locale from "User" where id = ${custTerms.body.user.id}`) === "en");
  const setFi = await call("PATCH", "/me", { locale: "fi" }, fiTok);
  check("PATCH /me sets the language (fi|en); anything else is 400", setFi.status === 200 && setFi.body.user?.locale === "fi" && (await call("PATCH", "/me", { locale: "sv" }, fiTok)).status === 400 && (await call("PATCH", "/me", {}, fiTok)).status === 400);
  check("requests without Accept-Language leave the language alone", (await call("GET", "/me", null, fiTok)).body.user?.locale === "fi");

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
  const store = await call("POST", "/stores", { name: `Vera Vintage ${uniq}`, category: "THRIFT", sellerType: "BUSINESS", businessId: "2345678-0", latitude: 60.17, longitude: 24.94, address: "Mannerheimintie 1, Helsinki", prepMinutes: 8 }, vendor.accessToken);
  check("vendor creates a business store with Y-tunnus", store.status === 201 && store.body.store.sellerType === "BUSINESS", store);
  const storeId = store.body.store.id;
  const veraMfr = await sellerReady(vendor.accessToken);
  check("business seller must give a valid Y-tunnus", (await call("POST", "/stores", { name: "No ID", category: "APPAREL", sellerType: "BUSINESS" }, (await register("Nina", "VENDOR")).accessToken)).status === 400);
  const privSeller = await call("POST", "/stores", { name: `Pekka's closet ${uniq}`, category: "THRIFT", sellerType: "PRIVATE" }, (await register("Pekka", "VENDOR")).accessToken);
  check("private seller needs no Y-tunnus", privSeller.status === 201 && privSeller.body.store.sellerType === "PRIVATE", privSeller.body);
  check("customer cannot create a store", (await call("POST", "/stores", { name: "Sneaky", category: "OTHER" }, tokenA)).status === 403);
  check("unverified store hidden from public list", (await call("GET", `/stores?search=Vera Vintage ${uniq}`)).body.stores.length === 0);
  const foreignImg = await call("POST", "/products", { name: "Stolen pic", category: "Coat", salePriceCents: 5000, images: ["https://res.cloudinary.com/demo/coat.jpg"] }, vendor.accessToken);
  check("product photos must be the store's own uploads", foreignImg.status === 400, foreignImg.body);
  const prod = await call("POST", "/products", { name: "Wool coat", category: "Coat", salePriceCents: 5000, stockQuantity: 2, images: [ownImage(storeId, "coat")], ...clothing(veraMfr, "clothing-jackets-coats") }, vendor.accessToken);
  check("vendor creates product with own photo", prod.status === 201 && prod.body.product.images.length === 1, prod.body);
  const productId = prod.body.product.id;

  const adminUser = await register("Admin");
  sql(`update "User" set role='ADMIN' where id=${adminUser.user.id}`);
  const adminToken = (await call("POST", "/auth/login", { email: `admin${uniq}@example.fi`, password: "strong-pass-123" })).body.accessToken;
  check("non-admin blocked from admin API", (await call("GET", "/admin/stats", null, tokenA)).status === 403);
  check("admin approves store", (await call("PATCH", `/admin/vendors/${storeId}/approve`, null, adminToken)).status === 200);
  const pub2 = await call("GET", `/stores?search=Vera Vintage ${uniq}&lat=60.18&lng=24.95`);
  const listed = pub2.body.stores[0];
  check("approved store is public with trader info and ETA window", listed?.businessId === "2345678-0" && listed?.etaMinutes > 0 && listed?.etaMaxMinutes === listed?.etaMinutes + 10, listed);
  check("reviewed store cannot relabel itself as a private seller", (await call("POST", "/stores", { name: `Vera Vintage ${uniq}`, category: "THRIFT", sellerType: "PRIVATE" }, vendor.accessToken)).body.store?.sellerType === "BUSINESS");
  const listedFee = listed.deliveryFeeCents;

  console.log("\n— Couriers");
  const c1 = await register("Kalle", "COURIER");
  const c2 = await register("Linnea", "COURIER");
  check("unapproved courier cannot see jobs", (await call("GET", "/orders/available", null, c1.accessToken)).status === 403);
  // Payout onboarding is a step towards approval, so it is open before approval; jobs (and so money) only come after
  const earlyPayout = await call("POST", "/payouts/onboarding", null, c1.accessToken);
  check("an unapproved courier can already set up payouts (Stripe onboarding), but still gets no jobs", earlyPayout.status === 200 && /^https?:\/\//.test(earlyPayout.body.url || "") && (await call("GET", "/orders/available", null, c1.accessToken)).status === 403, earlyPayout.body);
  const couriers = (await call("GET", "/admin/couriers", null, adminToken)).body.couriers;
  for (const c of couriers.filter((x) => [c1.user.id, c2.user.id].includes(x.user?.id))) await call("PATCH", `/admin/couriers/${c.id}/approve`, null, adminToken);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.171, longitude: 24.941 }, c1.accessToken);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.2, longitude: 24.9 }, c2.accessToken);
  await call("POST", "/me/devices", { token: `courier-device-${uniq}-xxxxxxxxxxxx`, platform: "android" }, c1.accessToken);

  console.log("\n— Checkout through Stripe (stripe-mock)");
  const otherCustEarly = await register("Ulla");
  const realOrder = await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }] }, tokenA);
  check("order creates a PaymentIntent and returns a client secret", realOrder.status === 201 && !!realOrder.body.clientSecret, realOrder.body);
  const ro = realOrder.body.order;
  // Courier pay is separate from the customer fee: 1.24 km straight = 1.6 km route → 4.50 + 1.76 € = 6.26 €, raised to the 6.50 € minimum
  check("courier pay (formula, with minimum) and ETA are set on the order", sql(`select "courierFeeCents" = 650 and ("courierPay"->>'topUpCents')::int = 24 and ("courierPay"->>'distanceKm')::float = 1.6 and "etaMinutes" > 0 from "Order" where id=${ro?.id}`) === "t", sql(`select "courierFeeCents" || ' ' || coalesce("courierPay"::text, '') from "Order" where id=${ro?.id}`));
  check("charged delivery fee equals the advertised fee", ro?.deliveryFeeCents === listedFee, { charged: ro?.deliveryFeeCents, listed: listedFee });
  const payInfo = await call("GET", `/orders/${ro.id}/payment`, null, tokenA);
  check("an unpaid order can be finished: the PaymentSheet secret, amount and hold time", payInfo.status === 200 && !!payInfo.body.clientSecret && payInfo.body.amountCents === ro.totalCents && new Date(payInfo.body.holdUntil) > new Date(), payInfo.body);
  check("only the customer can get the payment of an order", (await call("GET", `/orders/${ro.id}/payment`, null, otherCustEarly.accessToken)).status === 404 && (await call("GET", `/orders/${ro.id}/payment`, null, vendor.accessToken)).status === 403);
  check("customer cancels before the store accepts; stock returns", (await call("POST", `/orders/${ro.id}/cancel`, null, tokenA)).status === 200 && sql(`select "stockQuantity" from "Product" where id=${productId}`) === "2");
  check("a cancelled order can no longer be paid (409)", (await call("GET", `/orders/${ro.id}/payment`, null, tokenA)).status === 409);
  const retryA = await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 2 }] }, tokenA);
  const retryB = await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 2 }] }, tokenA);
  check("retrying checkout never fails on stock: the earlier unpaid checkout is cancelled quietly", retryA.status === 201 && retryB.status === 201 && sql(`select status || '|' || "cancelReason" from "Order" where id=${retryA.body.order?.id}`) === "CANCELLED|Replaced by a new checkout" && sql(`select "stockQuantity" from "Product" where id=${productId}`) === "0", [retryA.body, retryB.body]);
  check("cannot order more than stock", (await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", items: [{ productId, quantity: 5 }] }, tokenA)).status === 400);
  check("…and that attempt released the previous unpaid checkout too", sql(`select status from "Order" where id=${retryB.body.order?.id}`) === "CANCELLED" && sql(`select "stockQuantity" from "Product" where id=${productId}`) === "2");

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
  const p2 = (await call("POST", "/products", { name: "Silk scarf", category: "Accessories", salePriceCents: 6000, images: [ownImage(storeId, "scarf")], ...clothing(veraMfr, "accessories-scarves") }, vendor.accessToken)).body.product;
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
  const p3res = await call("POST", "/products", { name: "Linen shirt", category: "Shirt", salePriceCents: 3900, images: [ownImage(storeId, "shirt")], ...clothing(veraMfr, "clothing-shirts-blouses"),
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
  await call("POST", "/stores", { name: `Otto Outlet ${uniq}`, category: "APPAREL", sellerType: "BUSINESS", businessId: "1234567-1", latitude: 60.2, longitude: 24.9 }, otherVendor.accessToken);
  const ottoMfr = await sellerReady(otherVendor.accessToken);
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
  const oProd = (await call("POST", "/products", { name: "Denim", category: "Jeans", salePriceCents: 7000, ...clothing(ottoMfr, "clothing-trousers-jeans") }, otherVendor.accessToken)).body.product;
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
  const ecoOn = await call("GET", "/products/search?eco=true&limit=50");
  check("the removed eco filter is ignored (same results as without it)", ecoOn.status === 200 && ecoOn.body.total === (await call("GET", "/products/search?limit=50")).body.total, ecoOn.body.total);

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
  check("fee levers are off by default and listed in system status", sysDefault.pricing?.serviceFeePercent === 0 && sysDefault.pricing?.smallOrderThresholdCents === 0 && sysDefault.pricing?.minChargeCents === 50 && sysDefault.version === "2.13.0", sysDefault.pricing);
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

  const socks = (await call("POST", "/products", { name: "Wool socks", category: "Socks", salePriceCents: 100, stockQuantity: 20, images: [ownImage(storeId, "socks")], ...clothing(veraMfr, "clothing-underwear-nightwear") }, vendor.accessToken)).body.product;
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
  check("Shopify mapping: name, plain-text description, category, price, size/colour options with price differences, GTIN", dress?.name === "Linen Dress" && dress.description === "Soft linen & cotton" && dress.category === "Dresses" && dress.categorySlug === "clothing-dresses" && dress.salePriceCents === 4990 && dress.variants.length === 2 && dress.variants[0].size === "S" && dress.variants[0].color === "Musta" && dress.variants[1].priceAdjustCents === 300 && dress.variants[0].stock === 3 && dress.stockQuantity === 3 && dress.gtin === "6412345678901", dress);
  check("a vintage tag and no stock levels: Good condition, stock 1, category from the title", boots?.condition === "GOOD" && boots.isSecondHand === true && boots.stockQuantity === 1 && boots.category === "Boots & ankle boots" && boots.categorySlug === "shoes-boots" && boots.variants.length === 0, boots);
  check("photos are copied into the store's own Cloudinary folder; products never hold remote URLs", own.every((p) => p.images.every((u) => u.startsWith(`https://res.cloudinary.com/testcloud/image/upload/c_limit,w_1200,q_auto,f_auto/malvoya/products/s${impStore.id}/imp-`))) && dress?.images.length === 2 && !JSON.stringify(own).includes("shopify.test"), own.map((p) => p.images));
  const uploads1 = await (await fetch("http://localhost:12222/__uploads")).json();
  check("the copies are signed server-side uploads of the shop's photo URLs", uploads1.some((u) => u.file === "https://cdn.shopify.test/files/dress1.jpg?v=1") && uploads1.some((u) => u.file === "https://cdn.shopify.test/files/dress2.jpg") && uploads1.every((u) => u.public_id.startsWith(`malvoya/products/s${impStore.id}/imp-`)), uploads1);
  check("imported prices start the 30-day price history", sql(`select count(*) from "PriceChange" where "productId"=${dress?.id}`) === "1");
  check("a draft cannot be opened by anyone but its store", (await call("GET", `/products/${dress?.id}`)).status === 404 && (await call("GET", `/products/${dress?.id}`, null, otherCust.accessToken)).status === 404 && (await call("GET", `/products/${dress?.id}`, null, importer.accessToken)).status === 200);
  check("drafts are not public", (await call("GET", `/stores/${impStore.id}/products`)).body.products.length === 0 && !(await call("GET", `/products/search?q=${encodeURIComponent("Linen Dress")}`)).body.products.some((p) => p.id === dress?.id));
  // 2.12: drafts that miss required information stay drafts and are listed with what is missing
  const pub0 = await call("POST", `/products/import/${sj.body.job.id}/publish`, null, importer.accessToken);
  const dressMissing = pub0.body.incomplete?.find((x) => x.productId === dress?.id)?.missing.map((m) => m.field) ?? [];
  check("publishing an import refuses drafts that miss required information, and says what is missing", pub0.status === 200 && pub0.body.published === 0 && dressMissing.includes("safetyPledge") && dressMissing.includes("attributes.fibreComposition") && pub0.body.incomplete.length === 2, pub0.body);
  await call("POST", "/stores/my/safety-pledge", { accept: true }, importer.accessToken);
  await call("PATCH", `/products/${dress?.id}`, { attributes: { fibreComposition: [{ component: "main", fibres: [{ fibre: "flax", percent: 55 }, { fibre: "cotton", percent: 45 }] }] } }, importer.accessToken);
  const pub1 = await call("POST", `/products/import/${sj.body.job.id}/publish`, null, importer.accessToken);
  const publicNow = (await call("GET", `/stores/${impStore.id}/products`)).body.products.map((p) => p.id).sort();
  check("once complete (pledge; a private seller's second-hand boots need no labels) the drafts with a photo and a price publish, not the one without a photo", pub1.status === 200 && pub1.body.published === 2 && publicNow.join() === [dress?.id, boots?.id].sort().join(), [pub1.body, publicNow]);
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
  check("CSV mapping: options with price differences, quoted text, comma decimals, category mapping", sweater?.salePriceCents === 5990 && sweater.variants.length === 2 && sweater.variants[1].priceAdjustCents === 300 && sweater.stockQuantity === 3 && sweater.description === 'Warm "merino" wool' && sweater.category === "Knitwear & hoodies" && sweater.categorySlug === "clothing-knitwear" && sweater.images.length === 2 && sweater.isAvailable === false, sweater);
  check("CSV: dot decimals, condition and GTIN; an http photo is skipped", scarf?.salePriceCents === 1950 && scarf.condition === "LIKE_NEW" && scarf.gtin === "40123455" && scarf.categorySlug === "accessories-scarves" && cap?.images.length === 0 && cap.categorySlug === "accessories-hats-beanies", [scarf, cap]);
  const cj2 = await csvImport({ csv: csvText, rightsConfirmed: true });
  const cjob2 = await waitJob(cj2.body.job?.id);
  // 3 Shopify + 3 CSV products, less the boots the store deleted (since 2.10 deleted products leave the owner's list too)
  check("re-importing the same CSV updates, never duplicates", cjob2?.created === 0 && cjob2.updated === 3 && (await ownList()).length === 5, cjob2);
  const cpub = (await call("POST", `/products/import/${cj2.body.job?.id}/publish`, null, importer.accessToken)).body;
  check("publishing the CSV import: textile drafts without a composition stay drafts (only those with a photo are listed)", cpub.published === 0 && cpub.incomplete?.length === 2 && cpub.incomplete.every((x) => x.missing.some((m) => m.field === "attributes.fibreComposition")), cpub);
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
  const wStore = (await call("POST", "/stores", { name: `Wilma Woo ${uniq}`, category: "APPAREL", sellerType: "BUSINESS", businessId: "4567890-7", latitude: 60.17, longitude: 24.94 }, wilma.accessToken)).body.store;
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
  check("WooCommerce mapping: variations become size/colour options with price differences and stock, GTIN, plain-text description", cardigan?.name === "Merino Cardigan" && cardigan.externalSource === "WOOCOMMERCE" && cardigan.salePriceCents === 7900 && cardigan.description === "Soft merino wool" && cardigan.categorySlug === "clothing-knitwear" && cardigan.variants.length === 2 && cardigan.variants[0].size === "S" && cardigan.variants[0].color === "Grey" && cardigan.variants[0].stock === 2 && cardigan.variants[1].size === "M" && cardigan.variants[1].stock === 0 && cardigan.variants[1].priceAdjustCents === 600 && cardigan.gtin === "6412345678901" && cardigan.images.length === 2 && cardigan.isAvailable === false, cardigan);
  check("WooCommerce mapping: a simple vintage product, stock not tracked → 1 with a warning, photos re-hosted", belt?.salePriceCents === 3500 && belt.condition === "GOOD" && belt.stockQuantity === 1 && belt.categorySlug === "accessories-belts" && belt.images.every((u) => u.includes(`/malvoya/products/s${wStore.id}/imp-`)) && wjob.errors.some((e) => e.item === "Leather Belt" && /stock/.test(e.message)), belt);
  const keyLeak = wooSeen.some((r) => r.url.includes("ck_") || r.url.includes("cs_")) || wooSeen.some((r) => r.method !== "GET");
  check("the keys go only in the Authorization header of GET requests to the shop, never in a URL", wooSeen.length > 0 && !keyLeak && wooSeen.every((r) => r.url.startsWith("/wp-json/wc/v3/")), wooSeen.slice(0, 5));
  check("the keys are not stored anywhere", sql(`select count(*) from "ImportJob" where "errors"::text ~ '(ck|cs)_' or coalesce("sourceRef",'') ~ '(ck|cs)_'`) === "0" && !JSON.stringify(wj.body).includes(CS));
  const wpub = (await call("POST", `/products/import/${wj.body.job.id}/publish`, null, wilma.accessToken)).body;
  check("publishing the WooCommerce import: a business seller's drafts need the manufacturer, model and warnings first", wpub.published === 0 && wpub.incomplete?.length === 2 && wpub.incomplete.every((x) => x.missing.some((m) => m.field === "manufacturerId") && x.missing.some((m) => m.field === "productModel")), wpub);
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
  const stina = (await call("POST", "/stores", { name: `Stina <b>Studio</b> ${uniq}`, category: "APPAREL", sellerType: "BUSINESS", businessId: "3334445-9", latitude: 60.16, longitude: 24.93, address: "Bulevardi 3, Helsinki" }, stinaV.accessToken)).body.store;
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
  check("a Finnish VAT number must match the store's Y-tunnus", badVat.status === 400 && /FI33344459/.test(badVat.body.error || ""), badVat.body);
  check("unknown fields are refused", (await taxPut({ ...stinaTax, iban: "FI00" }, stinaV.accessToken)).status === 400);
  const t1 = await taxPut({ ...stinaTax, vatNumber: "fi 3334 4459" }, stinaV.accessToken);
  check("business seller saves legal name, VAT number and registered address; Y-tunnus comes from the store", t1.status === 200 && t1.body.taxInfoComplete === true && t1.body.taxInfo.vatNumber === "FI33344459" && t1.body.taxInfo.businessId === "3334445-9" && t1.body.taxInfo.country === "FI" && t1.body.taxInfo.dateOfBirth === null && t1.body.taxInfo.tinMasked === null, t1.body);
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
  check("printable statement: titled 'not a VAT invoice', store name escaped, Y-tunnus, Malvoya's details as placeholders, no scripts", stRes.status === 200 && /text\/html/.test(stRes.headers.get("content-type") || "") && stHtml.includes("Statement — not a VAT invoice") && stHtml.includes("Stina &lt;b&gt;Studio&lt;/b&gt;") && !stHtml.includes("<b>Studio") && stHtml.includes("3334445-9") && stHtml.includes("+Stina Studio Oy") && stHtml.includes("[COMPANY LEGAL NAME]") && stHtml.includes(`#${sA}`) && !/<script/i.test(stHtml) && (stRes.headers.get("content-security-policy") || "").startsWith("default-src 'none'"), stHtml.slice(0, 400));
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
  check("DAC7: business identity (legal name, Y-tunnus, VAT number, address)", dS?.identity?.legalName === "+Stina Studio Oy" && dS.identity.businessId === "3334445-9" && dS.identity.vatNumber === "FI33344459" && dS.identity.address?.postalCode === "00120" && dS.identity.tin === null && dS.taxInfoComplete === true, dS?.identity);
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

  // This instance also runs as production without SMTP: password reset by email is unavailable there
  // DELIVERY_SLOTS empty (the default since 2.12): scheduled delivery is off, no invented time windows
  const refUp = await startFeeApi({ NODE_ENV: "production", REFERRAL_DISCOUNT_CENTS: "500", REFERRAL_REWARD_CENTS: "300", ANDROID_APP_SHA256: `${"ab:".repeat(31)}cd, ${"12:".repeat(31)}EF, not-a-fingerprint`, DELIVERY_SLOTS: "", APPLE_TEAM_ID: "AB12CD34EF" });
  check("API starts with invites switched on", refUp);
  const noSlotQ = await quote({ storeId, deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }] }, otherCust.accessToken, FEE_API);
  const aasaOn = await (await fetch(`${FEE_BASE}/.well-known/apple-app-site-association`)).json();
  check("apple-app-site-association lists the customer app with the Team ID and the /s, /r, /d paths", JSON.stringify(aasaOn) === JSON.stringify({ applinks: { details: [{ appIDs: ["AB12CD34EF.com.malvoya.customer"], components: [{ "/": "/s/*" }, { "/": "/r/*" }, { "/": "/d/*" }] }] } }), aasaOn);
  check("without DELIVERY_SLOTS GET /delivery/today lists no slots", ((await callAt(FEE_API, "GET", "/delivery/today?lat=60.17&lng=24.94")).body.slots ?? [1]).length === 0);
  check("without DELIVERY_SLOTS no delivery windows are offered and none can be booked (2.12 default)", noSlotQ.status === 200 && Array.isArray(noSlotQ.body.quote?.slots) && noSlotQ.body.quote.slots.length === 0 && (await quote({ storeId, deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }], deliverySlot: { date: hel(new Date(Date.now() + 86_400_000)).date, start: "17:00", end: "19:00" } }, otherCust.accessToken, FEE_API)).status === 400, noSlotQ.body.quote?.slots);
  const noMail = await callAt(FEE_API, "POST", "/auth/password/forgot", { email: `reija${uniq}@example.fi` });
  check("without email sending, forgot password says so (503) for any address", noMail.status === 503 && noMail.body.error === "Password reset by email is not available yet. Contact support." && (await callAt(FEE_API, "POST", "/auth/password/forgot", { email: `nobody2-${uniq}@example.fi` })).status === 503, noMail.body);
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
  const evilProd = await call("POST", "/products", { name: "Tee <script>alert(1)</script>", category: "Shirt", salePriceCents: 2500, images: [ownImage(storeId, "tee")], ...clothing(veraMfr) }, vendor.accessToken);
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
  const conn = await call("POST", "/admin/system/check", null, adminToken);
  const cc = conn.body?.checks ?? {};
  check("connection test: Stripe accepts the key and reports test mode", conn.status === 200 && cc.payments?.ok === true && /test mode/.test(cc.payments.detail), cc.payments);
  check("connection test: a Stripe webhook that does not point at this server is reported", cc.paymentWebhook?.ok === false && cc.paymentWebhook.detail.includes("/api/v1/payments/webhook"), cc.paymentWebhook);
  check("connection test: Cloudinary accepts the account and key", cc.photosAndVideos?.ok === true, cc.photosAndVideos);
  check("connection test: services that are not set up say so instead of failing", cc.email?.ok === null && cc.sms?.ok === null && cc.pushNotifications?.ok === null && cc.googleSignIn?.ok === null && /Not set up/.test(cc.email.detail), cc);
  check("connection test never returns keys or secrets", !JSON.stringify(conn.body).includes("sk_test_123") && !JSON.stringify(conn.body).includes(CLD_SECRET) && !JSON.stringify(conn.body).includes(WHSEC));
  check("only admins can run the connection test", (await call("POST", "/admin/system/check", null, vendor.accessToken)).status === 403 && (await call("POST", "/admin/system/check")).status === 401);
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

  console.log("\n— Store cancel reasons (2.10)");
  sql(`update "Product" set "stockQuantity"=40, "isAvailable"=true where id=${productId}`);
  const scRes = await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", deliveryLat: 60.18, deliveryLng: 24.95, items: [{ productId, quantity: 1 }] }, otherCust.accessToken);
  await payOrder(scRes.body.order);
  check("a store's cancel reason is limited to 200 characters", (await call("PATCH", `/orders/${scRes.body.order.id}/status`, { status: "CANCELLED", reason: "x".repeat(201) }, vendor.accessToken)).status === 400);
  const scCancel = await call("PATCH", `/orders/${scRes.body.order.id}/status`, { status: "CANCELLED", reason: "Item damaged / Tuote vaurioitunut" }, vendor.accessToken);
  const scView = (await call("GET", `/orders/${scRes.body.order.id}`, null, otherCust.accessToken)).body.order;
  check("the store's reason is stored as the cancel reason and shown to the customer; the customer is refunded", scCancel.status === 200 && scView?.cancelReason === "Item damaged / Tuote vaurioitunut" && sql(`select "cancelledBy" || '|' || "paymentStatus" from "Order" where id=${scRes.body.order.id}`) === "STORE|REFUNDED", [scCancel.body, scView?.cancelReason]);

  console.log("\n— Returns: store notes and notifications (2.10)");
  const rnOrder = Number(sql(`insert into "Order" ("userId","storeId","status","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","stripePaymentIntentId","paymentStatus","paidAt","deliveredAt","deliveryAddress","updatedAt") values (${otherCust.user.id},${storeId},'DELIVERED',4000,300,300,400,3600,4300,'pi_ret2_${uniq}','SUCCEEDED',now(),now(),'Aleksanterinkatu 5, Helsinki',now()) returning id`).split("\n")[0]);
  sql(`insert into "OrderItem" ("orderId","productId","quantity","unitCents") values (${rnOrder},${productId},1,4000)`);
  vendorSock.events.length = 0;
  const rn1 = await call("POST", "/returns", { orderId: rnOrder, reason: "CHANGED_MIND", conditionNote: "Too big" }, otherCust.accessToken);
  await sleep(400);
  check("a new return reaches the store live (return:new) and the payload has storeNote", rn1.status === 201 && rn1.body.return?.storeNote === null && vendorSock.events.some((e) => e.ev === "return:new" && e.data.returnId === rn1.body.return.id && e.data.orderId === rnOrder), [rn1.body, vendorSock.events.map((e) => e.ev)]);
  const myRet = (await call("GET", "/returns", null, otherCust.accessToken)).body.returns?.find((r) => r.id === rn1.body.return?.id);
  check("the customer's return says where to take the items (store name, address, phone)", myRet?.store?.name === `Vera Vintage ${uniq}` && myRet.store.address === "Mannerheimintie 1, Helsinki" && "phone" in myRet.store, myRet?.store);
  check("rejecting a return needs the store's reason (storeNote)", (await call("PATCH", `/returns/${rn1.body.return.id}/status`, { status: "REJECTED" }, vendor.accessToken)).status === 400);
  const rnRej = await call("PATCH", `/returns/${rn1.body.return.id}/status`, { status: "REJECTED", storeNote: "The tags were removed and it was worn" }, vendor.accessToken);
  check("the store rejects with a note; the customer's own note is kept separately", rnRej.status === 200 && rnRej.body.return?.status === "REJECTED" && rnRej.body.return.storeNote === "The tags were removed and it was worn" && rnRej.body.return.conditionNote === "Too big", rnRej.body);
  const rn2 = await call("POST", "/returns", { orderId: rnOrder, reason: "NOT_AS_DESCRIBED" }, otherCust.accessToken);
  const rnAppr = await call("PATCH", `/returns/${rn2.body.return?.id}/status`, { status: "APPROVED", storeNote: "Bring it to the counter" }, vendor.accessToken);
  check("after a rejection the items can be returned again; approval carries a note", rn2.status === 201 && rnAppr.status === 200 && rnAppr.body.return?.storeNote === "Bring it to the counter", [rn2.body, rnAppr.body]);
  const rnRef = await call("PATCH", `/returns/${rn2.body.return?.id}/status`, { status: "REFUNDED", damageDedCents: 500, storeNote: "A stain on the sleeve" }, vendor.accessToken);
  check("a deduction can be explained in the store note (old apps: the condition note)", rnRef.status === 200 && rnRef.body.return?.refundCents === 4300 - 500 && rnRef.body.return.storeNote === "A stain on the sleeve", rnRef.body);

  console.log("\n— Deleting products and the store's own catalogue (2.10)");
  const hardP = (await call("POST", "/products", { name: `Delete me ${uniq}`, category: "Shirt", salePriceCents: 1500, images: [ownImage(storeId, "del")], ...clothing(veraMfr) }, vendor.accessToken)).body.product;
  const hardDel = await call("DELETE", `/products/${hardP.id}`, null, vendor.accessToken);
  check("a product nobody ordered is deleted for good", hardDel.status === 200 && hardDel.body.deleted === "hard" && sql(`select count(*) from "Product" where id=${hardP.id}`) === "0", hardDel.body);
  const softP = (await call("POST", "/products", { name: `Keep me ${uniq}`, category: "Shirt", salePriceCents: 1500, stockQuantity: 0, images: [ownImage(storeId, "keep")], ...clothing(veraMfr) }, vendor.accessToken)).body.product;
  const mySold = await call("GET", "/stores/my/products?filter=soldout&limit=100", null, vendor.accessToken);
  check("the store's catalogue filters sold-out products", mySold.status === 200 && mySold.body.products.some((p) => p.id === softP.id) && mySold.body.products.every((p) => p.stockQuantity <= 0), mySold.body.products?.map((p) => p.stockQuantity));
  sql(`insert into "OrderItem" ("orderId","productId","quantity","unitCents") values (${rnOrder},${softP.id},1,1500)`);
  check("another store cannot delete it", (await call("DELETE", `/products/${softP.id}`, null, otherVendor.accessToken)).status === 403);
  const softDel = await call("DELETE", `/products/${softP.id}`, null, vendor.accessToken);
  check("an ordered product is kept for the records but marked deleted", softDel.status === 200 && softDel.body.deleted === "soft" && sql(`select ("deletedAt" is not null) || '|' || "isAvailable" from "Product" where id=${softP.id}`) === "true|false", softDel.body);
  const ownerList = (await call("GET", `/stores/${storeId}/products?limit=50`, null, vendor.accessToken)).body.products;
  const myQ = await call("GET", `/stores/my/products?q=${encodeURIComponent(`Keep me ${uniq}`)}`, null, vendor.accessToken);
  check("a deleted product disappears everywhere, also from the owner's lists", (await call("GET", `/products/${softP.id}`, null, vendor.accessToken)).status === 404 && !ownerList.some((p) => p.id === softP.id) && myQ.body.total === 0 && !(await call("GET", "/stores/my", null, vendor.accessToken)).body.store.products.some((p) => p.id === softP.id));
  check("deleting it again is 404; editing it is 404", (await call("DELETE", `/products/${softP.id}`, null, vendor.accessToken)).status === 404 && (await call("PATCH", `/products/${softP.id}`, { salePriceCents: 1000 }, vendor.accessToken)).status === 404);
  const myP1 = await call("GET", "/stores/my/products?page=1&limit=2", null, vendor.accessToken);
  const myP2 = await call("GET", "/stores/my/products?page=2&limit=2", null, vendor.accessToken);
  check("the store's catalogue is paged: products, total, page, pageSize", myP1.status === 200 && myP1.body.products.length === 2 && myP1.body.page === 1 && myP1.body.pageSize === 2 && myP1.body.total >= 4 && myP2.body.page === 2 && !myP2.body.products.some((p) => myP1.body.products.some((q) => q.id === p.id)), [myP1.body.total, myP1.body.pageSize]);
  const myVis = (await call("GET", "/stores/my/products?filter=visible&limit=100", null, vendor.accessToken)).body;
  const myDrafts = (await call("GET", "/stores/my/products?filter=drafts&limit=100", null, vendor.accessToken)).body;
  check("filters: visible and drafts", myVis.products.every((p) => p.isAvailable === true) && myDrafts.products.every((p) => p.isAvailable === false) && myVis.total + myDrafts.total === myP1.body.total);
  check("the catalogue is the owner's (customers 403); bad filters are 400", (await call("GET", "/stores/my/products", null, otherCust.accessToken)).status === 403 && (await call("GET", "/stores/my/products?filter=secret", null, vendor.accessToken)).status === 400 && (await call("GET", "/stores/my/products?limit=500", null, vendor.accessToken)).status === 400);

  console.log("\n— Courier cannot deliver: chat, wait, back to the shop (2.10)");
  const dpRes = await call("POST", "/orders", { storeId, deliveryAddress: "Aleksanterinkatu 5, Helsinki", deliveryLat: 60.18, deliveryLng: 24.95, tipCents: 200, items: [{ productId, quantity: 2 }] }, otherCust.accessToken);
  const dp = dpRes.body.order;
  await payOrder(dp);
  await call("PATCH", `/orders/${dp.id}/status`, { status: "CONFIRMED" }, vendor.accessToken);
  await call("POST", "/courier/status", { isOnline: true, latitude: 60.1702, longitude: 24.9402 }, c1.accessToken);
  const dpAcc = await call("PATCH", `/orders/${dp.id}/assign-courier`, null, c1.accessToken);
  check("courier takes the job", dpAcc.status === 200, dpAcc.body);
  const custChat = await connect(otherCust.accessToken);
  const join1 = await ack(custChat, "chat:join", dp.id);
  check("chat:join acknowledges with the history (empty at first)", join1?.ok === true && Array.isArray(join1.messages) && join1.messages.length === 0, join1);
  const msg1 = await call("POST", `/orders/${dp.id}/messages`, { text: "  I'll be at the door in 5 min  " }, otherCust.accessToken);
  check("the customer sends a message over HTTP; it is stored", msg1.status === 201 && msg1.body.message?.text === "I'll be at the door in 5 min" && msg1.body.message.senderRole === "CUSTOMER" && msg1.body.message.senderId === otherCust.user.id && msg1.body.message.orderId === dp.id, msg1.body);
  check("only the customer, the assigned courier and admins can read the chat", (await call("GET", `/orders/${dp.id}/messages`, null, vendor.accessToken)).status === 404 && (await call("GET", `/orders/${dp.id}/messages`, null, pirjo.accessToken)).status === 404 && (await call("GET", `/orders/${dp.id}/messages`, null, c2.accessToken)).status === 404 && (await call("GET", `/orders/${dp.id}/messages`, null, adminToken)).status === 200);
  check("an empty message is refused", (await call("POST", `/orders/${dp.id}/messages`, { text: "   " }, otherCust.accessToken)).status === 400 && (await call("POST", `/orders/${dp.id}/messages`, { text: "hi" }, vendor.accessToken)).status === 404);
  const c1Chat = await connect(c1.accessToken);
  const join2 = await ack(c1Chat, "chat:join", dp.id);
  const sent = await ack(c1Chat, "chat:send", { orderId: dp.id, text: "On my way" });
  await sleep(400);
  check("the courier joins (history has the customer's message) and sends over the socket; the customer gets it live", join2?.messages?.length === 1 && sent?.ok === true && custChat.events.some((e) => e.ev === "chat:message" && e.data.id === sent.message.id && e.data.text === "On my way" && e.data.senderRole === "COURIER"), [join2, sent]);
  const chatHist = await call("GET", `/orders/${dp.id}/messages`, null, c1.accessToken);
  check("chat history: oldest first, exactly the documented fields", chatHist.status === 200 && chatHist.body.messages.map((m) => m.senderRole).join() === "CUSTOMER,COURIER" && chatHist.body.messages.every((m) => Object.keys(m).sort().join() === "createdAt,id,orderId,senderId,senderRole,text"), chatHist.body);
  check("a courier can only report a problem after pickup", (await call("POST", `/orders/${dp.id}/delivery-problem`, { reason: "CUSTOMER_UNAVAILABLE" }, c1.accessToken)).status === 409);
  await call("PATCH", `/orders/${dp.id}/status`, { status: "SHIPPED" }, c1.accessToken);
  check("only the assigned courier can report it; the reason must be one of the three", (await call("POST", `/orders/${dp.id}/delivery-problem`, { reason: "CUSTOMER_UNAVAILABLE" }, otherCust.accessToken)).status === 403 && (await call("POST", `/orders/${dp.id}/delivery-problem`, { reason: "CUSTOMER_UNAVAILABLE" }, c2.accessToken)).status === 404 && (await call("POST", `/orders/${dp.id}/delivery-problem`, { reason: "RAINING" }, c1.accessToken)).status === 400);
  check("taking it back needs a reported problem first", (await call("POST", `/orders/${dp.id}/return-to-store`, null, c1.accessToken)).status === 409);
  const prob = await call("POST", `/orders/${dp.id}/delivery-problem`, { reason: "CUSTOMER_UNAVAILABLE", note: "Rang the bell twice" }, c1.accessToken);
  const canAt = new Date(prob.body.canReturnAt).getTime();
  check("reporting starts a 10-minute wait (canReturnAt)", prob.status === 200 && Math.abs(canAt - (Date.now() + 10 * 60_000)) < 30_000, prob.body);
  const dpCust = (await call("GET", `/orders/${dp.id}`, null, otherCust.accessToken)).body.order;
  check("the order shows the problem to the customer", !!dpCust?.deliveryProblemAt && dpCust.deliveryProblemReason === "CUSTOMER_UNAVAILABLE", dpCust);
  const prob2 = await call("POST", `/orders/${dp.id}/delivery-problem`, { reason: "WRONG_ADDRESS" }, c1.accessToken);
  check("reporting again keeps the original wait", prob2.status === 200 && prob2.body.canReturnAt === prob.body.canReturnAt && prob2.body.deliveryProblemReason === "WRONG_ADDRESS");
  check("admin System lists the delivery problem", (await call("GET", "/admin/system", null, adminToken)).body.attention?.some((a) => a.startsWith(`Order #${dp.id}: the courier`)));
  check("the courier cannot take it back before the 10 minutes are up", (await call("POST", `/orders/${dp.id}/return-to-store`, null, c1.accessToken)).status === 409);
  sql(`update "Order" set "deliveryProblemAt" = now() - interval '11 minutes' where id=${dp.id}`);
  const stockBack0 = Number(sql(`select "stockQuantity" from "Product" where id=${productId}`));
  check("only the assigned courier takes it back", (await call("POST", `/orders/${dp.id}/return-to-store`, null, c2.accessToken)).status === 404);
  const back = await call("POST", `/orders/${dp.id}/return-to-store`, null, c1.accessToken);
  check("back to the shop: cancelled 'Customer could not be reached', returnedToStoreAt set", back.status === 200 && back.body.order?.status === "CANCELLED" && back.body.order.cancelReason === "Customer could not be reached" && !!back.body.order.returnedToStoreAt, back.body);
  check("the items are refunded (2 × 50 €); delivery fee and tip are not", sql(`select "refundedCents" || '|' || "paymentStatus" from "Order" where id=${dp.id}`) === "10000|SUCCEEDED" && dp.totalCents === 10000 + dp.deliveryFeeCents + 200, sql(`select "refundedCents" || '|' || "paymentStatus" from "Order" where id=${dp.id}`));
  check("the items are back in the store's stock", Number(sql(`select "stockQuantity" from "Product" where id=${productId}`)) === stockBack0 + 2);
  await sleep(900);
  const dpFee = sql(`select "courierFeeCents" from "Order" where id=${dp.id}`);
  check("the courier is paid the job pay and the tip; the store gets no payout", sql(`select "amountCents" from "Payout" where "orderId"=${dp.id} and party='COURIER'`) === dpFee && Number(dpFee) >= 650 + 200 && sql(`select count(*) from "Payout" where "orderId"=${dp.id} and party='STORE'`) === "0", [dpFee, sql(`select party || ':' || "amountCents" || ':' || status from "Payout" where "orderId"=${dp.id}`)]);
  const sysBack = (await call("GET", "/admin/system", null, adminToken)).body.attention || [];
  check("System no longer lists the problem and does not count the kept delivery fee as a missing refund", !sysBack.some((a) => a.startsWith(`Order #${dp.id}:`)) && Number(sql(`select count(*) from "Order" where status='CANCELLED' and "paymentStatus"='SUCCEEDED' and ("returnedToStoreAt" is null or "refundedCents" < greatest(0, least("subtotalCents" - "discountCents", "totalCents")))`)) === Number((sysBack.find((a) => /still need a refund/.test(a)) || "0").match(/\d+/)[0]), sysBack);
  check("taking it back twice is refused; the closed order's chat is closed", (await call("POST", `/orders/${dp.id}/return-to-store`, null, c1.accessToken)).status === 409 && (await call("POST", `/orders/${dp.id}/messages`, { text: "hello?" }, otherCust.accessToken)).status === 409);
  check("only the store confirms it got the items back", (await call("POST", `/orders/${dp.id}/returned-received`, null, otherVendor.accessToken)).status === 404 && (await call("POST", `/orders/${dp.id}/returned-received`, null, otherCust.accessToken)).status === 403 && (await call("POST", `/orders/${scRes.body.order.id}/returned-received`, null, vendor.accessToken)).status === 409);
  const recv = await call("POST", `/orders/${dp.id}/returned-received`, null, vendor.accessToken);
  const vendDp = (await call("GET", "/orders", null, vendor.accessToken)).body.orders?.find((o) => o.id === dp.id);
  check("the store confirms it got the items back; its order list shows both times", recv.status === 200 && !!recv.body.order?.returnReceivedAt && !!vendDp?.returnedToStoreAt && !!vendDp.returnReceivedAt, vendDp);
  // Chat is deleted 30 days after the order is closed (scheduler job "chat-purge", run here directly)
  const chatMod = require(path.join(__dirname, "..", "..", "dist", "modules", "orders", "chat.js"));
  await chatMod.purgeOldMessages();
  const keptMsgs = sql(`select count(*) from "OrderMessage" where "orderId"=${dp.id}`);
  sql(`update "Order" set "cancelledAt" = now() - interval '31 days' where id=${dp.id}`);
  await chatMod.purgeOldMessages();
  check("order chat is kept until 30 days after the order is closed, then deleted", keptMsgs === "2" && sql(`select count(*) from "OrderMessage" where "orderId"=${dp.id}`) === "0", keptMsgs);
  sql(`update "Order" set "cancelledAt" = now() where id=${dp.id}`);
  custChat.close();
  c1Chat.close();
  const an2 = (await call("GET", "/admin/analytics", null, adminToken)).body.totals?.cancelledByReason;
  check("analytics: store cancellations in the store's own words and customers not reached have their own buckets", an2?.store_cancelled >= 1 && an2.customer_unreachable >= 1, an2);

  console.log("\n— Blocking users and reporting reviews (2.10)");
  const liveDrop = (await call("GET", `/stores/${storeId}/drops`)).body.drops?.[0]?.id;
  const pirjoComment = await call("POST", `/drops/${liveDrop}/comments`, { body: "Lovely colours" }, pirjo.accessToken);
  check("comments carry the author's user id", pirjoComment.status === 201 && pirjoComment.body.comment?.authorId === pirjo.user.id, pirjoComment.body);
  check("blocking needs a signed-in user, another real user", (await call("POST", "/me/blocks", { userId: pirjo.user.id })).status === 401 && (await call("POST", "/me/blocks", { userId: otherCust.user.id }, otherCust.accessToken)).status === 400 && (await call("POST", "/me/blocks", { userId: 99999999 }, otherCust.accessToken)).status === 404 && (await call("POST", "/me/blocks", { userId: "x" }, otherCust.accessToken)).status === 400);
  const blk = await call("POST", "/me/blocks", { userId: pirjo.user.id }, otherCust.accessToken);
  const blocks = await call("GET", "/me/blocks", null, otherCust.accessToken);
  check("a customer blocks another user and sees the block list", blk.status === 200 && blk.body.blocked === true && blocks.body.blocks?.some((b) => b.userId === pirjo.user.id && b.name === "Pirjo"), blocks.body);
  const seenByBlocker = (await call("GET", `/drops/${liveDrop}/comments`, null, otherCust.accessToken)).body.comments || [];
  const seenByOthers = (await call("GET", `/drops/${liveDrop}/comments`)).body.comments || [];
  check("the blocked user's comments are hidden for the blocker only", !seenByBlocker.some((c) => c.id === pirjoComment.body.comment?.id) && seenByOthers.some((c) => c.id === pirjoComment.body.comment?.id));
  const pRevOrder = Number(sql(`insert into "Order" ("userId","storeId","status","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","paymentStatus","paidAt","deliveredAt","updatedAt") values (${pirjo.user.id},${storeId},'DELIVERED',5000,300,300,500,4500,5300,'SUCCEEDED',now(),now(),now()) returning id`).split("\n")[0]);
  const pRev = await call("POST", `/orders/${pRevOrder}/review`, { storeRating: 2, comment: "Slow to answer" }, pirjo.accessToken);
  const revBlocker = (await call("GET", `/stores/${storeId}/reviews`, null, otherCust.accessToken)).body.reviews || [];
  const revPublic = (await call("GET", `/stores/${storeId}/reviews`)).body.reviews || [];
  check("reviews carry authorId; the blocked user's reviews are hidden for the blocker only", pRev.status === 201 && !revBlocker.some((r) => r.id === pRev.body.review.id) && revPublic.some((r) => r.id === pRev.body.review.id && r.authorId === pirjo.user.id), revPublic.slice(0, 2));
  const unblk = await call("DELETE", `/me/blocks/${pirjo.user.id}`, null, otherCust.accessToken);
  check("unblocking shows them again", unblk.status === 200 && unblk.body.blocked === false && (await call("GET", `/stores/${storeId}/reviews`, null, otherCust.accessToken)).body.reviews.some((r) => r.id === pRev.body.review.id));
  check("you cannot report your own review; a reason is needed", (await call("POST", `/reviews/${pRev.body.review.id}/report`, { reason: "SPAM" }, pirjo.accessToken)).status === 400 && (await call("POST", `/reviews/${pRev.body.review.id}/report`, {}, otherCust.accessToken)).status === 400 && (await call("POST", `/reviews/${pRev.body.review.id}/report`, { reason: "SPAM" })).status === 401);
  const repRev = await call("POST", `/reviews/${pRev.body.review.id}/report`, { reason: "HARASSMENT" }, otherCust.accessToken);
  await call("POST", `/reviews/${pRev.body.review.id}/report`, { reason: "SPAM" }, commentStranger.accessToken);
  const reported = await call("GET", "/admin/reviews/reported", null, adminToken);
  const rr = reported.body.reviews?.find((r) => r.id === pRev.body.review.id);
  check("admins see reported reviews with their reasons; others cannot", repRev.status === 200 && rr?.reportCount === 2 && rr.reports.length === 2 && (await call("GET", "/admin/reviews/reported", null, otherCust.accessToken)).status === 403, reported.body);
  check("System asks an admin to look at reported reviews", (await call("GET", "/admin/system", null, adminToken)).body.attention?.some((a) => /reported review/.test(a)));
  check("resolving needs hide or keep", (await call("POST", `/admin/reviews/${pRev.body.review.id}/resolve`, { action: "delete" }, adminToken)).status === 400 && (await call("POST", `/admin/reviews/${pRev.body.review.id}/resolve`, { action: "hide" }, otherCust.accessToken)).status === 403);
  const hid = await call("POST", `/admin/reviews/${pRev.body.review.id}/resolve`, { action: "hide" }, adminToken);
  check("the admin hides the review: gone from the store page and the reported list", hid.status === 200 && hid.body.review?.isHidden === true && !(await call("GET", `/stores/${storeId}/reviews`)).body.reviews.some((r) => r.id === pRev.body.review.id) && !(await call("GET", "/admin/reviews/reported", null, adminToken)).body.reviews.some((r) => r.id === pRev.body.review.id));

  console.log("\n— Approval messages, account deletion clean-up, legal pages (2.10)");
  const aaro = await register("Aaro", "COURIER");
  const aaroCourier = (await call("GET", "/admin/couriers", null, adminToken)).body.couriers.find((c) => c.user?.id === aaro.user.id);
  const ap1 = await call("PATCH", `/admin/couriers/${aaroCourier.id}/approve`, null, adminToken);
  const ap2 = await call("PATCH", `/admin/couriers/${aaroCourier.id}/approve`, null, adminToken);
  check("approving a courier sends 'You're approved' (push and email) once", ap1.status === 200 && ap1.body.approvalSent === true && ap2.body.approvalSent === false, [ap1.body.approvalSent, ap2.body.approvalSent]);
  const vilja = await register("Vilja", "VENDOR");
  const viljaStore = (await call("POST", "/stores", { name: `Vilja Vintage ${uniq}`, category: "THRIFT", sellerType: "PRIVATE", latitude: 60.17, longitude: 24.94 }, vilja.accessToken)).body.store;
  const sp1 = await call("PATCH", `/admin/vendors/${viljaStore.id}/approve`, null, adminToken);
  const sp2 = await call("PATCH", `/admin/vendors/${viljaStore.id}/approve`, null, adminToken);
  check("approving a store sends 'You're approved' once", sp1.body.approvalSent === true && sp2.body.approvalSent === false, [sp1.body, sp2.body.approvalSent]);
  const viljaDel = await call("DELETE", "/auth/me", null, vilja.accessToken);
  await sleep(700);
  const destroyedNow = await (await fetch("http://localhost:12222/__destroyed")).json();
  check("deleting a store account deletes its media on Cloudinary (products, store pictures, drops, avatar)", viljaDel.status === 200 && [`prefix:malvoya/products/s${viljaStore.id}/`, `prefix:malvoya/stores/s${viljaStore.id}/`, `prefix:malvoya/drops/s${viljaStore.id}/`, `prefix:malvoya/avatars/u${vilja.user.id}/`].every((p) => destroyedNow.includes(p)), destroyedNow.filter((d) => String(d).startsWith("prefix:")));
  check("a deleted account's token stops working at once", (await call("GET", "/me", null, vilja.accessToken)).status === 401);
  const delPage = await fetch(`${BASE}/legal/delete-account`);
  const delHtml = await delPage.text();
  check("the account deletion page is published and listed with the legal documents", delPage.status === 200 && delHtml.includes("Delete your Malvoya account") && delHtml.includes("Malvoya Courier") && (await (await fetch(`${BASE}/legal/terms`)).text()).includes('href="/legal/delete-account"'));
  check("/legal/vendor-terms opens the seller terms", (await fetch(`${BASE}/legal/vendor-terms`)).status === 200 && (await (await fetch(`${BASE}/legal/vendor-terms`)).text()).includes("Seller Terms"));
  check("the customer terms explain what happens when the courier cannot reach you", (await (await fetch(`${BASE}/legal/terms`)).text()).includes("If the courier cannot reach you at the address"));

  console.log("\n— Signed statement links (2.10)");
  const stLink = await call("GET", `/stores/my/statements/${month}/link`, null, stinaV.accessToken);
  check("the store gets a 10-minute link to its printable statement", stLink.status === 200 && stLink.body.url.startsWith(`${BASE}/api/v1/stores/statements/${stina.id}/${month}.html?exp=`) && Math.abs(new Date(stLink.body.expiresAt).getTime() - Date.now() - 600_000) < 30_000, stLink.body);
  const stPage = await fetch(stLink.body.url);
  const stPageHtml = await stPage.text();
  check("the link opens the statement in a normal browser (no token)", stPage.status === 200 && stPageHtml.includes("Statement — not a VAT invoice") && stPageHtml.includes(`#${sA}`) && (stPage.headers.get("content-security-policy") || "").startsWith("default-src 'none'"));
  const badSig = await fetch(stLink.body.url.replace(/sig=[^&]+/, "sig=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"));
  const otherStore = await fetch(stLink.body.url.replace(`/statements/${stina.id}/`, `/statements/${paula.id}/`));
  const otherMonth = await fetch(stLink.body.url.replace(`/${month}.html`, "/2025-01.html"));
  check("a changed signature, store or month is refused (403)", badSig.status === 403 && otherStore.status === 403 && otherMonth.status === 403);
  const linkKey = crypto.createHmac("sha256", testEnv.JWT_SECRET).update("malvoya:statement-link:v1").digest();
  const oldExp = Math.floor(Date.now() / 1000) - 60;
  const oldSig = crypto.createHmac("sha256", linkKey).update(`statement|${stina.id}|${month}|${oldExp}`).digest("base64url");
  const expired = await fetch(`${API}/stores/statements/${stina.id}/${month}.html?exp=${oldExp}&sig=${oldSig}`);
  check("an expired link is refused and says so", expired.status === 403 && /expired/.test(await expired.text()));
  check("statement links are the store owner's; the month is validated", (await call("GET", `/stores/my/statements/${month}/link`, null, otherCust.accessToken)).status === 403 && (await call("GET", "/stores/my/statements/2026-13/link", null, stinaV.accessToken)).status === 400);

  console.log("\n— DAC7 reminders (2.10)");
  const rasmus = await register("Rasmus", "VENDOR");
  const rStore = (await call("POST", "/stores", { name: `Rasmus Retro ${uniq}`, category: "THRIFT", sellerType: "PRIVATE", latitude: 60.17, longitude: 24.94 }, rasmus.accessToken)).body.store;
  await call("PATCH", `/admin/vendors/${rStore.id}/approve`, null, adminToken);
  sql(`insert into "Order" ("userId","storeId","status","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","paymentStatus","paidAt","deliveredAt","updatedAt") values (${otherCust.user.id},${rStore.id},'DELIVERED',3000,300,300,300,2700,3300,'SUCCEEDED',now(),now(),now())`);
  const reminders = require(path.join(__dirname, "..", "..", "dist", "modules", "sellers", "taxReminders.js"));
  const remCount = () => sql(`select "taxReminderCount" || '|' || coalesce("taxReminderYear"::text, '-') from "Store" where id=${rStore.id}`);
  const thisYear = hel().date.slice(0, 4);
  await reminders.sendTaxInfoReminders();
  check("a store with sales and no tax details is reminded (push and email)", remCount() === `1|${thisYear}`, remCount());
  await reminders.sendTaxInfoReminders();
  check("…at most once every 30 days", remCount() === `1|${thisYear}`);
  sql(`update "Store" set "taxReminderAt" = now() - interval '31 days' where id=${rStore.id}`);
  await reminders.sendTaxInfoReminders();
  sql(`update "Store" set "taxReminderAt" = now() - interval '31 days' where id=${rStore.id}`);
  await reminders.sendTaxInfoReminders();
  check("…and at most twice a year; stores with complete details are never reminded", remCount() === `2|${thisYear}` && sql(`select "taxReminderCount" from "Store" where id=${stina.id}`) === "0", remCount());

  console.log("\n— Legal versions, acceptance records, business check and onboarding (2.11)");
  { // own scope: the 2.11 checks reuse short names
  const waitFor = async (fn, ms = 8000) => { const end = Date.now() + ms; let v; while (Date.now() < end) { v = await fn(); if (v) return v; await sleep(200); } return v; };
  const verTerms = await (await fetch(`${BASE}/legal/terms/versions`)).json();
  check("each legal document has its first version on record, effective now", verTerms.ok && verTerms.versions.length === 1 && verTerms.versions[0].status === "current" && /^terms_of_service@[0-9a-f]{12}$/.test(verTerms.currentVersion) && verTerms.pendingVersion === null && verTerms.versions[0].url.includes("/legal/terms/v/"), verTerms);
  const verSell = await (await call("GET", "/legal/sellers/versions")).body;
  const sellV1 = verSell.currentVersion;
  check("the versions list answers to the page names too (and under /api/v1)", verSell.doc === "seller-terms" && /^vendor_terms@/.test(sellV1) && (await fetch(`${BASE}/legal/vendor-terms/versions`)).status === 200);
  const exactPage = await fetch(`${BASE}/legal/sellers/v/${encodeURIComponent(sellV1)}`);
  const exactHtml = await exactPage.text();
  check("GET /legal/:doc/v/:version renders that exact stored text", exactPage.status === 200 && exactHtml.includes("Seller Terms") && exactHtml.includes(sellV1) && (exactPage.headers.get("content-security-policy") || "").startsWith("default-src 'none'"));
  check("unknown versions and documents are 404", (await fetch(`${BASE}/legal/terms/v/terms_of_service@000000000000`)).status === 404 && (await fetch(`${BASE}/legal/nope/versions`)).status === 404);
  check("the public page shows the version in force", (await (await fetch(`${BASE}/legal/terms`)).text()).includes(verTerms.currentVersion));

  // Registration writes the acceptance records (customer: terms + privacy acknowledgement)
  const lauriReg = await call("POST", "/auth/register", { name: "Lauri", email: `lauri${uniq}@example.fi`, password: "strong-pass-123", acceptTerms: true }, null, { headers: { "X-App-Version": "1.8.0+10", "User-Agent": "MalvoyaCustomer/1.8.0 " + "x".repeat(300) } });
  const lauri = lauriReg.body;
  const lauriAg = (await call("GET", "/me/agreements", null, lauri.accessToken)).body;
  check("registering with acceptTerms records terms + privacy for a customer", lauriAg.ok && lauriAg.required.map((r) => r.doc).join(",") === "terms,privacy" && lauriAg.required.every((r) => r.accepted && r.acceptedAt && r.currentVersion && r.url && r.title?.fi) && lauriAg.history.length === 2 && lauriAg.history.every((h) => h.method === "register"), lauriAg);
  const lauriRow = sql(`select ip || '|' || length("userAgent") || '|' || "appVersion" from "AgreementAcceptance" where "userId"=${lauri.user.id} and doc='terms'`);
  check("the record keeps a truncated IP (/24), at most 200 chars of user agent and the app version", /^10\.9\.\d+\.0\/24\|200\|1\.8\.0\+10$/.test(lauriRow), lauriRow);
  check("termsVersion still matches the accepted version", sql(`select "termsVersion" from "User" where id=${lauri.user.id}`) === verTerms.currentVersion);
  const pekka = await register("Pekka Testi", "VENDOR");
  const pekkaAg = (await call("GET", "/me/agreements", null, pekka.accessToken)).body;
  check("a store accepts the seller terms; the privacy notice is listed as a non-blocking acknowledgement", pekkaAg.required[0]?.doc === "seller-terms" && pekkaAg.required[0].accepted === true && pekkaAg.required[0].blocking === true && pekkaAg.required[1]?.doc === "privacy" && pekkaAg.required[1].accepted === false && pekkaAg.required[1].blocking === false, pekkaAg.required);
  const expData = (await call("GET", "/auth/me/data", null, lauri.accessToken)).body;
  check("acceptance records are part of the data export", expData.data?.agreementAcceptances?.length === 2);

  // Backfill: 2.10 accounts that only have termsVersion get a record for exactly that version (migration SQL)
  const helmi = await register("Helmi");
  sql(`delete from "AgreementAcceptance" where "userId"=${helmi.user.id}; update "User" set "termsVersion"='terms_of_service@0123456789ab' where id=${helmi.user.id}`);
  const migSql = fs.readFileSync(path.join(__dirname, "..", "..", "prisma", "migrations", fs.readdirSync(path.join(__dirname, "..", "..", "prisma", "migrations")).find((d) => d.endsWith("_agreements_onboarding")), "migration.sql"), "utf8");
  sql(migSql.slice(migSql.indexOf('INSERT INTO "AgreementAcceptance"')));
  check("existing users with only termsVersion are backfilled as accepted for that version", sql(`select doc || '|' || version || '|' || method from "AgreementAcceptance" where "userId"=${helmi.user.id}`) === "terms|terms_of_service@0123456789ab|register");
  const helmi428 = await call("POST", "/orders", {}, helmi.accessToken);
  check("…and must accept the version in force before ordering (428 AGREEMENT_REQUIRED)", helmi428.status === 428 && helmi428.body.code === "AGREEMENT_REQUIRED" && helmi428.body.doc === "terms" && helmi428.body.version === verTerms.currentVersion && /changed/.test(helmi428.body.error), helmi428.body);

  // Accepting in the app
  const sanni = await register("Sanni", undefined, { acceptTerms: false });
  const sanni428 = await call("POST", "/orders", {}, sanni.accessToken);
  check("an account that never accepted (e.g. social sign-up) cannot order (428)", sanni428.status === 428 && sanni428.body.code === "AGREEMENT_REQUIRED" && /accept/.test(sanni428.body.error) && sanni428.body.url.includes("/legal/terms/v/"), sanni428.body);
  check("428 also guards rentals; quotes and reading stay open", (await call("POST", "/rentals", {}, sanni.accessToken)).status === 428 && (await call("POST", "/orders/quote", {}, sanni.accessToken)).status !== 428 && (await call("GET", "/orders", null, sanni.accessToken)).status === 200 && (await call("GET", "/auth/me/data", null, sanni.accessToken)).status === 200);
  check("only the current or the announced version can be accepted (409)", (await call("POST", "/me/agreements/accept", { doc: "terms", version: "terms_of_service@000000000000" }, sanni.accessToken)).status === 409);
  check("a customer cannot accept the seller terms (400)", (await call("POST", "/me/agreements/accept", { doc: "seller-terms", version: sellV1 }, sanni.accessToken)).status === 400);
  const acc1 = await call("POST", "/me/agreements/accept", { doc: "terms", version: verTerms.currentVersion }, sanni.accessToken, { headers: { "X-App-Version": "1.8.0+10" } });
  const acc2 = await call("POST", "/me/agreements/accept", { doc: "terms", version: verTerms.currentVersion }, sanni.accessToken);
  check("accepting records it and emails a copy", acc1.status === 201 && acc1.body.alreadyAccepted === false && acc1.body.emailed === true && acc1.body.acceptance?.method === "in_app" && acc1.body.acceptance.copyUrl.endsWith(`/me/agreements/${acc1.body.acceptance.id}/copy`), acc1.body);
  check("accepting again is idempotent (same record, no second email)", acc2.status === 200 && acc2.body.alreadyAccepted === true && acc2.body.acceptance.id === acc1.body.acceptance.id && acc2.body.emailed === false && sql(`select count(*) from "AgreementAcceptance" where "userId"=${sanni.user.id}`) === "1");
  check("after accepting, ordering is no longer refused for the agreement", (await call("POST", "/orders", {}, sanni.accessToken)).status === 400);
  const copyId = acc1.body.acceptance.id;
  const copyRes = await fetch(`${API}/me/agreements/${copyId}/copy`, { headers: { Authorization: `Bearer ${sanni.accessToken}` } });
  const copyHtml = await copyRes.text();
  check("the copy shows the account, version, time and the full accepted text", copyRes.status === 200 && copyHtml.includes("Your copy: Terms of Service") && copyHtml.includes(verTerms.currentVersion) && copyHtml.includes(`sanni${uniq}@example.fi`) && copyHtml.includes("Right of withdrawal") && copyHtml.includes("1.8.0+10") && copyRes.headers.get("cache-control") === "private, no-store");
  check("copies are the owner's only (404 for others, 401 without a token)", (await call("GET", `/me/agreements/${copyId}/copy`, null, lauri.accessToken)).status === 404 && (await call("GET", `/me/agreements/${copyId}/copy`, null, adminToken)).status === 404 && (await fetch(`${API}/me/agreements/${copyId}/copy`)).status === 401);
  const copyLink = await call("GET", `/me/agreements/${copyId}/copy/link`, null, sanni.accessToken);
  check("a signed 10-minute link opens the copy without a token", copyLink.status === 200 && copyLink.body.url.startsWith(`${BASE}/api/v1/agreements/copy/${copyId}.html?exp=`) && Math.abs(new Date(copyLink.body.expiresAt).getTime() - Date.now() - 600_000) < 30_000 && (await fetch(copyLink.body.url)).status === 200, copyLink.body);
  check("a changed signature or record id is refused (403); links are the owner's", (await fetch(copyLink.body.url.replace(/sig=[^&]+/, "sig=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))).status === 403 && (await fetch(copyLink.body.url.replace(`/copy/${copyId}.html`, `/copy/${copyId + 1}.html`))).status === 403 && (await call("GET", `/me/agreements/${copyId}/copy/link`, null, lauri.accessToken)).status === 404);

  // Business check (PRH/YTJ mock)
  const badY = await call("POST", "/stores", { name: `Bad Y ${uniq}`, category: "APPAREL", sellerType: "BUSINESS", businessId: "1234567-8" }, pekka.accessToken);
  check("a Y-tunnus with a wrong check digit is refused (400)", badY.status === 400 && /not valid/.test(badY.body.error || JSON.stringify(badY.body)), badY.body);
  const pekkaStore = (await call("POST", "/stores", { name: "Testi Kauppa", category: "APPAREL", sellerType: "BUSINESS", businessId: "7654321-2", address: "Testikatu 1, Helsinki", phone: "+358401111111", latitude: 60.17, longitude: 24.94 }, pekka.accessToken)).body.store;
  const vendorRow = async (id) => (await call("GET", "/admin/vendors", null, adminToken)).body.stores?.find((x) => x.id === id);
  const pekkaCheck = await waitFor(async () => { const v = await vendorRow(pekkaStore.id); return v?.businessCheck?.verificationStatus ? v.businessCheck : null; });
  check("saving a Y-tunnus looks it up in PRH: matched, registered name and date shown to the admin", pekkaCheck?.verificationStatus === "matched" && pekkaCheck.registeredName === "Testi Kauppa Oy" && String(pekkaCheck.registeredAt).startsWith("2015-03-01") && !!pekkaCheck.checkedAt, pekkaCheck);
  check("the check never approves the store", (await vendorRow(pekkaStore.id))?.isVerified === false);
  check("the lookup used the PRH v3 companies endpoint on the test host", prhRequests.includes("/opendata-ytj-api/v3/companies?businessId=7654321-2"), prhRequests);
  const toini = await register("Toini", "VENDOR");
  const toiniStore = (await call("POST", "/stores", { name: "Aivan Muu Puoti", category: "APPAREL", sellerType: "BUSINESS", businessId: "7654321-2" }, toini.accessToken)).body.store;
  const toiniCheck = await waitFor(async () => (await vendorRow(toiniStore.id))?.businessCheck?.verificationStatus);
  check("a different name is flagged name_mismatch (and the answer came from the cache)", toiniCheck === "name_mismatch" && prhRequests.filter((r) => r.endsWith("7654321-2")).length === 1, [toiniCheck, prhRequests]);
  const kerttu = await register("Kerttu", "VENDOR");
  const kStore = (await call("POST", "/stores", { name: "Testi Lopetettu", category: "APPAREL", sellerType: "BUSINESS", businessId: "1112223-0" }, kerttu.accessToken)).body.store;
  const veikko = await register("Veikko", "VENDOR");
  const vStore = (await call("POST", "/stores", { name: "Ei Rekisterissä", category: "APPAREL", sellerType: "BUSINESS", businessId: "5555555-6" }, veikko.accessToken)).body.store;
  const iiro = await register("Iiro", "VENDOR");
  const iStore = (await call("POST", "/stores", { name: "Iiro Ateljee", category: "APPAREL", sellerType: "BUSINESS", businessId: "9876543-0" }, iiro.accessToken)).body.store;
  const aarne = await register("Aarne", "VENDOR");
  const aStore = (await call("POST", "/stores", { name: "Aarnen Kirpputori", category: "THRIFT", sellerType: "PRIVATE" }, aarne.accessToken)).body.store;
  const kChk = await waitFor(async () => (await vendorRow(kStore.id))?.businessCheck?.verificationStatus);
  const vChk = await waitFor(async () => (await vendorRow(vStore.id))?.businessCheck?.verificationStatus);
  const iChk = await waitFor(async () => (await vendorRow(iStore.id))?.businessCheck?.verificationStatus);
  check("ceased companies are inactive, unknown IDs not_found, an outage unavailable", kChk === "inactive" && vChk === "not_found" && iChk === "unavailable", [kChk, vChk, iChk]);
  const recheck = await call("POST", `/admin/vendors/${iStore.id}/business-check`, null, adminToken);
  check("the admin can run the check again (current name only, old names ignored)", recheck.status === 200 && recheck.body.businessCheck?.verificationStatus === "matched" && recheck.body.businessCheck.registeredName === "Iiro Ateljee Oy", recheck.body);
  const aRow = await vendorRow(aStore.id);
  check("private sellers skip the check (and the admin re-check says so)", aRow?.businessCheck?.required === false && aRow.businessCheckStatus === null && (await call("POST", `/admin/vendors/${aStore.id}/business-check`, null, adminToken)).status === 409);
  check("the store app sees its own check result", (await call("GET", "/stores/my", null, pekka.accessToken)).body.store?.businessCheck?.verificationStatus === "matched");

  // Onboarding checklists
  let ob = (await call("GET", "/stores/my/onboarding", null, pekka.accessToken)).body;
  check("store onboarding lists the steps in order with titles and actions", ob.ok && ob.steps.map((s) => s.key).join(",") === "details,map_pin,hours,payouts,first_product,tax_info,agreement,safety_pledge,business_check" && ob.steps.every((s) => s.title?.en && s.title?.fi && s.action) && ob.readyForApproval === false && ob.percent === 44, ob);
  await call("PATCH", `/stores/${pekkaStore.id}`, { openingHours: { mon: [["09:00", "18:00"]], tue: [["09:00", "18:00"]] } }, pekka.accessToken);
  // A draft counts as the first product (publishing needs the category data, 2.12)
  await call("POST", "/products", { name: "Testi paita", category: "Shirt", salePriceCents: 2500, stockQuantity: 1, images: [ownImage(pekkaStore.id, "paita")], isAvailable: false }, pekka.accessToken);
  await call("POST", "/stores/my/safety-pledge", { accept: true }, pekka.accessToken);
  await call("PUT", "/stores/my/tax-info", { legalName: "Testi Kauppa Oy", addressLine: "Testikatu 1", postalCode: "00100", city: "Helsinki", country: "fi" }, pekka.accessToken);
  ob = (await call("GET", "/stores/my/onboarding", null, pekka.accessToken)).body;
  check("steps turn done as the store completes them (payouts still missing)", ob.steps.filter((s) => !s.done).map((s) => s.key).join(",") === "payouts" && ob.readyForApproval === false && sql(`select "readyForApprovalAt" is null from "Store" where id=${pekkaStore.id}`) === "t", ob.steps);
  sql(`update "Store" set "payoutsEnabled"=true where id=${pekkaStore.id}`);
  ob = (await call("GET", "/stores/my/onboarding", null, pekka.accessToken)).body;
  const readyAt1 = sql(`select "readyForApprovalAt" from "Store" where id=${pekkaStore.id}`);
  check("everything but approval done: ready for approval, admin told once", ob.percent === 100 && ob.readyForApproval === true && ob.approved === false && readyAt1 !== "");
  await call("GET", "/stores/my/onboarding", null, pekka.accessToken);
  check("…only once (the time is not reset)", sql(`select "readyForApprovalAt" from "Store" where id=${pekkaStore.id}`) === readyAt1);
  const aOb = (await call("GET", "/stores/my/onboarding", null, aarne.accessToken)).body;
  check("a private seller's business check step is skipped (done)", aOb.steps.find((s) => s.key === "business_check")?.done === true && aOb.steps.find((s) => s.key === "business_check")?.skipped === true);
  const onni = await register("Onni", "COURIER");
  let cob = (await call("GET", "/courier/me/onboarding", null, onni.accessToken)).body;
  check("courier onboarding lists profile, vehicle, payouts, agreement, location disclosure, approval", cob.ok && cob.steps.map((s) => s.key).join(",") === "profile,vehicle,payouts,agreement,location_disclosure,approved" && cob.steps.find((s) => s.key === "agreement").done === true && cob.readyForApproval === false, cob);
  check("vehicle types are validated (400)", (await call("PATCH", "/courier/me", { vehicleType: "rocket" }, onni.accessToken)).status === 400);
  const setV = await call("PATCH", "/courier/me", { vehicleType: "ebike", phone: "+358 40 222 3333" }, onni.accessToken);
  check("the courier sets vehicle and phone", setV.status === 200 && setV.body.courier.vehicleType === "ebike");
  check("the location disclosure must be confirmed explicitly (400 otherwise)", (await call("POST", "/courier/me/disclosures", { locationDisclosure: false }, onni.accessToken)).status === 400);
  const disc1 = await call("POST", "/courier/me/disclosures", { locationDisclosure: true }, onni.accessToken);
  const disc2 = await call("POST", "/courier/me/disclosures", { locationDisclosure: true }, onni.accessToken);
  check("the disclosure acknowledgement is recorded once", disc1.status === 200 && !!disc1.body.locationDisclosureAt && disc2.body.locationDisclosureAt === disc1.body.locationDisclosureAt);
  sql(`update "Courier" set "payoutsEnabled"=true where "userId"=${onni.user.id}`);
  cob = (await call("GET", "/courier/me/onboarding", null, onni.accessToken)).body;
  check("courier ready for approval when everything but approval is done", cob.readyForApproval === true && cob.approved === false && cob.percent === 83 && sql(`select "readyForApprovalAt" is not null from "Courier" where "userId"=${onni.user.id}`) === "t", cob);
  const sys211 = (await call("GET", "/admin/system", null, adminToken)).body;
  check("System lists them as ready for approval", sys211.version === "2.13.0" && sys211.attention.some((a) => a.includes(`(#${pekkaStore.id}) is ready for approval`)) && sys211.attention.some((a) => a.includes("Courier \"Onni\"") && a.includes("ready for approval")) && sys211.readyForApproval?.stores?.some((s) => s.id === pekkaStore.id), sys211.attention);
  check("admin courier list shows vehicle, disclosure and readiness", (await call("GET", "/admin/couriers", null, adminToken)).body.couriers?.find((c) => c.user?.id === onni.user.id)?.vehicleType === "ebike");

  // Publishing changes (second instance reading a copy of the legal texts, same database)
  const legalTmp = fs.mkdtempSync(path.join(require("os").tmpdir(), "malvoya-legal-"));
  for (const f of fs.readdirSync(path.join(__dirname, "..", "..", "..", "legal"))) if (f.endsWith(".md")) fs.copyFileSync(path.join(__dirname, "..", "..", "..", "legal", f), path.join(legalTmp, f));
  const changeText = (file, n) => fs.appendFileSync(path.join(legalTmp, file), `\n\nTest change ${n} (e2e only).\n`);
  check("second instance with a copy of the legal texts starts", await startFeeApi({ LEGAL_DIR: legalTmp }));
  const pub = (doc, body) => callAt(FEE_API, "POST", `/admin/legal/${doc}/publish`, body, adminToken);
  const inDays = (d) => new Date(Date.now() + d * 86_400_000 + 60_000).toISOString();
  const summ = { summaryEn: "Clearer rules for returns and payouts.", summaryFi: "Selkeämmät säännöt palautuksille ja tilityksille." };
  check("publishing an unchanged text is refused (409)", (await pub("terms", { effectiveAt: inDays(0), ...summ })).status === 409);
  check("only admins publish", (await callAt(FEE_API, "POST", "/admin/legal/terms/publish", { effectiveAt: inDays(0), ...summ }, pekka.accessToken)).status === 403);
  changeText("vendor_terms.md", 1);
  const short = await pub("seller-terms", { effectiveAt: inDays(3), ...summ });
  check("seller terms need at least 15 days' notice (P2B) (400 NOTICE_TOO_SHORT)", short.status === 400 && short.body.code === "NOTICE_TOO_SHORT" && short.body.minNoticeDays === 15, short.body);
  changeText("courier_agreement.md", 1);
  check("the courier agreement needs 15 days too", (await pub("courier-agreement", { effectiveAt: inDays(10), ...summ })).body.code === "NOTICE_TOO_SHORT");
  check("a legal obligation needs a reason (400)", (await pub("seller-terms", { effectiveAt: inDays(0), ...summ, legalObligation: true })).status === 400);
  check("summaries in both languages are required (400)", (await pub("seller-terms", { effectiveAt: inDays(16), summaryEn: "x", summaryFi: "y" })).status === 400);
  const pubSell = await pub("seller-terms", { effectiveAt: inDays(16), ...summ });
  check("seller terms with 16 days' notice are published as pending", pubSell.status === 201 && pubSell.body.version.noticeDays === 16 && pubSell.body.notifying >= 1 && /^vendor_terms@/.test(pubSell.body.version.version) && pubSell.body.version.version !== sellV1, pubSell.body);
  const sellV2 = pubSell.body.version.version;
  const notified = await waitFor(async () => { const n = Number(sql(`select "notifiedCount" from "LegalVersion" where version='${sellV2}'`)); return n >= 5 ? n : 0; }, 20000);
  check("every store is told (push + email in their language)", Number(notified) >= 5, notified);
  const vers2 = (await callAt(FEE_API, "GET", "/legal/seller-terms/versions")).body;
  check("the versions list shows the pending one; the old one stays current", vers2.currentVersion === sellV1 && vers2.pendingVersion === sellV2 && vers2.versions.find((v) => v.version === sellV2)?.status === "pending" && vers2.versions.find((v) => v.version === sellV2)?.summary?.fi === summ.summaryFi);
  const pendAg = (await callAt(FEE_API, "GET", "/me/agreements", null, toini.accessToken)).body.required[0];
  check("GET /me/agreements shows the pending version, its date, summary and the right to terminate before it", pendAg.pendingVersion === sellV2 && !!pendAg.pendingEffectiveAt && pendAg.summary?.en === summ.summaryEn && pendAg.canTerminateBefore === pendAg.pendingEffectiveAt && pendAg.accepted === true && pendAg.pendingAccepted === false, pendAg);
  changeText("vendor_terms.md", 2);
  check("a second change while one is announced is refused (409)", (await pub("seller-terms", { effectiveAt: inDays(20), ...summ })).status === 409);
  const adminLegal = (await callAt(FEE_API, "GET", "/admin/legal", null, adminToken)).body;
  const aSell = adminLegal.docs?.find((d) => d.doc === "seller-terms");
  check("admin Legal lists documents, versions, notice rules, acceptance counts and the unpublished file change", adminLegal.docs?.length === 4 && aSell.minNoticeDays === 15 && aSell.versions.length === 2 && aSell.versions.find((v) => v.version === sellV1).acceptances >= 5 && aSell.unpublishedChange === true && aSell.pendingVersion === sellV2, aSell);
  check("System says the repository text changed but is not published", (await callAt(FEE_API, "GET", "/admin/system", null, adminToken)).body.attention.some((a) => a.startsWith("Seller Terms: the text in the repository has changed")));
  check("the announced version can be accepted early", (await callAt(FEE_API, "POST", "/me/agreements/accept", { doc: "seller-terms", version: sellV2 }, pekka.accessToken)).status === 201);
  check("before it takes effect nothing is blocked", (await callAt(FEE_API, "POST", "/products", { name: "Ennen", category: "Shirt", salePriceCents: 1000, images: [] }, toini.accessToken)).status !== 428);
  // Time passes: the announced version takes effect
  sql(`update "LegalVersion" set "effectiveAt" = now() - interval '1 second' where version='${sellV2}'`);
  await sleep(10_500); // version cache (10 s)
  const sell428 = await callAt(FEE_API, "POST", "/products", { name: "Jälkeen", category: "Shirt", salePriceCents: 1000, images: [] }, toini.accessToken);
  check("once in effect, a store that has not accepted cannot publish products (428)", sell428.status === 428 && sell428.body.code === "AGREEMENT_REQUIRED" && sell428.body.doc === "seller-terms" && sell428.body.version === sellV2, sell428.body);
  check("…nor accept orders (428); drafts, reading, payouts and support stay open", (await callAt(FEE_API, "PATCH", "/orders/999999/status", { status: "CONFIRMED" }, toini.accessToken)).status === 428 && (await callAt(FEE_API, "POST", "/products", { name: "Luonnos", category: "Shirt", salePriceCents: 1000, images: [], isAvailable: false }, toini.accessToken)).status !== 428 && (await callAt(FEE_API, "GET", "/stores/my", null, toini.accessToken)).status === 200 && (await callAt(FEE_API, "GET", "/payouts", null, toini.accessToken)).status !== 428 && (await callAt(FEE_API, "GET", "/auth/me/data", null, toini.accessToken)).status === 200);
  check("the store that accepted early is not blocked", (await callAt(FEE_API, "POST", "/products", { name: "Hyväksytty", category: "Shirt", salePriceCents: 1000, images: [] }, pekka.accessToken)).status !== 428);
  check("the page now shows the new version", (await (await fetch(`${FEE_BASE}/legal/sellers`)).text()).includes(sellV2));
  // Required by law: shorter notice, reason audited
  changeText("courier_agreement.md", 2);
  const pubCour = await pub("courier-agreement", { effectiveAt: new Date().toISOString(), ...summ, legalObligation: true, reason: "Platform Work Directive transposition requires new wording now" });
  check("a change required by law may take effect at once, with the reason in the audit log", pubCour.status === 201 && pubCour.body.version.legalObligation === true && sql(`select action || '|' || ("newValue"->>'reason') from "AdminAuditLog" where entity='LegalVersion' and "entityId"=${pubCour.body.version.id}`) === "legal.publish.legal_obligation|Platform Work Directive transposition requires new wording now");
  const cOn = await callAt(FEE_API, "POST", "/courier/status", { isOnline: true, latitude: 60.17, longitude: 24.94 }, c1.accessToken);
  check("a courier who has not accepted cannot go online or take jobs (428); going offline works", cOn.status === 428 && cOn.body.doc === "courier-agreement" && (await callAt(FEE_API, "PATCH", "/orders/999999/assign-courier", null, c1.accessToken)).status === 428 && (await callAt(FEE_API, "POST", "/courier/status", { isOnline: false }, c1.accessToken)).status === 200, cOn.body);
  await callAt(FEE_API, "POST", "/me/agreements/accept", { doc: "courier-agreement", version: pubCour.body.version.version }, c1.accessToken);
  check("after accepting, the courier can go online again", (await callAt(FEE_API, "POST", "/courier/status", { isOnline: false }, c1.accessToken)).status === 200 && (await callAt(FEE_API, "POST", "/courier/status", { isOnline: true }, c1.accessToken)).status === 200);
  await callAt(FEE_API, "POST", "/courier/status", { isOnline: false }, c1.accessToken);
  // Customer terms: no minimum, announced; customers on the old version must accept before ordering
  changeText("terms_of_service.md", 1);
  const pubTerms = await pub("terms", { effectiveAt: new Date().toISOString(), ...summ });
  const lauri428 = await callAt(FEE_API, "POST", "/orders", {}, lauri.accessToken);
  check("customer terms may take effect at once (0 days) and then block ordering until accepted", pubTerms.status === 201 && pubTerms.body.version.noticeDays === 0 && lauri428.status === 428 && /have changed/.test(lauri428.body.error) && lauri428.body.version === pubTerms.body.version.version, [pubTerms.body, lauri428.body]);
  const lauriFi = await callAt(FEE_API, "POST", "/orders", {}, lauri.accessToken, { headers: { "Accept-Language": "fi" } });
  check("the 428 message follows the app's language", /uusi versio/.test(lauriFi.body.error || ""), lauriFi.body);
  await callAt(FEE_API, "POST", "/me/agreements/accept", { doc: "terms", version: pubTerms.body.version.version }, lauri.accessToken);
  const lauriAfter = (await callAt(FEE_API, "GET", "/me/agreements", null, lauri.accessToken)).body;
  check("after accepting, the history keeps both versions", (await callAt(FEE_API, "POST", "/orders", {}, lauri.accessToken)).status === 400 && lauriAfter.history.filter((h) => h.doc === "terms").length === 2 && lauriAfter.required[0].accepted === true);
  const uHist = (await callAt(FEE_API, "GET", `/admin/users/${lauri.user.id}/agreements`, null, adminToken)).body;
  check("admin sees a user's acceptance history", uHist.ok && uHist.acceptances.length === 3 && uHist.acceptances.every((a) => a.version && a.acceptedAt && a.method), uHist);
  feeApi.kill(); feeApi = null;
  fs.rmSync(legalTmp, { recursive: true, force: true });
  }

  console.log("\n— Category taxonomy, product data and EU compliance (2.12)");
  {
    // A business beauty & fashion store in Helsinki with its pledge, an EU manufacturer, a non-EU manufacturer and an EU responsible person
    const bea = await register("Bea", "VENDOR");
    const beaStore = (await call("POST", "/stores", { name: `Bea Beauty ${uniq}`, category: "COSMETICS", sellerType: "BUSINESS", businessId: "4567890-7", latitude: 60.169, longitude: 24.938, address: "Esplanadi 2, Helsinki" }, bea.accessToken)).body.store;
    await call("PATCH", `/admin/vendors/${beaStore.id}/approve`, null, adminToken);
    const bt = bea.accessToken;
    const img = (n) => ownImage(beaStore.id, n);
    const mk = (body, tok = bt, raw) => call("POST", "/products", { salePriceCents: 2900, stockQuantity: 5, images: [img(`p${Math.random().toString(36).slice(2, 8)}`)], ...body }, tok, raw);
    // The legal checks above put a new version of the Seller Terms in force: Vera accepts it before publishing again
    const veraAg = (await call("GET", "/me/agreements", null, vendor.accessToken)).body.required?.find((r) => r.doc === "seller-terms");
    if (veraAg && !veraAg.accepted) await call("POST", "/me/agreements/accept", { doc: "seller-terms", version: veraAg.currentVersion }, vendor.accessToken);

    // Safety pledge (GPSR Art. 22(10)(b))
    const pl0 = await call("GET", "/stores/my/safety-pledge", null, bt);
    check("the safety pledge has a text in English and Finnish and a version, not yet given", pl0.status === 200 && pl0.body.pledge.accepted === false && /^safety-pledge@[0-9a-f]{12}$/.test(pl0.body.pledge.currentVersion) && pl0.body.pledge.text.fi.includes("EU"), pl0.body);
    const noPledge = await mk({ name: "Ennen sitoumusta", ...clothing(null) });
    check("publishing before the pledge is refused (422) with the pledge as a field", noPledge.status === 422 && noPledge.body.code === "PUBLISH_REQUIREMENTS" && noPledge.body.fields.some((f) => f.field === "safetyPledge"), noPledge.body);
    check("the pledge needs accept: true", (await call("POST", "/stores/my/safety-pledge", {}, bt)).status === 400);
    const pl1 = await call("POST", "/stores/my/safety-pledge", { accept: true }, bt);
    const pl2 = await call("POST", "/stores/my/safety-pledge", { accept: true }, bt);
    check("the pledge is recorded once with its time and version (idempotent)", pl1.status === 201 && pl1.body.pledge.accepted && pl2.status === 200 && pl2.body.alreadyAccepted === true && pl2.body.pledge.acceptedAt === pl1.body.pledge.acceptedAt && sql(`select "safetyPledgeVersion" from "Store" where id=${beaStore.id}`) === pl1.body.pledge.currentVersion);
    check("/stores/my shows the pledge", (await call("GET", "/stores/my", null, bt)).body.store?.safetyPledge?.accepted === true);

    // Manufacturer / responsible person records
    check("a manufacturer record needs an email or a web address (GPSR: electronic address)", (await call("POST", "/stores/my/operators", { name: "No Contact Oy", addressLine: "Katu 1", postalCode: "00100", city: "Helsinki", countryCode: "FI" }, bt)).status === 400);
    const mFi = (await call("POST", "/stores/my/operators", { name: "Testi Kosmetiikka Oy", addressLine: "Teollisuuskatu 3", postalCode: "00510", city: "Helsinki", countryCode: "fi", email: "info@kosmetiikka.example.fi" }, bt)).body.operator;
    const mCn = (await call("POST", "/stores/my/operators", { name: "Test Factory Ltd", addressLine: "1 Factory Road", postalCode: "518000", city: "Shenzhen", countryCode: "CN", url: "https://factory.example.com" }, bt)).body.operator;
    const rpSe = (await call("POST", "/stores/my/operators", { name: "Test Import AB", addressLine: "Gatan 1", postalCode: "11122", city: "Stockholm", countryCode: "SE", email: "rp@import.example.se" }, bt)).body.operator;
    check("records are the store's own, with the country and whether it is in the EU", mFi?.address?.countryCode === "FI" && mFi.inEu === true && mCn?.inEu === false && rpSe?.inEu === true && (await call("GET", "/stores/my/operators", null, bt)).body.operators.length === 3);
    check("another store cannot use these records", (await mk({ name: "Borrowed maker", images: [], ...clothing(mFi.id) }, vendor.accessToken)).body.fields?.some((f) => f.field === "manufacturerId" && f.code === "unknown"));

    // Taxonomy: templates, the tree and its counts
    const tpl = (await call("GET", "/categories/templates")).body.templates;
    const apparelTpl = tpl?.find((x) => x.template === "APPAREL");
    check("templates describe the editor's fields with levels, allowed values and the Annex I fibre names", apparelTpl?.fields.some((f) => f.key === "fibreComposition" && f.level === "law" && f.fibres?.some((x) => x.value === "cotton" && x.label.fi === "puuvilla")) && tpl.some((x) => x.template === "FRAGRANCE" && x.cosmetic && x.optionFields.includes("contentAmount")) && tpl.some((x) => x.template === "HAIR_TOOL"), apparelTpl?.fields?.slice(0, 2));
    const schemes = (await call("GET", "/categories/certificate-schemes")).body.schemes;
    check("certificate schemes come from a fixed list with FI/EN names", schemes?.some((x) => x.key === "nordic_swan" && x.name.fi === "Joutsenmerkki") && schemes.some((x) => x.key === "eu_ecolabel") && schemes.length >= 15);
    const allTree = (await call("GET", "/categories?includeEmpty=1")).body;
    const tops = allTree.categories?.map((c) => c.slug) ?? [];
    check("the tree has 11 top levels in Home order, incl. Sport & outdoor and Second-hand (store editor: includeEmpty=1)", tops.join() === "clothing,shoes,bags,accessories,jewellery,makeup,skincare,haircare,fragrance,sport-outdoor,second-hand", tops);
    const lips = allTree.categories?.find((c) => c.slug === "makeup")?.children.find((c) => c.slug === "makeup-lips");
    check("nodes carry FI/EN names, icon, tile colour and template", lips?.name?.fi === "Huulet" && lips.name.en === "Lips" && lips.icon === "brush" && lips.tileColor === "peach" && lips.template === "COSMETIC_MAKEUP" && allTree.categories.find((c) => c.slug === "second-hand")?.children.every((c) => c.collection === true), lips);
    check("the owner's additions are in the tree", ["clothing-outdoor-rainwear", "clothing-workwear", "clothing-festive-traditional", "clothing-nightwear-loungewear"].every((s) => allTree.categories.find((c) => c.slug === "clothing").children.some((x) => x.slug === s)) && allTree.categories.find((c) => c.slug === "shoes").children.some((x) => x.slug === "shoes-first-shoes") && allTree.categories.find((c) => c.slug === "skincare").children.some((x) => x.slug === "skincare-mens-grooming") && allTree.categories.find((c) => c.slug === "haircare").children.some((x) => x.slug === "haircare-hair-tools" && x.template === "HAIR_TOOL"));

    // Per-template validation (422 with field-level bilingual messages); drafts may be incomplete
    const draft = await mk({ name: "Luonnos ilman kategoriaa", isAvailable: false });
    check("a draft may be incomplete: saved, with the completeness meter", draft.status === 201 && draft.body.product.publishCheck?.ready === false && draft.body.product.publishCheck.missing.some((f) => f.field === "categorySlug"), draft.body);
    const noCat = await mk({ name: "Ilman kategoriaa" });
    check("a visible product needs a category (422 PUBLISH_REQUIREMENTS, messages in EN and FI)", noCat.status === 422 && noCat.body.fields.some((f) => f.field === "categorySlug" && f.message.en && f.message.fi), noCat.body);
    const fiErr = await mk({ name: "Ilman kategoriaa" }, bt, { headers: { "Accept-Language": "fi-FI" } });
    check("the summary follows the app's language", /^Tuotetta ei voi vielä julkaista/.test(fiErr.body.error || ""), fiErr.body.error);
    const comp95 = await mk({ name: "Paita 95", ...clothing(mFi.id, "clothing-tops", { attributes: { fibreComposition: [{ component: "main", fibres: [{ fibre: "cotton", percent: 90 }, { fibre: "elastane", percent: 5 }] }] } }) });
    check("textiles: the composition must total 100 % (Reg. 1007/2011)", comp95.status === 422 && comp95.body.fields.some((f) => f.code === "composition_total" && f.message.en.includes("95") && f.message.fi.includes("95 %")), comp95.body);
    check("textiles: only Annex I fibre names (bamboo is not one)", (await mk({ name: "Bambupaita", ...clothing(mFi.id, "clothing-tops", { attributes: { fibreComposition: [{ component: "main", fibres: [{ fibre: "bamboo", percent: 100 }] }] } }) })).body.code === "INVALID_PRODUCT_DATA");
    const noComp = await mk({ name: "Paita ilman materiaalia", ...clothing(mFi.id, "clothing-tops", { attributes: { brand: "Testi" } }) });
    check("textiles: no composition, no publishing", noComp.status === 422 && noComp.body.fields.some((f) => f.field === "attributes.fibreComposition"));
    const shoe = await mk({ name: "Nahkanilkkurit", ...clothing(mFi.id, "shoes-boots", { attributes: { brand: "Testi", materialUpper: ["leather"] } }) });
    check("footwear: upper, lining and sole materials (Directive 94/11/EC)", shoe.status === 422 && ["attributes.materialLiningSock", "attributes.materialOuterSole"].every((k) => shoe.body.fields.some((f) => f.field === k)) && !shoe.body.fields.some((f) => f.field === "attributes.materialUpper"), shoe.body.fields);
    const unknownAttr = await mk({ name: "Väärä tieto", ...clothing(mFi.id, "clothing-tops", { attributes: { fibreComposition: wool100, shadeFamily: "nude" } }) });
    check("an attribute of another template is refused (422 INVALID_PRODUCT_DATA, even for drafts)", unknownAttr.status === 422 && unknownAttr.body.code === "INVALID_PRODUCT_DATA" && unknownAttr.body.fields.some((f) => f.field === "attributes.shadeFamily" && f.code === "not_for_category"), unknownAttr.body);
    check("a hygiene seal is not allowed on clothing (always returnable)", (await mk({ name: "Uimapuku sinetillä", isAvailable: false, ...clothing(mFi.id, "clothing-swimwear", { hygieneSealed: true }) })).body.fields?.some((f) => f.field === "hygieneSealed" && f.code === "not_allowed"));
    const noMaker = await mk({ name: "Ilman valmistajaa", ...clothing(null) });
    check("business sellers: manufacturer name and address are required (GPSR Art. 19)", noMaker.status === 422 && noMaker.body.fields.some((f) => f.field === "manufacturerId" && /manufacturer/.test(f.message.en) && /valmistajan/.test(f.message.fi)));
    const cnMaker = await mk({ name: "Kiinasta", ...clothing(mCn.id) });
    check("a manufacturer outside the EU needs the EU responsible person", cnMaker.status === 422 && cnMaker.body.fields.some((f) => f.field === "responsiblePersonId"));
    const fiOnly = await mk({ name: "Varoitus suomeksi", ...clothing(mFi.id, "clothing-tops", { noWarnings: false, warnings: { fi: "Pidä poissa tulesta." } }) });
    check("warnings are needed in Finnish and Swedish", fiOnly.status === 422 && fiOnly.body.fields.some((f) => f.field === "warnings" && /Swedish/.test(f.message.en) && /ruotsiksi/.test(f.message.fi)), fiOnly.body.fields);
    const withRp = await mk({ name: "Kiinasta vastuuhenkilöllä", ...clothing(mCn.id, "clothing-tops", { responsiblePersonId: rpSe.id, noWarnings: false, warnings: { fi: "Pidä poissa tulesta.", sv: "Håll borta från eld." } }) });
    check("a complete product publishes; the safety block shows manufacturer, EU responsible person, model and warnings FI + SV", withRp.status === 201 && withRp.body.product.isAvailable === true && withRp.body.product.safety?.manufacturer?.name === "Test Factory Ltd" && withRp.body.product.safety.responsiblePerson?.address?.countryCode === "SE" && withRp.body.product.safety.productModel === "T-100" && withRp.body.product.safety.warnings?.sv === "Håll borta från eld." && withRp.body.product.materials?.fi === "100 % villa" && withRp.body.product.publishCheck?.ready === true, withRp.body);
    const kids = await mk({ name: "Lasten huppari", ...clothing(mFi.id, "clothing-knitwear", { audience: "KIDS", ageGroup: "KIDS", attributes: { brand: "Testi", fibreComposition: wool100, sizeSystem: "kids_height", cordsDrawstrings: "present_hood_neck" } }) });
    check("children's clothes: no cords in the hood or neck area (EN 14682)", kids.status === 422 && kids.body.fields.some((f) => f.field === "attributes.cordsDrawstrings" && f.code === "not_allowed"));
    check("children's sizes are heights in cm (50–176)", (await mk({ name: "Lasten paita M", ...clothing(mFi.id, "clothing-tops", { audience: "KIDS", attributes: { brand: "Testi", fibreComposition: wool100, sizeSystem: "kids_height", cordsDrawstrings: "none" }, variants: [{ size: "M", stock: 1 }] }) })).body.fields?.some((f) => f.field === "variants.0.size"));
    check("an age group must fit the audience (baby is for Kids)", (await mk({ name: "Vauvan body", isAvailable: false, ...clothing(mFi.id, "clothing-tops", { audience: "WOMEN", ageGroup: "BABY" }) })).body.fields?.some((f) => f.field === "ageGroup"));
    const kidsOk = await mk({ name: "Lasten neule", ...clothing(mFi.id, "clothing-knitwear", { audience: "KIDS", ageGroup: "TODDLER", attributes: { brand: "Testi", fibreComposition: wool100, sizeSystem: "kids_height", cordsDrawstrings: "none" }, variants: [{ size: "98", stock: 1 }, { size: "110 cm", stock: 1 }] }) });
    check("a complete children's product publishes with its age group", kidsOk.status === 201 && kidsOk.body.product.ageGroup === "TODDLER" && kidsOk.body.product.audience === "KIDS", kidsOk.body);

    // Cosmetics: label facts, responsible person, business only, hygiene seal on by default
    const cosm = (slug, extra = {}) => ({
      categorySlug: slug, manufacturerId: mFi.id, responsiblePersonId: mFi.id, productModel: "C-1",
      attributes: { brand: "Testi", durabilityType: "pao", paoMonths: 12, function: { fi: "Tuoksu", sv: "Doft" }, precautions: { fi: "Vain ulkoiseen käyttöön.", sv: "Endast för utvärtes bruk." }, ingredientsInci: "Alcohol Denat., Parfum, Aqua, Linalool", sealedUnused: true, ...(extra.attributes ?? {}) },
      ...Object.fromEntries(Object.entries(extra).filter(([k]) => k !== "attributes")),
    });
    const bare = await mk({ name: "Hajuvesi ilman tietoja", categorySlug: "fragrance-parfum-edp", manufacturerId: mFi.id, productModel: "X" });
    const bareFields = bare.body.fields?.map((f) => f.field) ?? [];
    check("cosmetics: content, shelf life, function and precautions FI + SV, INCI, sealed & unused and the responsible person are required", bare.status === 422 && ["contentAmount", "attributes.durabilityType", "attributes.function", "attributes.precautions", "attributes.ingredientsInci", "attributes.sealedUnused", "responsiblePersonId"].every((k) => bareFields.includes(k)), bareFields);
    check("cosmetics: testers and professional-use products are not for sale", (await mk({ name: "Testeri", ...cosm("fragrance-parfum-edp", { contentAmount: 50, contentUnit: "ml", attributes: { isTesterOrSample: true } }) })).body.fields?.some((f) => f.field === "attributes.isTesterOrSample"));
    check("cosmetics: an expired best-before date blocks publishing", (await mk({ name: "Vanha voide", ...cosm("skincare-moisturisers", { contentAmount: 50, contentUnit: "ml", attributes: { durabilityType: "best_before", paoMonths: null, bestBefore: "2020-01" } }) })).body.fields?.some((f) => f.field === "attributes.bestBefore" && f.code === "expired"));
    const paula2 = await register("Paavo", "VENDOR");
    await call("POST", "/stores", { name: `Paavon kirppis ${uniq}`, category: "THRIFT", sellerType: "PRIVATE", latitude: 60.17, longitude: 24.94 }, paula2.accessToken);
    await call("POST", "/stores/my/safety-pledge", { accept: true }, paula2.accessToken);
    const privCosm = await mk({ name: "Avaamaton huulipuna", images: [], categorySlug: "makeup-lips", contentAmount: 3.5, contentUnit: "g", attributes: { brand: "Testi", durabilityType: "pao", paoMonths: 12, function: { fi: "Huulipuna", sv: "Läppstift" }, noPrecautions: true, ingredientsInci: "Ricinus Communis Seed Oil, Cera Alba", sealedUnused: true } }, paula2.accessToken);
    check("private sellers cannot publish cosmetics, skincare, haircare or fragrance", privCosm.status === 422 && privCosm.body.fields.some((f) => f.code === "business_only"), privCosm.body.fields);
    const edp = await mk({
      name: "Testi Eau de Parfum", salePriceCents: 8900, stockQuantity: undefined,
      ...cosm("fragrance-parfum-edp", { audience: "UNISEX", attributes: { concentration: "eau_de_parfum", olfactoryFamily: ["floral"] } }),
      variants: [{ contentAmount: 30, contentUnit: "ml", priceAdjustCents: -3000, stock: 3 }, { contentAmount: 50, contentUnit: "ml", stock: 2 }, { contentAmount: 100, contentUnit: "ml", priceAdjustCents: 4000, stock: 1 }],
    });
    const ev = edp.body.product?.variants ?? [];
    check("a complete fragrance publishes; the hygiene seal is on by default and disclosed", edp.status === 201 && edp.body.product.hygieneSealed === true && /seal/.test(edp.body.product.hygieneSealNotice?.en || "") && /sinet/.test(edp.body.product.hygieneSealNotice?.fi || ""), edp.body);
    check("unit price per litre per option: 50 ml at 89,00 € → 1 780,00 €/l; 100 ml at 129,00 € → 1 290,00 €/l", ev[1]?.unitPrice?.cents === 178000 && ev[1].unitPrice.per === "l" && ev[2]?.unitPrice?.cents === 129000, ev.map((v) => v.unitPrice));
    check("no unit price under 50 ml (decree 553/2013 §10) and none at product level without a product content", ev[0]?.unitPrice === null && ev[0].priceCents === 5900 && edp.body.product.unitPrice === null);
    await call("PATCH", `/products/${edp.body.product?.id}`, { salePriceCents: 7900 }, bt);
    check("the unit price follows a reduced price (sale prices too)", (await call("GET", `/products/${edp.body.product?.id}`)).body.product.variants[1].unitPrice?.cents === 158000);
    const cream = await mk({ name: "Vartalovoide 200 g", salePriceCents: 1990, contentAmount: 200, contentUnit: "g", ...cosm("skincare-body", { attributes: { skinType: ["dry"] } }) });
    check("per kilogram for grams: 200 g at 19,90 € → 99,50 €/kg", cream.status === 201 && cream.body.product.unitPrice?.cents === 9950 && cream.body.product.unitPrice.per === "kg", cream.body.product?.unitPrice ?? cream.body);
    const edge50 = await mk({ name: "Käsivoide 50 ml", salePriceCents: 990, contentAmount: 50, contentUnit: "ml", ...cosm("skincare-hands-feet", { attributes: { skinType: ["dry"] } }) });
    const edge49 = await mk({ name: "Käsivoide 49,9 ml", salePriceCents: 990, contentAmount: 49.9, contentUnit: "ml", ...cosm("skincare-hands-feet") });
    check("exactly 50 ml shows a unit price (9,90 € → 198,00 €/l); 49,9 ml does not", edge50.body.product?.unitPrice?.cents === 19800 && edge49.status === 201 && edge49.body.product.unitPrice === null, [edge50.body.product?.unitPrice, edge49.body.product?.unitPrice]);
    const lip = await mk({ name: "Velvet Lip 02", salePriceCents: 2400, ...cosm("makeup-lips", { attributes: { productType: "lipstick", finish: "matte" } }), variants: [{ shadeName: "02 Rose", shadeHex: "#C2185B", shadeFamily: "pink", undertone: "cool", finish: "matte", contentAmount: 3.5, contentUnit: "g", stock: 4 }] });
    check("shades are options with name, hex, family, undertone and finish; tiny packs have no unit price", lip.status === 201 && lip.body.product.variants[0].shadeHex === "#C2185B" && lip.body.product.variants[0].shadeFamily === "pink" && lip.body.product.variants[0].unitPrice === null, lip.body);
    check("a shade hex must be #RRGGBB", (await mk({ name: "Bad shade", ...cosm("makeup-lips"), variants: [{ shadeName: "x", shadeHex: "red", contentAmount: 3, contentUnit: "g" }] })).status === 400);

    // Jewellery, generic green claims
    const ring = await mk({ name: "Hopeasormus", ...clothing(mFi.id, "jewellery-rings", { attributes: { brand: "Testi", metal: "silver_925", nickelBasis: "nickel_free_material" } }) });
    check("jewellery publishes with its nickel safety basis", ring.status === 201, ring.body);
    check("new jewellery without a nickel basis is refused (REACH Annex XVII)", (await mk({ name: "Teräskorvakorut", ...clothing(mFi.id, "jewellery-earrings", { attributes: { brand: "Testi", metal: "stainless_steel_316l", nickelBasis: "not_known", leadCadmiumBasis: "supplier_declaration" } }) })).body.fields?.some((f) => f.field === "attributes.nickelBasis"));
    const greenDraft = await mk({ name: "Ekologinen villapaita", description: "Sustainable and eco-friendly", isAvailable: false, tags: ["eco-friendly", "villa"], ...clothing(mFi.id, "clothing-knitwear") });
    check("claims checker: generic green words give warnings on a draft; green tags are not stored", greenDraft.status === 201 && greenDraft.body.warnings.some((w) => w.field === "name" && w.code === "generic_green_claim") && greenDraft.body.warnings.some((w) => w.field === "description") && greenDraft.body.product.tags.join() === "villa", greenDraft.body);
    const greenPub = await call("PATCH", `/products/${greenDraft.body.product?.id}`, { isAvailable: true }, bt);
    check("…and block publishing (422)", greenPub.status === 422 && greenPub.body.fields.some((f) => f.field === "name" && f.code === "generic_green_claim" && /ympäristöväittämä/.test(f.message.fi)), greenPub.body);
    check("colour words are only checked, never blocked (a green dress)", (await mk({ name: "Green linen dress", ...clothing(mFi.id, "clothing-dresses") })).status === 201);

    // Eco claim removed from the API and the database
    const ecoP = await mk({ name: "Ilman ekolippua", isEcoFriendly: true, ...clothing(mFi.id) });
    check("isEcoFriendly is gone from products and stores (accepted from old apps, ignored)", ecoP.status === 201 && !("isEcoFriendly" in ecoP.body.product) && !("isEcoFriendly" in (await call("GET", `/stores/${beaStore.id}`)).body.store) && sql(`select count(*) from information_schema.columns where column_name='isEcoFriendly'`) === "0");
    const ecoStore = await call("POST", "/stores", { name: `Eco Shop ${uniq}`, category: "ECO_FRIENDLY", sellerType: "PRIVATE" }, (await register("Eetu", "VENDOR")).accessToken);
    check("ECO_FRIENDLY is no longer a store category (old apps get OTHER)", ecoStore.status === 201 && ecoStore.body.store.category === "OTHER" && sql(`select count(*) from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname='StoreCategory' and e.enumlabel='ECO_FRIENDLY'`) === "0", ecoStore.body);

    // Attributes for filters: a dress (black, cotton), another women's product, a men's one
    const dress = await mk({ name: "Musta mekko", ...clothing(mFi.id, "clothing-dresses", { audience: "WOMEN", attributes: { brand: "Testi", fibreComposition: [{ component: "main", fibres: [{ fibre: "cotton", percent: 100 }] }], colourFamily: "black", season: ["winter"], countryOfManufacture: "FI", originDeclared: true } }) });
    const jacket = await mk({ name: "Miesten talvitakki", ...clothing(mFi.id, "clothing-jackets-coats", { audience: "MEN", attributes: { brand: "Toinen", fibreComposition: wool100, colourFamily: "navy", season: ["winter"], countryOfManufacture: "FI", originDeclared: true, fitCollection: ["tall"] } }) });
    check("attribute facets are written for search", dress.status === 201 && jacket.status === 201 && sql(`select string_agg(key || '=' || value, ',' order by key, value) from "ProductFacet" where "productId"=${dress.body.product?.id}`).includes("colourFamily=black") && sql(`select count(*) from "ProductFacet" where "productId"=${dress.body.product?.id} and key='fibre' and value='cotton'`) === "1");

    // The tree with live counts within reach
    const near = (await call("GET", "/categories?lat=60.17&lng=24.94")).body;
    const nearClothing = near.categories?.find((c) => c.slug === "clothing");
    check("GET /categories: live counts of buyable products within reach, empty nodes hidden", near.ok && near.reach?.located === true && nearClothing?.count >= 5 && nearClothing.children.every((c) => c.count > 0) && !nearClothing.children.some((c) => c.slug === "clothing-workwear") && near.categories.every((c) => c.count > 0), near);
    const far = (await call("GET", "/categories?lat=68.5&lng=27.0")).body;
    check("far from every store the tree is empty (no empty tiles); includeEmpty=1 keeps them for the editor", far.categories?.length === 0 && (await call("GET", "/categories?lat=68.5&lng=27.0&includeEmpty=1")).body.categories.length === 11);
    const menTree = (await call("GET", "/categories?lat=60.17&lng=24.94&audience=MEN")).body;
    const womenTree = (await call("GET", "/categories?lat=60.17&lng=24.94&audience=women")).body;
    const dressesCount = (t) => t.categories?.find((c) => c.slug === "clothing")?.children.find((c) => c.slug === "clothing-dresses")?.count ?? 0;
    check("audience: Women sees the women's dress, Men does not; unisex products count for both", dressesCount(womenTree) >= 1 && menTree.categories.find((c) => c.slug === "clothing")?.children.some((c) => c.slug === "clothing-jackets-coats") && dressesCount(menTree) < dressesCount(womenTree) && menTree.categories.find((c) => c.slug === "clothing").count < nearClothing.count, [dressesCount(womenTree), dressesCount(menTree)]);
    const kidsTree = (await call("GET", "/categories?includeEmpty=1&audience=KIDS")).body;
    check("Kids views never show beauty or fragrance", !kidsTree.categories.some((c) => ["makeup", "skincare", "haircare", "fragrance"].includes(c.slug)) && kidsTree.categories.some((c) => c.slug === "clothing"));
    const babyTree = (await call("GET", "/categories?audience=KIDS&ageGroup=TODDLER")).body;
    check("the Kids age row filters by age group", babyTree.ageGroup === "TODDLER" && babyTree.categories.find((c) => c.slug === "clothing")?.count >= 1);
    const det = (await call("GET", "/categories/clothing-dresses?lat=60.17&lng=24.94")).body;
    const fk = (key) => det.facets?.find((f) => f.key === key);
    check("GET /categories/:slug: node, breadcrumbs and facets with counts", det.ok && det.category?.slug === "clothing-dresses" && det.breadcrumbs?.map((b) => b.slug).join() === "clothing,clothing-dresses" && fk("colourFamily")?.values.some((v) => v.value === "black" && v.count >= 1 && v.label.fi === "Musta") && fk("fibre")?.values.some((v) => v.value === "cotton") && fk("audience")?.values.some((v) => v.value === "WOMEN") && fk("condition") && det.facets.every((f) => f.label?.en && f.label?.fi), det);
    const topDet = (await call("GET", "/categories/clothing")).body;
    check("a top level lists its children and the union of their filters", topDet.children?.length >= 3 && topDet.breadcrumbs?.length === 1 && topDet.facets?.some((f) => f.key === "season"), topDet.children?.map((c) => c.slug));
    check("an unknown category is 404", (await call("GET", "/categories/nope-nope")).status === 404);
    const makeupDet = (await call("GET", "/categories/makeup")).body;
    check("makeup facets: shade family and undertone from the options", makeupDet.facets?.some((f) => f.key === "shadeFamily" && f.values.some((v) => v.value === "pink")) && makeupDet.facets.some((f) => f.key === "undertone"), makeupDet.facets?.map((f) => f.key));

    // Search by category, audience and attributes
    const s = async (qs) => (await call("GET", `/products/search?limit=50&${qs}`)).body;
    const ids = (r) => (r.products ?? []).map((p) => p.id);
    const sTop = await s("category=clothing");
    check("search by a top-level slug includes its subcategories", ids(sTop).includes(dress.body.product.id) && ids(sTop).includes(jacket.body.product.id) && !ids(sTop).includes(edp.body.product.id));
    const sSub = await s("category=clothing-dresses");
    check("search by a subcategory slug", ids(sSub).includes(dress.body.product.id) && !ids(sSub).includes(jacket.body.product.id));
    check("the legacy free-text category still works for older apps", ids(await s("category=Dresses")).includes(dress.body.product.id));
    check("audience filter (Men = men + unisex)", !ids(await s("category=clothing&audience=MEN")).includes(dress.body.product.id) && ids(await s("category=clothing&audience=MEN")).includes(jacket.body.product.id) && ids(await s("category=clothing&audience=MEN")).includes(withRp.body.product.id));
    check("attribute filters: colour family, fibre (attr[...]), several values", ids(await s("category=clothing&colourFamily=black")).join() === String(dress.body.product.id) && ids(await s("attr[fibre]=cotton")).includes(dress.body.product.id) && ids(await s("category=clothing&colourFamily=black,navy")).length === 2);
    check("beauty filters: shade family, undertone, skin type, concentration", ids(await s("category=makeup-lips&shadeFamily=pink&undertone=cool")).includes(lip.body.product.id) && ids(await s("category=skincare&skinType=dry")).includes(cream.body.product.id) && ids(await s("category=fragrance&concentration=eau_de_parfum")).includes(edp.body.product.id));
    check("jewellery metal and fit-collection filters", ids(await s("category=jewellery&metal=silver_925")).includes(ring.body.product.id) && ids(await s("fitCollection=tall")).includes(jacket.body.product.id));
    check("age group filter", ids(await s("audience=KIDS&ageGroup=TODDLER")).includes(kidsOk.body.product.id) && !ids(await s("ageGroup=TODDLER")).includes(dress.body.product.id));
    const wrongF = await call("GET", "/products/search?category=clothing-dresses&shadeFamily=nude");
    check("a filter that the category's template does not have is refused (400)", wrongF.status === 400 && wrongF.body.code === "FILTER_NOT_AVAILABLE" && (await call("GET", "/products/search?attr[colour]=x")).body.code === "UNKNOWN_FILTER", wrongF.body);
    const huuli = await s("q=huulipuna");
    check("search names the matching categories (huulipuna → Makeup › Lips) and finds the products filed there", huuli.categories?.[0]?.slug === "makeup-lips" && huuli.categories[0].path.map((x) => x.slug).join() === "makeup,makeup-lips" && huuli.categories[0].name.fi === "Huulet" && ids(huuli).includes(lip.body.product.id), huuli.categories);
    check("English queries name categories too (lipstick)", (await s("q=lipstick")).categories?.[0]?.slug === "makeup-lips");
    check("search with a delivery location returns only products from stores within reach", ids(await s("category=clothing-dresses&lat=60.17&lng=24.94")).includes(dress.body.product.id) && (await s("lat=68.5&lng=27.0")).total === 0 && (await call("GET", "/products/search?lat=95&lng=0")).status === 400);

    // Certificates: submitted by the store, verified by an admin; only verified, unexpired ones show
    const certBody = { scheme: "nordic_swan", licenceNumber: "1234 5678", holderName: "Testi Tekstiili Oy", scope: "whole_product", validUntil: "2030-12-31", evidenceUrl: `https://res.cloudinary.com/testcloud/image/upload/v1/malvoya/certificates/s${beaStore.id}/swan.pdf` };
    check("the certificate file must be the store's own upload", (await call("POST", "/stores/my/certificates", { ...certBody, evidenceUrl: "https://example.com/fake.pdf" }, bt)).status === 400);
    check("an expired certificate cannot be submitted; schemes come from the fixed list", (await call("POST", "/stores/my/certificates", { ...certBody, validUntil: "2020-01-01" }, bt)).status === 400 && (await call("POST", "/stores/my/certificates", { ...certBody, scheme: "green_planet" }, bt)).status === 400);
    const cert = (await call("POST", "/stores/my/certificates", certBody, bt)).body.certificate;
    check("the store submits a certificate: pending until verified", cert?.status === "PENDING" && cert.live === false);
    const bunny = (await call("POST", "/stores/my/certificates", { ...certBody, scheme: "leaping_bunny", licenceNumber: "LB-1" }, bt)).body.certificate;
    check("a scheme must fit the product (Leaping Bunny is for cosmetics)", (await call("PATCH", `/products/${dress.body.product.id}`, { certificateIds: [bunny.id] }, bt)).body.fields?.some((f) => f.field === "certificateIds" && f.code === "not_for_category"));
    await call("PATCH", `/products/${dress.body.product.id}`, { certificateIds: [cert.id] }, bt);
    check("a pending certificate is not shown to shoppers or used in filters", (await call("GET", `/products/${dress.body.product.id}`)).body.product.certificates.length === 0 && !ids(await s("certificate=nordic_swan")).includes(dress.body.product.id));
    check("the certificate queue is admin-only", (await call("GET", "/admin/certificates", null, bt)).status === 403);
    const queue = (await call("GET", "/admin/certificates?status=PENDING", null, adminToken)).body.certificates;
    check("admins see pending certificates with the store and evidence", queue?.some((c) => c.id === cert.id && c.store.id === beaStore.id && c.evidenceUrl === certBody.evidenceUrl && c.productCount === 1));
    check("rejecting needs a reason", (await call("POST", `/admin/certificates/${bunny.id}/review`, { decision: "reject" }, adminToken)).status === 400);
    const verified = await call("POST", `/admin/certificates/${cert.id}/review`, { decision: "verify" }, adminToken);
    const pubCert = (await call("GET", `/products/${dress.body.product.id}`)).body.product.certificates;
    check("once verified, the chip names the scheme and licence on the page itself; the decision is audited", verified.status === 200 && pubCert.length === 1 && pubCert[0].label.fi === "Joutsenmerkki · lisenssi 1234 5678" && pubCert[0].holderName === "Testi Tekstiili Oy" && !("evidenceUrl" in pubCert[0]) && sql(`select count(*) from "AdminAuditLog" where action='certificate.verify' and "entityId"=${cert.id}`) === "1", pubCert);
    check("…and it is a filter with counts", ids(await s("certificate=nordic_swan")).includes(dress.body.product.id) && (await call("GET", "/categories/clothing-dresses")).body.facets.find((f) => f.key === "certificate")?.values.some((v) => v.value === "nordic_swan" && v.label.fi === "Joutsenmerkki"));
    sql(`update "Certificate" set "validUntil" = current_date - 1 where id=${cert.id}`);
    check("an expired certificate disappears from payloads and filters", (await call("GET", `/products/${dress.body.product.id}`)).body.product.certificates.length === 0 && !ids(await s("certificate=nordic_swan")).includes(dress.body.product.id));
    sql(`update "Certificate" set "validUntil" = '2030-12-31' where id=${cert.id}`);

    // Report this product (signed in or not, rate-limited) → admin queue
    const target = withRp.body.product.id;
    check("a report needs a valid reason; 'other' needs details", (await call("POST", `/products/${target}/report`, { reason: "ugly" })).status === 400 && (await call("POST", `/products/${target}/report`, { reason: "other" })).status === 400);
    const rep1 = await call("POST", `/products/${target}/report`, { reason: "unsafe", details: "The zip puller came off and is a choking hazard", email: "reporter@example.fi" });
    check("anyone can report a product, also signed out; a due date of three working days", rep1.status === 201 && rep1.body.report.status === "OPEN" && new Date(rep1.body.report.dueBy) > new Date(), rep1.body);
    const hanna = await register("Hanna");
    const repA = await call("POST", `/products/${target}/report`, { reason: "counterfeit", details: "Fake logo" }, hanna.accessToken);
    const repB = await call("POST", `/products/${target}/report`, { reason: "counterfeit", details: "Fake logo" }, hanna.accessToken);
    check("a signed-in user's second open report is the same report", repA.status === 201 && repB.status === 200 && repB.body.alreadyReported === true && repB.body.report.id === repA.body.report.id);
    const fixedIp = { headers: { "X-Forwarded-For": `10.250.${uniq % 200}.7` } };
    const rl = [];
    for (let i = 0; i < 6; i++) rl.push((await call("POST", `/products/${target}/report`, { reason: "misleading" }, null, fixedIp)).status);
    check("reports are rate-limited (5 an hour per address or account)", rl.slice(0, 5).every((x) => x === 201) && rl[5] === 429, rl);
    const rq = (await call("GET", "/admin/product-reports", null, adminToken)).body.reports;
    const rq1 = rq?.find((r) => r.id === rep1.body.report.id);
    check("admins see the report queue with due dates, the reporter and the claims check", rq1?.reason === "unsafe" && rq1.reporter.email === "reporter@example.fi" && rq1.reporter.signedIn === false && rq1.dueBy && Array.isArray(rq1.product.claims) && (await call("GET", "/admin/product-reports", null, bt)).status === 403, rq1);
    check("a decision needs a note", (await call("POST", `/admin/product-reports/${rep1.body.report.id}/resolve`, { action: "remove_listing" }, adminToken)).status === 400);
    const removed = await call("POST", `/admin/product-reports/${rep1.body.report.id}/resolve`, { action: "remove_listing", note: "Choking hazard confirmed from the photos" }, adminToken);
    check("removing the listing locks it, closes the other notices about it and is audited", removed.status === 200 && sql(`select "isAvailable" || '|' || "lockedReason" from "Product" where id=${target}`) === "false|ADMIN" && sql(`select count(*) from "ProductReport" where "productId"=${target} and status='OPEN'`) === "0" && sql(`select count(*) from "AdminAuditLog" where action='product_report.remove_listing' and "entityId"=${rep1.body.report.id}`) === "1");
    const relock = await call("PATCH", `/products/${target}`, { isAvailable: true }, bt);
    check("the store cannot show a locked listing again (409 PRODUCT_LOCKED)", relock.status === 409 && relock.body.code === "PRODUCT_LOCKED", relock.body);
    check("a decided report cannot be decided again", (await call("POST", `/admin/product-reports/${rep1.body.report.id}/resolve`, { action: "dismiss", note: "again please" }, adminToken)).status === 409);
    check("the reporter's own reports are in their data export", (await call("GET", "/auth/me/data", null, hanna.accessToken)).body.data?.productReports?.some((r) => r.reason === "counterfeit"));
    const adminView = (await call("GET", `/admin/products/${greenDraft.body.product.id}`, null, adminToken)).body.product;
    check("admins see a product's claims-checker warnings and its publishing check", adminView?.claims?.some((c) => c.term === "ekologinen" && c.blocking) && adminView.publishCheck?.ready === false && adminView.store?.id === beaStore.id, adminView?.claims);

    // Recalls: identical listings lock, every buyer is told directly, public page
    const gtin = ean13(`64${String(uniq).slice(-10)}`);
    const recalled = await mk({ name: "Testi Hiuspinni", gtin, ...clothing(mFi.id, "accessories-hair", { attributes: { brand: "Testi", mainMaterial: ["metal"] }, productModel: "RC-1" }) });
    const twin = await call("POST", "/products", { name: "Hiuspinni (sama)", gtin, salePriceCents: 900, images: [ownImage(storeId, "twin")], ...clothing(veraMfr, "accessories-hair", { attributes: { brand: "Joku" }, productModel: "X-9" }) }, vendor.accessToken);
    const sameModel = await mk({ name: "Hiuspinni, punainen", ...clothing(mFi.id, "accessories-hair", { attributes: { brand: "testi" }, productModel: "rc-1" }) });
    check("a GTIN must have a valid check digit", (await mk({ name: "Bad EAN", gtin: "6412345678900", ...clothing(mFi.id) })).status === 400 && recalled.status === 201 && twin.status === 201 && sameModel.status === 201, [recalled.body, twin.body]);
    const kaisa = await register("Kaisa");
    await call("PATCH", "/me", { locale: "fi" }, kaisa.accessToken);
    const buy = (user, productId, tag) => {
      const oid = Number(sql(`insert into "Order" ("userId","storeId","status","subtotalCents","deliveryFeeCents","courierFeeCents","commissionCents","sellerPayoutCents","totalCents","stripePaymentIntentId","paymentStatus","paidAt","deliveredAt","deliveryAddress","updatedAt") values (${user.user.id},${beaStore.id},'DELIVERED',2900,300,300,290,2610,3200,'pi_rc_${tag}_${uniq}','SUCCEEDED',now() - interval '3 days',now() - interval '2 days','Testikatu 1, Helsinki',now()) returning id`).split("\n")[0]);
      sql(`insert into "OrderItem" ("orderId","productId","quantity","unitCents") values (${oid},${productId},1,2900)`);
      return oid;
    };
    buy(hanna, recalled.body.product.id, "h");
    buy(kaisa, sameModel.body.product.id, "k");
    const recallBody = { productIds: [recalled.body.product.id], reasonFi: "Hiuspinnin metalliosa voi irrota ja aiheuttaa tukehtumisvaaran pienille lapsille.", reasonEn: "The metal part of the hair clip can come off and is a choking hazard for small children.", remedyFi: "Palauta tuote myymälään, saat rahat takaisin.", remedyEn: "Return the product to the shop for a full refund.", remedies: ["refund", "replacement"], contact: "Malvoya tuki, malvoya-api-eu.onrender.com/support" };
    const soft = await call("POST", "/admin/recalls", { ...recallBody, reasonEn: "As a precautionary measure, the clip may in rare cases come loose." }, adminToken);
    check("a recall notice may not play the hazard down (no 'precautionary', 'in rare cases')", soft.status === 422 && soft.body.code === "INVALID_RECALL" && soft.body.fields.some((f) => f.field === "reasonEn"), soft.body);
    check("recalls are admin-only", (await call("POST", "/admin/recalls", recallBody, bt)).status === 403);
    const rc = await call("POST", "/admin/recalls", recallBody, adminToken);
    const rcId = rc.body.recall?.id;
    check("a recall locks the product and every identical listing (same GTIN, or same brand + model) in any shop", rc.status === 201 && rc.body.locked === 3 && rc.body.identical === 2 && [recalled, twin, sameModel].every((p) => sql(`select "isAvailable" || '|' || "lockedReason" from "Product" where id=${p.body.product.id}`) === "false|RECALL") && rc.body.recall.products.some((p) => p.matchedBy === "gtin") && rc.body.recall.products.some((p) => p.matchedBy === "brand_model"), rc.body);
    let notes = "";
    for (let i = 0; i < 40 && !/hanna-email-t/.test(notes + "") ; i++) {
      notes = sql(`select string_agg(u.name || '-' || n.channel || '-' || left(n.delivered::text,1) || '-' || n.locale, ',' order by u.name, n.channel) from "RecallNotification" n join "User" u on u.id = n."userId" where n."recallId"=${rcId}`).toLowerCase();
      if (/hanna-email-t/.test(notes) && /kaisa-email-t/.test(notes)) break;
      await sleep(250);
    }
    check("every buyer of the recalled listings is notified directly by push and email, in their language", /hanna-email-t-en/.test(notes) && /kaisa-email-t-fi/.test(notes) && /hanna-push/.test(notes) && /kaisa-push/.test(notes), notes);
    check("the recall records when buyers were told, and the creation is audited", sql(`select ("buyersNotifiedAt" is not null) || '|' || "notifiedUsers" from "Recall" where id=${rcId}`) === "true|2" && sql(`select count(*) from "AdminAuditLog" where action='recall.create' and "entityId"=${rcId}`) === "1");
    const pubRc = (await call("GET", "/recalls")).body.recalls?.find((r) => r.id === rcId);
    check("GET /recalls lists it with the hazard, remedies, contact and products", pubRc?.headline?.fi === "Tuotteen turvallisuuteen liittyvä takaisinveto" && pubRc.hazard.en === recallBody.reasonEn && pubRc.remedies.join() === "refund,replacement" && pubRc.products.length === 3, pubRc);
    const pageFi = await (await fetch(`${BASE}/recalls/${rcId}?lang=fi`)).text();
    const pageEn = await fetch(`${BASE}/recalls/${rcId}?lang=en`);
    const pageEnText = await pageEn.text();
    check("the public notice uses the legal format: headline, product, identification, hazard, 'stop using it now', remedies, contact", pageFi.includes("Tuotteen turvallisuuteen liittyvä takaisinveto") && pageFi.includes("Lopeta tuotteen käyttö heti") && pageFi.includes(gtin) && pageEnText.includes("Product safety recall") && pageEnText.includes("Stop using this product now") && pageEnText.includes("Refund") && !/<script/i.test(pageEnText) && /img-src https:\/\/res\.cloudinary\.com/.test(pageEn.headers.get("content-security-policy") || ""));
    check("the public /recalls page lists it", (await (await fetch(`${BASE}/recalls?lang=en`)).text()).includes(`/recalls/${rcId}`));
    const rcProd = (await call("GET", `/products/${recalled.body.product.id}`)).body.product;
    check("buyers who open the product see the recall banner; it cannot be bought or found", rcProd?.recall?.id === rcId && rcProd.inStock === false && !ids(await s(`q=${encodeURIComponent("Testi Hiuspinni")}`)).includes(recalled.body.product.id), rcProd?.recall);
    check("the store cannot show a recalled listing again", (await call("PATCH", `/products/${twin.body.product.id}`, { isAvailable: true }, vendor.accessToken)).body.code === "PRODUCT_LOCKED");
    const relist = await mk({ name: "Uusi hiuspinni", gtin, ...clothing(mFi.id, "accessories-hair", { attributes: { brand: "Muu" }, productModel: "N-1" }) });
    check("a recalled GTIN cannot be listed again", relist.status === 422 && relist.body.fields.some((f) => f.code === "recalled"), relist.body.fields);
    check("customers see recalls of what they bought in the app", (await call("GET", "/me/recalls", null, kaisa.accessToken)).body.recalls?.some((r) => r.id === rcId) && (await call("GET", "/me/recalls", null, (await register("Iida")).accessToken)).body.recalls.length === 0);
    const closeRc = await call("PATCH", `/admin/recalls/${rcId}`, { status: "CLOSED" }, adminToken);
    check("an admin closes the recall (audited); the listings stay locked", closeRc.status === 200 && closeRc.body.recall.status === "CLOSED" && sql(`select count(*) from "AdminAuditLog" where action='recall.status' and "entityId"=${rcId}`) === "1" && sql(`select "lockedReason" from "Product" where id=${twin.body.product.id}`) === "RECALL" && (await call("GET", "/admin/recalls", null, adminToken)).body.recalls.some((r) => r.id === rcId && r.notifiedUsers === 2));

    // Hygiene seal: snapshot on the order, return needs the seal state
    const hygOrder = await call("POST", "/orders", { storeId: beaStore.id, fulfilment: "PICKUP", items: [{ productId: cream.body.product.id, quantity: 2 }] }, hanna.accessToken);
    const hoid = hygOrder.body.order?.id;
    check("the hygiene seal is snapshotted onto the order line at purchase", hygOrder.status === 201 && sql(`select "hygieneSealed" from "OrderItem" where "orderId"=${hoid}`) === "t", hygOrder.body);
    sql(`update "Order" set status='DELIVERED', "paymentStatus"='SUCCEEDED', "paidAt"=now(), "deliveredAt"=now() where id=${hoid}`);
    const hItem = Number(sql(`select id from "OrderItem" where "orderId"=${hoid}`));
    const noSeal = await call("POST", "/returns", { orderId: hoid, reason: "CHANGED_MIND", items: [{ orderItemId: hItem, quantity: 1 }] }, hanna.accessToken);
    check("returning a sealed item under the right of withdrawal asks whether the seal is unbroken", noSeal.status === 400 && noSeal.body.code === "SEAL_STATUS_REQUIRED" && noSeal.body.question?.fi === "Onko hygieniasinetti ehjä?", noSeal.body);
    const opened = await call("POST", "/returns", { orderId: hoid, reason: "CHANGED_MIND", sealIntact: false, items: [{ orderItemId: hItem, quantity: 1 }] }, hanna.accessToken);
    check("an opened seal is refused with a clear reason in both languages that cites the disclosure", opened.status === 422 && opened.body.code === "HYGIENE_SEAL_OPENED" && /order confirmation/.test(opened.body.reason?.en || "") && /tilausvahvistuksessa/.test(opened.body.reason?.fi || "") && /6 luku 16 §/.test(opened.body.reason.fi), opened.body);
    const intact = await call("POST", "/returns", { orderId: hoid, reason: "CHANGED_MIND", sealIntact: true, items: [{ orderItemId: hItem, quantity: 1 }] }, hanna.accessToken);
    check("with the seal unbroken the return goes ahead (and the answer is kept)", intact.status === 201 && sql(`select "sealIntact" from "Return" where id=${intact.body.return?.id}`) === "t", intact.body);
    const faulty = await call("POST", "/returns", { orderId: hoid, reason: "DAMAGED_ON_ARRIVAL", items: [{ orderItemId: hItem, quantity: 1 }] }, hanna.accessToken);
    check("a faulty sealed item is always returnable (no seal question)", faulty.status === 201, faulty.body);

    // Import mapping (FI/EN keywords, Finnish compounds by their last word, audience, second-hand, held goods)
    Object.assign(process.env, testEnv);
    const matcher = require(path.join(__dirname, "..", "..", "dist", "modules", "catalog", "matcher.js"));
    const m = (...h) => matcher.matchTaxonomy(h);
    check("matcher: Finnish compounds by their last word, with the audience", m("Naisten iltamekko").slug === "clothing-dresses" && m("Naisten iltamekko").audience === "WOMEN" && m("talvitakki").slug === "clothing-jackets-coats" && m("Lasten kumisaappaat").slug === "shoes-rubber-boots" && m("Lasten kumisaappaat").audience === "KIDS");
    check("matcher: ASCII-typed Finnish, English plurals, longest keyword wins", m("Talvikengat").slug === "shoes-winter-rubber-boots" && m("Talvikengät").slug === "shoes-winter-rubber-boots" && m("Shower gel for men").slug === "skincare-body" && m("Shower gel for men").audience === "MEN" && m("earrings").slug === "jewellery-earrings" && m("Huulipuna 02").slug === "makeup-lips");
    check("matcher: vintage and used words set second-hand; only a top level → no guess (or clothing-other)", m("Vintage farkut").slug === "clothing-trousers-jeans" && m("Vintage farkut").secondHand && m("Vintage farkut").vintage && m("Kengät").slug === null && m("Kengät").topOnly === "shoes" && m("Vaatteet").slug === "clothing-other");
    check("matcher: out-of-scope goods are held; nothing matched stays without a category", m("Tuoksukynttilä kuusi").holdKey === "home_decor" && m("Kollageeni ravintolisä").holdKey === "food_supplement" && m("Gizmo 3000").slug === null && m("Hiustenkuivaaja 2000 W").slug === "haircare-hair-tools");
    const csv212 = [
      "name;description;category_slug;category;price;stock;image_urls;condition;external_id;brand;audience;content_ml",
      "Testi Eau de Parfum;Floral;fragrance-parfum-edp;;59,00;3;https://img.example.com/edp.jpg;new;EDP-1;Testi;unisex;30",
      "Testi Eau de Parfum;Floral;fragrance-parfum-edp;;89,00;2;;new;EDP-1;Testi;unisex;50",
      "Tuoksukynttilä Kuusi;;;Sisustus;25;1;https://img.example.com/candle.jpg;new;CANDLE-1;;;",
      "Gizmo 3000;;;;10;1;https://img.example.com/gizmo.jpg;new;GIZ-1;;;",
      "Naisten talvitakki;;;Naiset > Takit;149;1;https://img.example.com/coat.jpg;new;COAT-1;;;",
    ].join("\n");
    const cj212 = await call("POST", "/products/import/csv", { csv: csv212, rightsConfirmed: true }, wilma.accessToken);
    let j212 = null;
    for (let i = 0; i < 120 && !(j212 && (j212.status === "DONE" || j212.status === "FAILED")); i++) { await sleep(250); j212 = (await call("GET", `/products/import/${cj212.body.job?.id}`, null, wilma.accessToken)).body?.job; }
    const wl = (await call("GET", `/stores/my/products?limit=100`, null, wilma.accessToken)).body.products;
    const iEdp = wl.find((p) => p.externalId === "id:EDP-1");
    const iCandle = wl.find((p) => p.externalId === "id:CANDLE-1");
    const iGizmo = wl.find((p) => p.externalId === "id:GIZ-1");
    const iCoat = wl.find((p) => p.externalId === "id:COAT-1");
    check("CSV import maps category_slug, brand, audience and content per option (unit price)", j212?.status === "DONE" && iEdp?.categorySlug === "fragrance-parfum-edp" && iEdp.attributes.brand === "Testi" && iEdp.variants.map((v) => v.contentAmount).join() === "30,50" && iEdp.variants[1].unitPrice?.cents === 178000 && iEdp.category === "Parfum & eau de parfum" && iEdp.hygieneSealed === true, iEdp);
    check("CSV import: paths and Finnish words map with the audience (Naiset > Takit)", iCoat?.categorySlug === "clothing-jackets-coats" && iCoat.audience === "WOMEN");
    check("CSV import: out-of-scope goods are held, unmatched items stay drafts without a category, both reported", iCandle?.importHold === "home_decor" && iCandle.categorySlug === null && iGizmo?.categorySlug === null && j212.errors.some((e) => /On hold/.test(e.message)) && j212.errors.some((e) => /No category matched/.test(e.message)) && j212.errors.some((e) => /Missing before publishing/.test(e.message)), j212?.errors);
    const wAg = (await call("GET", "/me/agreements", null, wilma.accessToken)).body.required?.find((r) => r.doc === "seller-terms");
    if (wAg && !wAg.accepted) await call("POST", "/me/agreements/accept", { doc: "seller-terms", version: wAg.currentVersion }, wilma.accessToken);
    const p212 = (await call("POST", `/products/import/${cj212.body.job?.id}/publish`, null, wilma.accessToken)).body;
    check("an import publishes nothing incomplete: a held item says why", p212.published === 0 && p212.incomplete.find((x) => x.productId === iCandle?.id)?.missing.some((f) => f.code === "held"), p212);

    // Collections (saved filters, in season, ≥ CATALOG_COLLECTION_MIN_ITEMS nearby; 2 in this test)
    const cols = (qs = "") => call("GET", `/collections?lat=60.17&lng=24.94${qs}`);
    const c1r = (await cols("&month=1")).body;
    const slugs1 = c1r.collections?.map((c) => c.slug) ?? [];
    check("GET /collections: in-season collections with enough items nearby (winter in January, Made in Finland with the seller's declaration)", c1r.ok && c1r.minItems === 2 && slugs1.includes("winter-essentials") && slugs1.includes("made-in-finland") && c1r.collections.every((c) => c.count >= 2 && c.name.fi && c.name.en), c1r.collections);
    check("out of season collections are not shown (winter in July)", !((await cols("&month=7")).body.collections ?? []).some((c) => c.slug === "winter-essentials"));
    const c1k = (await cols("&month=1&audience=KIDS")).body.collections?.map((c) => c.slug) ?? [];
    check("beauty collections exist for everyone but never in Kids views", slugs1.includes("concern-dry-skin") && !c1k.includes("concern-dry-skin"), [slugs1, c1k]);
    check("collections below the minimum are hidden (one tall item)", !slugs1.includes("fit-tall"));
    const mif = await s("collection=made-in-finland");
    check("search by collection uses its saved filter", ids(mif).includes(dress.body.product.id) && ids(mif).includes(jacket.body.product.id) && !ids(mif).includes(edp.body.product.id) && (await call("GET", "/products/search?collection=nope")).status === 400);
    const brands = (await call("GET", "/collections/brands?lat=60.17&lng=24.94")).body.brands;
    check("the A–Z brand index comes from product data", brands?.some((b) => b.value === "testi" && b.name === "Testi" && b.letter === "T" && b.count >= 3), brands);

    // Admin: categories (rename, reorder, hide, counts), the under-18 flag
    const acs = (await call("GET", "/admin/categories", null, adminToken)).body;
    const workwear = acs.categories?.find((c) => c.slug === "clothing-workwear");
    const dressesRow = acs.categories?.find((c) => c.slug === "clothing-dresses");
    check("admin Categories lists every node with product counts", acs.ok && dressesRow?.visibleProducts >= 2 && acs.categories.length >= 90 && typeof acs.uncategorised?.products === "number", dressesRow);
    const ren = await call("PATCH", `/admin/categories/${workwear.id}`, { nameFi: "Työ- ja suojavaatteet", sort: 5, active: false }, adminToken);
    check("admins rename, reorder and hide a category (audited); hidden ones leave the tree", ren.status === 200 && ren.body.category.nameFi === "Työ- ja suojavaatteet" && !(await call("GET", "/categories?includeEmpty=1")).body.categories.find((c) => c.slug === "clothing").children.some((c) => c.slug === "clothing-workwear") && sql(`select count(*) from "AdminAuditLog" where action='category.edit' and "entityId"=${workwear.id}`) === "1");
    check("a hidden category cannot be chosen in the editor", (await mk({ name: "Työhousut", ...clothing(mFi.id, "clothing-workwear") })).body.fields?.some((f) => f.field === "categorySlug"));
    await call("PATCH", `/admin/categories/${workwear.id}`, { active: true }, adminToken);
    const minor = await call("PATCH", `/admin/users/${kaisa.user.id}/minor`, { isMinor: true }, adminToken);
    check("an admin can flag a user as under 18 (no profiling-based recommendations; audited); the feed still works", minor.status === 200 && sql(`select "isMinor" from "User" where id=${kaisa.user.id}`) === "t" && (await call("GET", "/drops/feed", null, kaisa.accessToken)).status === 200);
    await call("POST", `/products/${dress.body.product.id}/report`, { reason: "misleading", details: "The colour is not as shown" }, kaisa.accessToken);
    // Same-day signal: a store open now within reach and an approved courier online recently; slots only from the configuration
    const sd0 = (await call("GET", "/delivery/today?lat=68.5&lng=27.0")).body;
    check("same-day delivery is not possible far from every store; slots never invented", sd0.ok && sd0.possible === false && sd0.reach.stores === 0 && sd0.slots.length === 0, sd0);
    const cOnline = await register("Sami", "COURIER");
    sql(`update "Courier" set "isApproved"=true where "userId"=${cOnline.user.id}`);
    await call("POST", "/courier/status", { isOnline: true, latitude: 60.17, longitude: 24.94 }, cOnline.accessToken);
    const sd1 = (await call("GET", "/delivery/today?lat=60.17&lng=24.94")).body;
    const nowH = hel();
    const todaySlots = ["17:00", "19:00"].filter((st) => Number(st.slice(0, 2)) * 60 >= Number(nowH.time.slice(0, 2)) * 60 + Number(nowH.time.slice(3, 5)) + 60);
    check("same-day delivery is possible near an open store with a courier online; slots are today's configured ones still bookable", sd1.possible === true && sd1.date === nowH.date && sd1.slots.map((x) => x.start).join() === todaySlots.join() && sd1.slots.every((x) => x.label?.en && x.label?.fi && x.end), [sd1, todaySlots]);
    await call("POST", "/courier/status", { isOnline: false }, cOnline.accessToken);
    // Sign in with Apple (iOS): the Apple user id first, then the verified email; loaded from dist (no real Firebase token here)
    const social = require(path.join(__dirname, "..", "..", "dist", "modules", "auth", "social.service.js"));
    const appleId = (x) => ({ firebase: { identities: { "apple.com": [x] } } });
    const subA = `001234.apple${uniq}.0101`;
    const ap1 = await social.signInWithAppleClaims({ email: `apple${uniq}@privaterelay.appleid.com`, email_verified: true, ...appleId(subA) }, "CUSTOMER", "  Anna Apple  ");
    check("Sign in with Apple creates the account with the Apple id and the name the app sends (trimmed)", ap1.user?.name === "Anna Apple" && !!ap1.accessToken && sql(`select "appleSub" from "User" where id=${ap1.user.id}`) === subA, ap1.user);
    const ap2 = await social.signInWithAppleClaims({ ...appleId(subA) });
    check("the Apple id opens the same account later, also without an email", ap2.user?.id === ap1.user.id);
    let apRefused = null;
    try { await social.signInWithAppleClaims({ email: `cecilia${uniq}@example.fi`, email_verified: true, ...appleId(`other.${uniq}`) }); } catch (e) { apRefused = e.status; }
    check("Apple never opens an account made by /register (unproven email): 409", apRefused === 409, apRefused);
    const subB = `001234.apple${uniq}.0202`;
    const ap3 = await social.signInWithAppleClaims({ email: `OTP${uniq}@example.fi`, email_verified: true, ...appleId(subB) });
    check("a verified-sign-in account found by its email gets the Apple id on first use", ap3.user?.id === codeNew.body.user.id && sql(`select "appleSub" from "User" where id=${codeNew.body.user.id}`) === subB);
    let apNoEmail = null;
    try { await social.signInWithAppleClaims({ ...appleId(`new.${uniq}`) }); } catch (e) { apNoEmail = e.status; }
    check("a new Apple user without a verified email is refused (401)", apNoEmail === 401);
    check("POST /auth/apple validates the name (≤ 100) and the token", (await call("POST", "/auth/apple", { idToken: "x", name: "a".repeat(101) })).status === 400 && (await call("POST", "/auth/apple", { name: "Anna" })).status === 400 && (await call("POST", "/auth/apple", { idToken: "not-a-token", name: "Anna" })).status === 401);
    check("account deletion clears the Apple id", (await call("DELETE", "/auth/me", null, ap1.accessToken)).status === 200 && sql(`select "appleSub" is null from "User" where id=${ap1.user.id}`) === "t");
    const aasa = await fetch(`${BASE}/.well-known/apple-app-site-association`, { redirect: "manual" });
    check("apple-app-site-association: 200 JSON, no redirect; no apps without APPLE_TEAM_ID", aasa.status === 200 && /application\/json/.test(aasa.headers.get("content-type") || "") && JSON.stringify(await aasa.json()) === '{"applinks":{"details":[]}}');
    const sys212 = (await call("GET", "/admin/system", null, adminToken)).body;
    check("System lists open product reports and pending certificates", sys212.attention?.some((a) => /certificate\(s\) waiting/.test(a)) && sys212.attention.some((a) => /product report\(s\)/.test(a)), sys212.attention);
  }

  { // 2.13: two-step sign-in (authenticator app) for admins
    console.log("\n— Two-step sign-in for admins");
    // Independent RFC 6238 implementation (not the API's), so the test proves the codes an authenticator app shows work
    const b32dec = (t) => { let bits = 0, v = 0; const out = []; for (const ch of t) { v = (v << 5) | "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".indexOf(ch); bits += 5; if (bits >= 8) { out.push((v >>> (bits - 8)) & 255); bits -= 8; } } return Buffer.from(out); };
    const totp = (secretB32, step) => {
      const c = Buffer.alloc(8); c.writeBigUInt64BE(BigInt(step));
      const h = crypto.createHmac("sha1", b32dec(secretB32)).update(c).digest(); const o = h[19] & 15;
      return String((((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3]) % 1e6).padStart(6, "0");
    };
    const stepNow = () => Math.floor(Date.now() / 30000);
    const jwtBody = (tok) => JSON.parse(Buffer.from(tok.split(".")[1], "base64url").toString());
    const a2Email = `admin2fa${uniq}@example.fi`;
    const a2 = (await call("POST", "/auth/register", { name: "Admin Kaksi", email: a2Email, password: "strong-pass-123" })).body;
    sql(`update "User" set role='ADMIN' where id=${a2.user.id}`);
    const login = () => call("POST", "/auth/login", { email: a2Email, password: "strong-pass-123" });
    let a2Token = (await login()).body.accessToken;

    const st0 = await call("GET", "/me/mfa", null, a2Token);
    check("GET /me/mfa: off, not required outside production", st0.status === 200 && st0.body.enabled === false && st0.body.required === false && st0.body.needsPassword === true, st0.body);
    check("two-step set-up is for admin accounts only (403)", (await call("GET", "/me/mfa", null, otherCust.accessToken)).status === 403 && (await call("POST", "/me/mfa/setup", { password: "strong-pass-123" }, otherCust.accessToken)).status === 403);
    check("set-up asks for the password again (400 without / wrong)", (await call("POST", "/me/mfa/setup", {}, a2Token)).status === 400 && (await call("POST", "/me/mfa/setup", { password: "wrong-pass-999" }, a2Token)).status === 400);
    check("enable before set-up → 409", (await call("POST", "/me/mfa/enable", { code: "123456" }, a2Token)).status === 409);
    const setup = (await call("POST", "/me/mfa/setup", { password: "strong-pass-123" }, a2Token)).body;
    const secret = setup.secret;
    check("set-up returns a 160-bit base32 secret and an otpauth:// link for the authenticator app", /^[A-Z2-7]{32}$/.test(secret || "") && setup.otpauthUrl === `otpauth://totp/Malvoya%3A${encodeURIComponent(a2Email)}?secret=${secret}&issuer=Malvoya&algorithm=SHA1&digits=6&period=30`, setup);
    const storedSecret = sql(`select "totpSecret" from "User" where id=${a2.user.id}`);
    check("the secret is stored encrypted, never in the clear", storedSecret.startsWith("t1:") && !storedSecret.includes(secret));
    check("the secret and recovery codes are never part of an account payload", !JSON.stringify((await call("GET", "/me", null, a2Token)).body).includes("totp"));
    check("a pending set-up does not change sign-in yet", !!(await login()).body.accessToken && (await call("GET", "/me/mfa", null, a2Token)).body.pending === true);
    const wrongEnable = await call("POST", "/me/mfa/enable", { code: totp(secret, stepNow() + 5) }, a2Token);
    check("a wrong code does not turn it on (400, attempts left)", wrongEnable.status === 400 && wrongEnable.body.attemptsLeft === 4, wrongEnable.body);
    const s0 = stepNow();
    const enabled = await call("POST", "/me/mfa/enable", { code: totp(secret, s0) }, a2Token);
    const rc = enabled.body.recoveryCodes || [];
    check("the first code turns it on: 10 one-time recovery codes (shown once) and a fresh verified session", enabled.status === 200 && rc.length === 10 && rc.every((c) => /^[a-z2-9]{5}-[a-z2-9]{5}$/.test(c)) && !!enabled.body.accessToken && jwtBody(enabled.body.accessToken).mfa === true, enabled.body);
    check("recovery codes are stored hashed", sql(`select array_length("totpRecoveryCodes", 1) || '|' || ("totpRecoveryCodes"::text like '%${rc[0]}%')::text from "User" where id=${a2.user.id}`) === "10|false");
    check("turning it on ends every earlier session (old access token 401)", (await call("GET", "/me/mfa", null, a2Token)).status === 401);
    a2Token = enabled.body.accessToken;
    check("…and is audited", sql(`select count(*) from "AdminAuditLog" where action='mfa.enable' and "entityId"=${a2.user.id}`) === "1");

    const first = await login();
    check("password sign-in now returns a 5-minute challenge instead of tokens", first.status === 200 && first.body.mfaRequired === true && !!first.body.mfaToken && !first.body.accessToken && !first.body.refreshToken, first.body);
    check("the challenge token is not an access token", (await call("GET", "/me", null, first.body.mfaToken)).status === 401);
    check("second step: a bad or missing challenge → 401/400", (await call("POST", "/auth/login/mfa", { mfaToken: "x".repeat(20), code: "123456" })).status === 401 && (await call("POST", "/auth/login/mfa", { code: "123456" })).status === 400);
    check("the code already used to turn it on is not accepted again (replay)", (await call("POST", "/auth/login/mfa", { mfaToken: first.body.mfaToken, code: totp(secret, s0) })).status === 400);
    const second = await call("POST", "/auth/login/mfa", { mfaToken: first.body.mfaToken, code: totp(secret, s0 + 1) });
    check("challenge + the next authenticator code → a verified session", second.status === 200 && !!second.body.accessToken && !!second.body.refreshToken && jwtBody(second.body.accessToken).mfa === true && second.body.user?.role === "ADMIN", second.body);
    const again = await login();
    check("the same code never opens a second session", (await call("POST", "/auth/login/mfa", { mfaToken: again.body.mfaToken, code: totp(secret, s0 + 1) })).status === 400);
    const refreshed = await call("POST", "/auth/refresh", { refreshToken: second.body.refreshToken });
    check("refreshing a verified session keeps it verified", refreshed.status === 200 && jwtBody(refreshed.body.accessToken).mfa === true && (await call("GET", "/admin/system", null, refreshed.body.accessToken)).status === 200, refreshed.body);
    const viaRc = await call("POST", "/auth/login/mfa", { mfaToken: again.body.mfaToken, code: rc[0].toUpperCase().replace("-", " ") });
    check("a recovery code works once instead of the app (any case, spaces), and says how many are left", viaRc.status === 200 && viaRc.body.recoveryCodesLeft === 9 && !!viaRc.body.accessToken, viaRc.body);
    check("…the same recovery code is refused next time", (await call("POST", "/auth/login/mfa", { mfaToken: (await login()).body.mfaToken, code: rc[0] })).status === 400);
    check("using a recovery code is audited", sql(`select count(*) from "AdminAuditLog" where action='mfa.recovery_code_used' and "entityId"=${a2.user.id}`) === "1");
    sql(`update "User" set "totpFailures"=0 where id=${a2.user.id}`);
    const ch = (await login()).body.mfaToken;
    let lastWrong = null;
    for (let i = 0; i < 5; i++) lastWrong = await call("POST", "/auth/login/mfa", { mfaToken: ch, code: "000000" === totp(secret, stepNow()) ? "111111" : "000000" });
    check("five wrong codes in a row lock the second step (429)", lastWrong.status === 429, lastWrong.body);
    check("…even the right code waits out the lock", (await call("POST", "/auth/login/mfa", { mfaToken: ch, code: rc[1] })).status === 429);
    sql(`update "User" set "totpLockedUntil"=null, "totpLastStep"=null where id=${a2.user.id}`);
    const renew = await call("POST", "/me/mfa/recovery-codes", { code: totp(secret, stepNow()) }, viaRc.body.accessToken);
    check("new recovery codes (with a current code): the old ones stop working", renew.status === 200 && renew.body.recoveryCodes?.length === 10 && (await call("POST", "/auth/login/mfa", { mfaToken: (await login()).body.mfaToken, code: rc[2] })).status === 400, renew.body);
    const st1 = (await call("GET", "/me/mfa", null, viaRc.body.accessToken)).body;
    check("status: on, 10 recovery codes left, this session verified", st1.enabled === true && st1.recoveryCodesLeft === 10 && st1.sessionVerified === true, st1);
    const sysSec = (await call("GET", "/admin/system", null, viaRc.body.accessToken)).body.security;
    check("System reports admins with and without two-step sign-in", sysSec?.adminTwoStepRequired === false && sysSec.admins >= 2 && sysSec.adminsWithTwoStep >= 1 && sysSec.admins > sysSec.adminsWithTwoStep, sysSec);

    // Required (the production default): an admin session without the second step opens only the set-up
    check("API with ADMIN_MFA_REQUIRED=true started", await startFeeApi({ ADMIN_MFA_REQUIRED: "true" }));
    const plainAdmin = (await callAt(FEE_API, "POST", "/auth/login", { email: `admin${uniq}@example.fi`, password: "strong-pass-123" })).body.accessToken;
    const gated = await callAt(FEE_API, "GET", "/admin/system", null, plainAdmin);
    check("required: an admin without two-step sign-in gets 403 MFA_SETUP_REQUIRED on admin tools", gated.status === 403 && gated.body.code === "MFA_SETUP_REQUIRED", gated.body);
    check("…on admin access through other routes too (orders)", (await callAt(FEE_API, "GET", "/admin/orders", null, plainAdmin)).status === 403);
    const gatedSt = await callAt(FEE_API, "GET", "/me/mfa", null, plainAdmin);
    check("…but can open its account and the set-up", gatedSt.status === 200 && gatedSt.body.required === true && gatedSt.body.sessionVerified === false && (await callAt(FEE_API, "GET", "/me", null, plainAdmin)).status === 200, gatedSt.body);
    check("required: other roles are not affected", (await callAt(FEE_API, "GET", "/me/favorites", null, otherCust.accessToken)).status === 200);
    const reqFirst = await callAt(FEE_API, "POST", "/auth/login", { email: a2Email, password: "strong-pass-123" });
    const reqSecond = await callAt(FEE_API, "POST", "/auth/login/mfa", { mfaToken: reqFirst.body.mfaToken, code: renew.body.recoveryCodes[0] });
    check("required: an admin who passed the second step uses the admin tools", (await callAt(FEE_API, "GET", "/admin/system", null, reqSecond.body.accessToken)).status === 200, reqSecond.body);
    feeApi.kill(); feeApi = null;

    check("turning it off takes the password and a code", (await call("POST", "/me/mfa/disable", { code: renew.body.recoveryCodes[1] }, viaRc.body.accessToken)).status === 400 && (await call("POST", "/me/mfa/disable", { password: "wrong-pass-999", code: renew.body.recoveryCodes[1] }, viaRc.body.accessToken)).status === 400);
    const off = await call("POST", "/me/mfa/disable", { password: "strong-pass-123", code: renew.body.recoveryCodes[1] }, viaRc.body.accessToken);
    check("turned off: password sign-in gives tokens again, everything cleared and audited", off.status === 200 && !!(await login()).body.accessToken && sql(`select ("totpSecret" is null and "totpEnabledAt" is null and cardinality("totpRecoveryCodes") = 0)::text from "User" where id=${a2.user.id}`) === "true" && sql(`select count(*) from "AdminAuditLog" where action='mfa.disable' and "entityId"=${a2.user.id}`) === "1", off.body);
  }

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
  check("health reports v2.13.0", (await (await fetch(`${BASE}/health`)).json()).version === "2.13.0");

  [vendorSock, custSock, otherSock, c1Sock, c2Sock].forEach((s) => s.close());
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
