import { webcrypto } from "node:crypto";

const PBKDF2_SALT_LENGTH = 32;
const IV_LENGTH = 12;
const HKDF_SALT_LENGTH = 32;
const GCM_TAG_LENGTH = 128;
const PBKDF2_ITERATIONS = 310000;

const crypto = webcrypto;
const enc = new TextEncoder();

async function deriveMasterKey(passphrase, pbkdf2Salt) {
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    enc.encode(passphrase),
    "PBKDF2",
    false,
    ["deriveKey"]
  );
  return crypto.subtle.deriveKey(
    { name: "PBKDF2", salt: pbkdf2Salt, iterations: PBKDF2_ITERATIONS, hash: "SHA-256" },
    keyMaterial,
    { name: "AES-GCM", length: 256 },
    true,
    ["encrypt", "decrypt"]
  );
}

async function deriveHKDFKey(passphrase, pbkdf2Salt, hkdfSalt) {
  const masterKey = await deriveMasterKey(passphrase, pbkdf2Salt);
  const masterKeyRaw = await crypto.subtle.exportKey("raw", masterKey);
  const hkdfKey = await crypto.subtle.importKey("raw", masterKeyRaw, "HKDF", false, [
    "deriveKey",
  ]);
  return crypto.subtle.deriveKey(
    { name: "HKDF", salt: hkdfSalt, info: new Uint8Array(), hash: "SHA-256" },
    hkdfKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );
}

function readString(buf) {
  return new TextDecoder().decode(buf);
}

async function decryptHKDFSalted(input, passphrase) {
  const prefix = "%$";
  if (!input.startsWith(prefix)) throw new Error("Expected %$ prefix");

  const b64 = input.slice(prefix.length);
  const binary = new Uint8Array(Buffer.from(b64, "base64"));

  let offset = 0;
  const pbkdf2Salt = binary.slice(offset, offset + PBKDF2_SALT_LENGTH);
  offset += PBKDF2_SALT_LENGTH;
  const iv = binary.slice(offset, offset + IV_LENGTH);
  offset += IV_LENGTH;
  const hkdfSalt = binary.slice(offset, offset + HKDF_SALT_LENGTH);
  offset += HKDF_SALT_LENGTH;
  const ciphertext = binary.slice(offset);

  const key = await deriveHKDFKey(passphrase, pbkdf2Salt, hkdfSalt);
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv, tagLength: GCM_TAG_LENGTH },
    key,
    ciphertext
  );
  return readString(new Uint8Array(decrypted));
}

async function decryptV2(input, passphrase) {
  const data = input.substring(1);
  const ivHex = data.substring(0, 32);
  const saltHex = data.substring(32, 64);
  const b64 = data.substring(64);

  const iv = Buffer.from(ivHex, "hex");
  const salt = Buffer.from(saltHex, "hex");
  const encrypted = Buffer.from(b64, "base64");

  for (const iterations of [310000, 100000]) {
    try {
      const keyMaterial = await crypto.subtle.importKey(
        "raw",
        enc.encode(passphrase),
        "PBKDF2",
        false,
        ["deriveKey"]
      );
      const key = await crypto.subtle.deriveKey(
        { name: "PBKDF2", salt, iterations, hash: "SHA-256" },
        keyMaterial,
        { name: "AES-GCM", length: 256 },
        false,
        ["decrypt"]
      );
      const decrypted = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, encrypted);
      return readString(new Uint8Array(decrypted));
    } catch {
      continue;
    }
  }
  throw new Error("V2 decryption failed");
}

const [encrypted, passphrase] = process.argv.slice(2);
if (!encrypted || !passphrase) {
  process.stderr.write("Usage: node decrypt-setup-uri.mjs <encrypted> <passphrase>\n");
  process.exit(1);
}

let result;
if (encrypted.startsWith("%$")) {
  result = await decryptHKDFSalted(encrypted, passphrase);
} else if (encrypted.startsWith("%~") || encrypted.startsWith("%")) {
  result = await decryptV2(encrypted, passphrase);
} else {
  process.stderr.write("Unrecognised encryption format\n");
  process.exit(1);
}

process.stdout.write(result);
