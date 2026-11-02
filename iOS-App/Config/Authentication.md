# Firebase email/password authentication MVP

The app supports signup, login, Settings → Log Out, and session restoration. Firebase Authentication owns the session; BellAI does not save passwords in UserDefaults, files, Firestore, or its own Keychain entries.

## Xcode and Firebase setup

1. Open `iOS-App/BellAI.xcodeproj`. The iOS deployment target is 17.0.
2. In Firebase Console, select your project and register an Apple app with the exact bundle identifier shown in Xcode → BellAI target → Signing & Capabilities. The current identifier is `com.nicholascervantes.bellai.app`.
3. Download that app's `GoogleService-Info.plist`, place it at `BellAI/GoogleService-Info.plist`, and make sure it belongs to the BellAI target and is included in the app bundle. This repository already contains a configuration file; replace it only if using a different Firebase app/project.
4. In Firebase Console → Authentication → Sign-in method, enable **Email/Password** (not email-link sign-in) and save. The app will show an actionable error if this provider is disabled.
5. In Xcode → Package Dependencies, verify `https://github.com/firebase/firebase-ios-sdk` is present. It is already configured through Swift Package Manager, and `FirebaseAuth` is linked to BellAI. Keep the existing Firebase products used by other features.
6. Select your signing team and a simulator or device, then build and run. No custom authentication backend, new Firestore collection, or Cloud Functions deployment is required for authentication.

References: [Firebase Apple setup](https://firebase.google.com/docs/ios/setup), [Email/password authentication](https://firebase.google.com/docs/auth/ios/password-auth), [Authentication state listener](https://firebase.google.com/docs/auth/ios/start).

## Code map

- `BellAI/BellAIApp.swift`: calls `FirebaseApp.configure()` once before rendering the app.
- `BellAI/Services/FirebaseAuthService.swift`: official Firebase signup/login/logout APIs and auth-state listener registration/removal.
- `BellAI/ViewModels/AuthViewModel.swift`: session state, basic validation, loading, and readable errors. The listener determines navigation after both startup and account changes.
- `BellAI/Views/LoginView.swift`: email, secure password field, Log In and Register. Register opens `SignUpView.swift` with first name, last name, email, password, and Sign Up. Password input exists only in memory and is cleared after submission or leaving the screen.
- `BellAI/ContentView.swift`: shows a restoration indicator until the first listener callback, then Login or the existing main app. Main app state is recreated per UID.
- `BellAI/Views/SettingsView.swift`: Log Out button and logout errors. Pending task saves finish before sign-out; data calls never create anonymous sessions.

Firebase restores an existing registered user's session on startup. A legacy anonymous session stays behind the Login screen; this MVP does not migrate or link anonymous accounts. Their previously saved data is not deleted, but a newly registered account has its own UID and data. Existing task storage remains unchanged on the backend.

The login screen performs basic email and nonempty-password checks; signup requires at least six characters. Firebase enforces the project's actual password policy. Registration saves the trimmed first and last name together in Firebase Authentication’s `displayName` (for example, `Maya Chen`). Firebase Auth has no separate first-name/last-name fields; no Firestore profile is created. The email and password are managed by Firebase Auth. If saving the name fails after account creation, Sign Up retries just the name update. Returning to Login leaves the created account intact and signs it out. No password reset, verification, social providers, or new database features are included.

## Verification on a configured project

Use test accounts, not production credentials:

1. Fresh install / logged-out launch: Login appears, without main navigation.
2. Submit blank email, malformed email, empty password, or a short signup password: a validation error appears without a request.
3. Tap Register, enter first and last name, an unused email, and a valid password, then tap Sign Up: the main app opens. Verify the display name and email in Firebase Authentication. Blank names are rejected.
4. Stop and relaunch the app: the main app opens after session restoration without asking for a password.
5. Settings → Log Out: Login returns. Restart: Login remains visible.
6. Log In with the same credentials: the main app opens. Try a wrong password: a readable error appears and the screen remains on Login.
7. Try signup with an existing email, or disconnect networking and submit: an error appears and controls become usable again.
8. Switch between two accounts: previous tasks/chat/navigation do not carry into the new session. Existing camera configurations and device permissions remain device-level settings.

Live account creation and provider enablement must be checked against the configured Firebase project; a successful local build alone does not verify them.

## Temporary local test login (Debug builds only)

Log In with `admin@bellai.com` / `admin1234` in an Xcode Debug build. Its first name is `Admin` and last name is `NotSoInt`; Home displays `Good morning, Admin` and avatar initials `AN`. This account is checked locally and is not registered with Firebase. Incorrect passwords for this address are rejected locally. Register does not create a Firebase account for the reserved test address in Debug builds.

The session and its tasks are kept in memory and reset on logout or app restart. Settings labels the local test account. AI responses, weather, Health access, and camera streams still require their normal services and permissions. Real emails continue through Firebase Authentication. Release builds exclude the local credential check and temporary task store.

## Account details

Tap the profile icon in Settings to edit your first name, last name, login email, and password, then tap Save. Names update the Firebase Authentication display name and the Home greeting. “Username” refers to the login email; there is no separate handle.

Changing email or password requires the current password. Leave the new password and confirmation blank to keep the password. Email changes send a verification link to the new address via Firebase's `sendEmailVerification(beforeUpdatingEmail:)`; the current login email remains active until verification. Password changes use reauthentication followed by `updatePassword(to:)`. Passwords are never prefilled or stored by the app and are cleared after submission and dismissal. Saving names, changing passwords, and requesting email verification are separate operations; failures after the name/password save explicitly explain which changes succeeded.

The form validates required names, email format, minimum password length, and matching confirmation, disables editing/dismissal during saving, and shows success or error feedback. The local Debug account supports name changes for the current session only; its email/password cannot be changed.

Manual checks with a disposable Firebase account:

1. Open Settings → profile icon; verify names and login email are prefilled and password fields are empty.
2. Save changed names only; verify the Home greeting and persistence after logout/login.
3. Check empty names, malformed email, short new password, missing current password, and mismatched confirmation.
4. Try an incorrect current password; verify the password/email remain unchanged and partial-save feedback is accurate.
5. Change the password; log out and confirm only the new password works.
6. Change email; verify the message explains the pending state, follow the email link, then sign in using the new address.
7. Disconnect networking during saving; verify errors and enabled retry controls.

Reference: https://firebase.google.com/docs/auth/ios/manage-users
