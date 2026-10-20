import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import {setGlobalOptions} from "firebase-functions/v2";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {decrypt, encrypt} from "./crypto.js";

// same region as firestore
setGlobalOptions({region: "us-central1", maxInstances: 10});
initializeApp();

const ENCRYPTION_KEY = defineSecret("ENCRYPTION_KEY");
const MAX_PAYLOAD_BYTES = 100_000;

const userDoc = (uid: string) => getFirestore().collection("users").doc(uid);

// must be signed in (anonymus counts)
function requireUid(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  return request.auth.uid;
}

// encrypts a json object into users/{uid}.payload
export const saveUserData = onCall({secrets: [ENCRYPTION_KEY]}, async (request) => {
  const uid = requireUid(request);
  const data: unknown = request.data?.data;
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "`data` must be a JSON object.");
  }
  const json = JSON.stringify(data);
  if (Buffer.byteLength(json) > MAX_PAYLOAD_BYTES) {
    throw new HttpsError("invalid-argument", "`data` is too large.");
  }
  await userDoc(uid).set({
    payload: encrypt(json, ENCRYPTION_KEY.value(), uid),
    updatedAt: new Date(),
  });
  return {ok: true};
});

// decrypts it back, null if nothing saved
export const getUserData = onCall({secrets: [ENCRYPTION_KEY]}, async (request) => {
  const uid = requireUid(request);
  const payload = (await userDoc(uid).get()).get("payload");
  if (typeof payload !== "string") {
    return {data: null};
  }
  try {
    return {data: JSON.parse(decrypt(payload, ENCRYPTION_KEY.value(), uid))};
  } catch {
    throw new HttpsError("internal", "Stored data could not be decrypted.");
  }
});

export const deleteUserData = onCall(async (request) => {
  await userDoc(requireUid(request)).delete();
  return {ok: true};
});
