// Shared helpers for the load-test scenarios. LOCAL TEST SETUP ONLY: tokens are minted with the throwaway JWT secret
// of the test API, and ids are read from the seeded throwaway database (seed-scale.js).
const { Client } = require("pg");
const jwt = require("jsonwebtoken");

const BASE = (process.env.LOADTEST_BASE || "http://localhost:4565").replace(/\/+$/, "");
const DATABASE_URL = process.env.DATABASE_URL || "postgresql://postgres:test@localhost:56432/malvoya_scale";
const JWT_SECRET = process.env.JWT_SECRET || "e2e-only-access-secret-0123456789abcdef";

function assertThrowaway() {
  if (!/localhost|127\.0\.0\.1/.test(BASE) || !/localhost|127\.0\.0\.1/.test(DATABASE_URL) || !/scale|loadtest/i.test(DATABASE_URL)) {
    console.error("Refusing: load tests run only against a local API and a local database named *scale* or *loadtest*.");
    process.exit(1);
  }
}

async function db() {
  const c = new Client({ connectionString: DATABASE_URL });
  await c.connect();
  return c;
}

function token(user) {
  return jwt.sign({ id: user.id, role: user.role, email: user.email, typ: "access" }, JWT_SECRET, { algorithm: "HS256", expiresIn: "2h" });
}

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
// A different client address per request, so the per-IP limiter (600 / 15 min) measures the API, not the limiter
const ip = () => `10.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${1 + Math.floor(Math.random() * 250)}`;

/** Prints the numbers that go into docs/scaling/load-test-results.md. */
function report(name, r) {
  const non2xx = r.non2xx || 0;
  const line = {
    scenario: name,
    connections: r.connections,
    durationSec: r.duration,
    requests: r.requests.total,
    reqPerSec: Math.round(r.requests.average),
    latencyMs: { p50: r.latency.p50, p90: r.latency.p90, p97_5: r.latency.p97_5, p99: r.latency.p99, max: r.latency.max },
    errors: r.errors, timeouts: r.timeouts, non2xx,
    statusCodes: r.statusCodeStats,
  };
  console.log(JSON.stringify(line));
  return line;
}

module.exports = { BASE, DATABASE_URL, assertThrowaway, db, token, pick, ip, report };
