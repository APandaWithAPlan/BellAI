# BellAI Firebase backend

Firestore + callable Cloud Functions (TypeScript, Node 22). Sensitive user data is encrypted with AES-256-GCM inside the functions; the key lives in Secret Manager as `ENCRYPTION_KEY`. Clients never write to Firestore directly (see `firestore.rules`).

## One-time setup

1. In the [Firebase console](https://console.firebase.google.com), create a project, upgrade it to the **Blaze** plan (required for Functions and Secret Manager), and create a Firestore database in `us-central1` (the region cannot change later; keep it in sync with `setGlobalOptions` in `functions/src/index.ts`).
2. Enable **Authentication → Anonymous**.
3. Register an iOS app with bundle ID `com.nicholascervantes.bellai.app`. Set the Xcode target's `PRODUCT_BUNDLE_IDENTIFIER` to the same value before adding `GoogleService-Info.plist`, or Firebase will reject the app.
4. Put the project ID in `.firebaserc`.
5. Set the encryption key (32 random bytes, base64):

   ```sh
   openssl rand -base64 32 | npx firebase-tools functions:secrets:set ENCRYPTION_KEY
   ```

## Develop

```sh
cd functions
npm install
npm test      # builds and runs the crypto tests
npm run serve # emulators; put a test key in functions/.secret.local as ENCRYPTION_KEY=<base64>
npm run deploy
```

## Functions

| Function | Input | Result |
| --- | --- | --- |
| `saveUserData` | `{data: {...}}` | encrypts and stores under `users/{uid}.payload` |
| `getUserData` | none | `{data: {...} \| null}` |
| `deleteUserData` | none | deletes `users/{uid}` |

All require a signed-in (anonymous is fine) user. Ciphertext is bound to the uid, so a blob copied to another user's document will not decrypt.
