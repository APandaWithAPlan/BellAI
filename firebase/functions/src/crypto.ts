import {createCipheriv, createDecipheriv, randomBytes} from "node:crypto";

// blob looks like v1.<iv>.<tag>.<ciphertext>, all base64
// the version leaves room to rotate keys later
const VERSION = "v1";

function parseKey(keyBase64: string): Buffer {
  const key = Buffer.from(keyBase64, "base64");
  if (key.length !== 32) {
    throw new Error("ENCRYPTION_KEY must be 32 bytes, base64-encoded");
  }
  return key;
}

// aad ties the blob to a user, so a copy in someone else's doc won't decrypt
export function encrypt(plaintext: string, keyBase64: string, aad: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", parseKey(keyBase64), iv);
  cipher.setAAD(Buffer.from(aad));
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [VERSION, iv.toString("base64"), tag.toString("base64"), ciphertext.toString("base64")].join(".");
}

export function decrypt(blob: string, keyBase64: string, aad: string): string {
  const [version, iv, tag, ciphertext] = blob.split(".");
  if (version !== VERSION || !iv || !tag || ciphertext === undefined) {
    throw new Error("Unsupported ciphertext format");
  }
  const decipher = createDecipheriv("aes-256-gcm", parseKey(keyBase64), Buffer.from(iv, "base64"));
  decipher.setAAD(Buffer.from(aad));
  decipher.setAuthTag(Buffer.from(tag, "base64"));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertext, "base64")),
    decipher.final(),
  ]).toString("utf8");
}
