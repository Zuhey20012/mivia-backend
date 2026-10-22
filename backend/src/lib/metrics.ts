import { monitorEventLoopDelay } from "perf_hooks";
import type { Request, Response, NextFunction } from "express";
import pino from "pino";
import { scale } from "../config/scale";

/**
 * In-process metrics, cheap enough to keep on all the time: request counts, error counts and latency percentiles per
 * route (the route pattern, never the raw URL, so ids and query strings do not explode the key space), event-loop
 * lag and memory. Each instance reports its own numbers (GET /api/v1/admin/metrics); every LATENCY_LOG_INTERVAL_MS
 * (5 min) the window's p50/p95/p99 per route is written to the log and a new window starts.
 */
const logger = pino({ name: "metrics" });

const MAX_SAMPLES_PER_ROUTE = 2_000; // reservoir sampling keeps percentiles honest with bounded memory
const MAX_ROUTES = 500;

type RouteWindow = { count: number; errors5xx: number; errors4xx: number; samples: number[]; seen: number; maxMs: number };

const startedAt = Date.now();
let windowStartedAt = Date.now();
let window = new Map<string, RouteWindow>();
let lastSummary: ReturnType<typeof summarise> | null = null;
const totals = { requests: 0, errors5xx: 0, errors4xx: 0 };
let inFlight = 0;

const loop = monitorEventLoopDelay({ resolution: 20 });
loop.enable();

function routeKey(req: Request): string {
  // req.route is set once a route matched; the base URL of the router + its path is the pattern
  const route = (req as any).route?.path;
  if (route) return `${req.method} ${req.baseUrl}${typeof route === "string" ? route : String(route)}`;
  return `${req.method} (unmatched)`;
}

function record(key: string, ms: number, status: number) {
  totals.requests++;
  if (status >= 500) totals.errors5xx++;
  else if (status >= 400) totals.errors4xx++;
  let w = window.get(key);
  if (!w) {
    if (window.size >= MAX_ROUTES) key = "(other)";
    w = window.get(key) ?? { count: 0, errors5xx: 0, errors4xx: 0, samples: [], seen: 0, maxMs: 0 };
    window.set(key, w);
  }
  w.count++;
  if (status >= 500) w.errors5xx++;
  else if (status >= 400) w.errors4xx++;
  if (ms > w.maxMs) w.maxMs = ms;
  w.seen++;
  if (w.samples.length < MAX_SAMPLES_PER_ROUTE) w.samples.push(ms);
  else {
    const i = Math.floor(Math.random() * w.seen);
    if (i < MAX_SAMPLES_PER_ROUTE) w.samples[i] = ms;
  }
}

/** Express middleware: measures every request from arrival to the last byte sent. */
export function metricsMiddleware(req: Request, res: Response, next: NextFunction) {
  const start = process.hrtime.bigint();
  inFlight++;
  let done = false;
  const finish = () => {
    if (done) return;
    done = true;
    inFlight--;
    if (req.path === "/health" || req.path === "/health/ready") return; // probes would drown the real traffic
    record(routeKey(req), Number(process.hrtime.bigint() - start) / 1e6, res.statusCode);
  };
  res.on("finish", finish);
  res.on("close", finish);
  next();
}

function pct(sorted: number[], p: number) {
  if (!sorted.length) return 0;
  const i = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return Math.round(sorted[Math.max(0, i)] * 10) / 10;
}

function summarise(now = Date.now()) {
  const seconds = Math.max(1, (now - windowStartedAt) / 1000);
  const routes = [...window.entries()].map(([route, w]) => {
    const sorted = [...w.samples].sort((a, b) => a - b);
    return {
      route, count: w.count, perSecond: Math.round((w.count / seconds) * 100) / 100,
      errors5xx: w.errors5xx, errors4xx: w.errors4xx,
      p50: pct(sorted, 50), p95: pct(sorted, 95), p99: pct(sorted, 99), maxMs: Math.round(w.maxMs),
    };
  }).sort((a, b) => b.count - a.count);
  const count = routes.reduce((s, r) => s + r.count, 0);
  const errors5xx = routes.reduce((s, r) => s + r.errors5xx, 0);
  return {
    from: new Date(windowStartedAt).toISOString(), to: new Date(now).toISOString(), seconds: Math.round(seconds),
    requests: count, perSecond: Math.round((count / seconds) * 100) / 100,
    errorRate5xx: count ? Math.round((errors5xx / count) * 10_000) / 10_000 : 0,
    routes,
  };
}

function eventLoop() {
  const ms = (n: number) => Math.round((n / 1e6) * 10) / 10;
  return { meanMs: ms(loop.mean || 0), p50Ms: ms(loop.percentile(50) || 0), p99Ms: ms(loop.percentile(99) || 0), maxMs: ms(loop.max || 0) };
}

/** Closes the current window: logs it (top routes by traffic) and starts a new one. */
export function rollWindow() {
  const summary = summarise();
  const lag = eventLoop();
  lastSummary = summary;
  window = new Map();
  windowStartedAt = Date.now();
  loop.reset();
  if (summary.requests) {
    logger.info({ window: { ...summary, routes: summary.routes.slice(0, 25) }, eventLoop: lag, heapUsedMb: Math.round(process.memoryUsage().heapUsed / 1048576) }, "Latency summary (ms per route, p50/p95/p99)");
  }
  return summary;
}

let timer: NodeJS.Timeout | null = null;
export function startLatencyLog() {
  if (timer || !scale.latencyLogIntervalMs) return;
  timer = setInterval(rollWindow, scale.latencyLogIntervalMs);
  timer.unref();
}
export function stopLatencyLog() {
  if (timer) clearInterval(timer);
  timer = null;
}

/** Everything /admin/metrics shows, apart from the parts other modules own (DB pool, sockets, queue). */
export function metricsSnapshot() {
  const mem = process.memoryUsage();
  const mb = (n: number) => Math.round((n / 1048576) * 10) / 10;
  return {
    pid: process.pid,
    uptimeSeconds: Math.round((Date.now() - startedAt) / 1000),
    eventLoopLag: eventLoop(),
    memory: { rssMb: mb(mem.rss), heapUsedMb: mb(mem.heapUsed), heapTotalMb: mb(mem.heapTotal), externalMb: mb(mem.external) },
    requests: {
      inFlight,
      sinceStart: { ...totals, errorRate5xx: totals.requests ? Math.round((totals.errors5xx / totals.requests) * 10_000) / 10_000 : 0 },
      currentWindow: summarise(),
      previousWindow: lastSummary,
    },
  };
}
