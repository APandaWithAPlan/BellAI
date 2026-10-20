import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {test} from "node:test";
import {decrypt, encrypt} from "./crypto.js";

const key = randomBytes(32).toString("base64");

test("round trip", () => {
  const blob = encrypt("hello", key, "uid1");
  assert.notEqual(blob, "hello");
  assert.equal(decrypt(blob, key, "uid1"), "hello");
});

test("same plaintext encrypts differently each time", () => {
  assert.notEqual(encrypt("hello", key, "uid1"), encrypt("hello", key, "uid1"));
});

test("wrong uid fails", () => {
  assert.throws(() => decrypt(encrypt("hello", key, "uid1"), key, "uid2"));
});

test("wrong key fails", () => {
  const other = randomBytes(32).toString("base64");
  assert.throws(() => decrypt(encrypt("hello", key, "uid1"), other, "uid1"));
});

test("tampered ciphertext fails", () => {
  const [v, iv, tag] = encrypt("hello", key, "uid1").split(".");
  assert.throws(() => decrypt([v, iv, tag, encrypt("bye", key, "uid1").split(".")[3]].join("."), key, "uid1"));
});

test("rejects a key of the wrong length", () => {
  assert.throws(() => encrypt("hello", "c2hvcnQ=", "uid1"), /32 bytes/);
});
