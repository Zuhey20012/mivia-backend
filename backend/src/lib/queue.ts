import pino from "pino";
import type { Queue as BullQueue, Worker as BullWorker, Job } from "bullmq";
import { scale } from "../config/scale";
import { createRedisClient, redis, redisEnabled, rkey } from "./redis";
import { reportError } from "./sentry";

/**
 * A small background-work queue for slow side work (push fan-out, emails, catalogue imports).
 *  - Without REDIS_URL: jobs run in this process right after the caller continues (setImmediate), as before, with
 *    retries and backoff in memory. A restart loses jobs that were still waiting for a retry (as before).
 *  - With REDIS_URL: jobs go to BullMQ. They are processed in this process (WORKER_MODE=inline, default) or by a
 *    separate `node dist/worker.js` (WORKER_MODE=api on the web service). Jobs survive restarts.
 * A job that fails every attempt is written to the dead-letter log (job name, id, attempts, error: never its data,
 * which can hold addresses or device tokens) and, with Redis, to the `dead-letter` list (last 1000).
 */
const logger = pino({ name: "queue" });

export type JobOptions = { attempts?: number; backoffMs?: number };
type Definition = { handler: (data: any) => Promise<unknown>; attempts: number; backoffMs: number };

const definitions = new Map<string, Definition>();
const QUEUE_NAME = "jobs";
let queue: BullQueue | null = null;
let worker: BullWorker | null = null;
const local = { running: 0, waitingRetry: 0, completed: 0, failed: 0, deadLettered: 0 };
const retryTimers = new Set<NodeJS.Timeout>();

/** Registers what a job name does. Call at module load in a module both the API and the worker import. */
export function defineJob<T>(name: string, handler: (data: T) => Promise<unknown>, opts: JobOptions = {}) {
  definitions.set(name, { handler, attempts: opts.attempts ?? 5, backoffMs: opts.backoffMs ?? 2_000 });
}

function deadLetter(name: string, id: string | undefined, attempts: number, err: any) {
  local.deadLettered++;
  logger.error({ job: name, jobId: id, attempts, err: err?.message }, "Job failed on every attempt (dead letter)");
  reportError(err, { tags: { job: name } });
  const r = redis();
  if (r) {
    const entry = JSON.stringify({ job: name, jobId: id, attempts, error: String(err?.message ?? err).slice(0, 500), at: new Date().toISOString() });
    r.multi().lpush(rkey("dead-letter"), entry).ltrim(rkey("dead-letter"), 0, 999).exec().catch(() => {});
  }
}

function runLocal(name: string, def: Definition, data: unknown, attempt: number) {
  local.running++;
  def.handler(data)
    .then(() => { local.completed++; })
    .catch((err) => {
      if (attempt >= def.attempts) { local.failed++; return deadLetter(name, undefined, attempt, err); }
      logger.warn({ job: name, attempt, err: err?.message }, "Job failed; retrying");
      local.waitingRetry++;
      const t = setTimeout(() => {
        retryTimers.delete(t);
        local.waitingRetry--;
        runLocal(name, def, data, attempt + 1);
      }, def.backoffMs * 2 ** (attempt - 1));
      t.unref();
      retryTimers.add(t);
    })
    .finally(() => { local.running--; });
}

function getQueue(): BullQueue {
  if (!queue) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { Queue } = require("bullmq") as typeof import("bullmq");
    queue = new Queue(QUEUE_NAME, { connection: createRedisClient("queue", { blocking: true }), prefix: rkey("bull") });
    queue.on("error", (err) => logger.error({ err: err?.message }, "Queue error"));
  }
  return queue;
}

/** Adds a job. Never throws for the caller: if Redis cannot take it, it runs in this process instead. */
export async function enqueue<T>(name: string, data: T): Promise<void> {
  const def = definitions.get(name);
  if (!def) throw new Error(`Unknown job ${name}`);
  if (redisEnabled()) {
    try {
      await getQueue().add(name, data as any, {
        attempts: def.attempts,
        backoff: { type: "exponential", delay: def.backoffMs },
        removeOnComplete: { age: 3_600, count: 1_000 },
        removeOnFail: { age: 7 * 86_400, count: 5_000 },
      });
      return;
    } catch (err: any) {
      logger.warn({ job: name, err: err?.message }, "Queue unavailable; running the job in this process");
    }
  }
  setImmediate(() => runLocal(name, def, data, 1));
}

/** True when jobs leave this process (Redis): callers cannot know the outcome right away. */
export function queueIsRemote() {
  return redisEnabled();
}

/** Starts processing queued jobs in this process (only with Redis; without it jobs always run where they are added). */
export function startQueueWorker() {
  if (!redisEnabled() || worker) return;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { Worker } = require("bullmq") as typeof import("bullmq");
  worker = new Worker(
    QUEUE_NAME,
    async (job: Job) => {
      const def = definitions.get(job.name);
      if (!def) throw new Error(`Unknown job ${job.name}`);
      return def.handler(job.data);
    },
    { connection: createRedisClient("worker", { blocking: true }), prefix: rkey("bull"), concurrency: scale.queueConcurrency },
  );
  worker.on("failed", (job, err) => {
    if (!job) return;
    const attempts = job.opts.attempts ?? 1;
    if (job.attemptsMade >= attempts) deadLetter(job.name, job.id, job.attemptsMade, err);
    else logger.warn({ job: job.name, jobId: job.id, attempt: job.attemptsMade, err: err?.message }, "Job failed; retrying");
  });
  worker.on("error", (err) => logger.error({ err: err?.message }, "Worker error"));
  logger.info({ concurrency: scale.queueConcurrency }, "Queue worker started");
}

/** Stops taking new jobs and waits for running ones (graceful shutdown). */
export async function stopQueue() {
  for (const t of retryTimers) clearTimeout(t);
  retryTimers.clear();
  await worker?.close().catch(() => {});
  await queue?.close().catch(() => {});
  worker = null;
  queue = null;
}

export async function queueStats() {
  const base = { backend: redisEnabled() ? "bullmq" : "in-process", workerHere: redisEnabled() ? !!worker : true, local: { ...local } };
  if (!redisEnabled()) return base;
  try {
    const r = redis()!;
    const [counts, deadLetters] = await Promise.all([
      getQueue().getJobCounts("waiting", "active", "delayed", "failed", "completed"),
      r.llen(rkey("dead-letter")),
    ]);
    return { ...base, counts, deadLetters };
  } catch {
    return { ...base, counts: null };
  }
}
