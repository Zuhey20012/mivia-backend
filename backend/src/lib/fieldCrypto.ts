import crypto from "crypto";
import pino from "pino";
import { env } from "../config/env";

const logger = pino({ name: "field-crypto" });

/**
 * Encryption at rest for single sensitive fields (the DAC7 tax identification number): AES-256-GCM with a
 * random 96-bit IV per value and the row it belongs to as additional authenticated data, so a ciphertext
 * copied to another row does not decrypt. Stored as "v1:" + base64(iv | tag | ciphertext).
 * The key is DATA_ENCRYPTION_KEY: 32 random bytes, base64 (e.g. `openssl rand -base64 32`).
 */
function loadKey(): Buffer | null {
  if (!env.dataEncryptionKey) return null;
  const key = Buffer.from(env.dataEncryptionKey, "base64");
  if (key.length !== 32) {
    logger.error("DATA_ENCRYPTION_KEY is not 32 bytes of base64: encrypted fields are switched off");
    return null;
  }
  return key;
}
const key = loadKey();

/** "ok" | "missing" | "invalid" — for System (never the key itself). */
export function encryptionStatus(): "ok" | "missing" | "invalid" {
  if (key) return "ok";
  return env.dataEncryptionKey ? "invalid" : "missing";
}

export function encryptionConfigured() {
  return key !== null;
}

export function encryptField(plain: string, aad: string): string {
  if (!key) throw new Error("DATA_ENCRYPTION_KEY is not configured");
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(aad, "utf8"));
  const enc = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  return `v1:${Buffer.concat([iv, cipher.getAuthTag(), enc]).toString("base64")}`;
}

/** The plain value, or null when there is no key or the value does not decrypt (wrong key, tampered, other row). */
export function decryptField(stored: string, aad: string): string | null {
  if (!key || !stored.startsWith("v1:")) return null;
  try {
    const raw = Buffer.from(stored.slice(3), "base64");
    const decipher = crypto.createDecipheriv("aes-256-gcm", key, raw.subarray(0, 12));
    decipher.setAAD(Buffer.from(aad, "utf8"));
    decipher.setAuthTag(raw.subarray(12, 28));
    return Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]).toString("utf8");
  } catch {
    return null;
  }
}
