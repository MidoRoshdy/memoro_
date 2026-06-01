# Memoro

**Memoro** is a cross-platform mobile and desktop application that connects **patients** (including family **caregiver** accounts) with **care professionals** (doctor flow). It supports day-to-day care coordination: therapeutic **activities**, **medicine** plans and adherence, **real-time chat**, **cognitive games**, and **SOS / emergency help** with location context. The stack is **Flutter** on the client and **Firebase** (Auth, Firestore, Storage, FCM, Cloud Functions) on the backend.

Use the sections below for a **CV or portfolio**: copy the one-liner and bullet points that match the role you are applying for.

---

## One-liner (CV / LinkedIn)

Cross-platform **Flutter** app with **Firebase** backend for patient–caregiver collaboration: activities, medication tracking, chat, games, SOS alerts with geolocation, push notifications, and **Node.js Cloud Functions** (scheduled retries, transactional email OTP for password reset).

---

## What the project does

| Area | Description |
|------|-------------|
| **Users** | Separate flows for **patients/caregivers** and **doctors**; registration, login, forgot-password with email OTP via callable functions. |
| **Care coordination** | Doctor–patient **pairing**; assigned **activities**; **medicine** items with status updates visible to both sides. |
| **Communication** | **Firestore-backed chat** with push notifications on new messages. |
| **Safety** | **SOS / emergency requests** stored in Firestore; high-priority FCM to the connected professional; resolution notifications to the patient. |
| **Engagement** | **Games** tab and **audio** assets for in-app experiences. |
| **Notifications** | FCM, local notifications, deep links; server-side **notification inbox** and **retry** job for failed deliveries. |
| **Internationalization** | **Flutter gen-l10n** with `AppLocalizations` and ARB sources. |

---

## Technology stack

**Client**

- **Flutter** (Dart **^3.9**), Material UI, custom theme and assets  
- **Riverpod** (`flutter_riverpod`) for app state  
- **Firebase**: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_messaging`, `cloud_functions`  
- **Device & UX**: `geolocator`, `image_picker`, `shared_preferences`, `flutter_local_notifications`, `timezone`, `webview_flutter`, `audioplayers`, `url_launcher`, `intl_phone_field`  
- **Platforms**: Android, iOS, **Windows**, **macOS**, Linux, Web (where configured)

**Backend (`functions/`)**

- **Node.js 20**  
- **Firebase Cloud Functions v2**: Firestore triggers (`onDocumentCreated` / `Updated` / `Written`), **scheduled** function (`onSchedule`), **callable** HTTPS functions (`onCall`)  
- **firebase-admin**: Auth, Firestore, **FCM** multicast  
- **nodemailer** (Gmail transport) + **Firebase Secrets** for SMTP (password reset OTP emails)  
- Idempotent **notification IDs**, invalid FCM token cleanup, per-user notification persistence

**DevOps / quality**

- `flutter analyze`, `flutter test`  
- `flutter_native_splash`, `flutter_launcher_icons`  
- Firebase project wiring via **FlutterFire** (`lib/firebase_options.dart`)

---

## Architecture (high level)

```text
┌─────────────────────────────────────────────────────────────┐
│  Flutter app (Riverpod, l10n, FCM, local notifications)      │
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
                ▼                             ▼
   Firestore / Storage / Auth          Cloud Functions (Node)
   (profiles, chats, activity,          (triggers, schedule,
    medicine, emergencyRequests)        callable OTP email)
                │                             │
                └─────────────┬───────────────┘
                              ▼
                     FCM + optional deep links
```

---

## Repository layout

| Path | Role |
|------|------|
| `lib/` | App entry, routing, themes, services, patient/doctor flows |
| `assets/` | Images, audio, navbar and feature icons |
| `functions/` | Cloud Functions (`index.js`), Node dependencies |
| `android/`, `ios/`, `macos/`, `windows/`, `linux/` | Platform runners and native config |

---

## Prerequisites

- **Flutter SDK** and **Dart** (bundled with Flutter)  
- **Git**  
- Editor: VS Code, Cursor, or Android Studio  
- **Android**: Android Studio + SDK  
- **iOS / macOS**: Xcode (macOS)  
- **Windows desktop**: Visual Studio with **Desktop development with C++**

---

## Getting started

1. Clone the repository and enter the project directory.

2. Install Flutter dependencies:

```bash
flutter pub get
```

3. Check your environment:

```bash
flutter doctor
```

4. Run the app:

```bash
flutter run
```

### Windows desktop

```bash
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
```

---

## Firebase setup

The app expects Firebase configuration in `lib/firebase_options.dart`. For a new Firebase project:

1. Install the [FlutterFire CLI](https://firebase.flutter.dev/docs/cli/).  
2. From the project root:

```bash
flutterfire configure
```

3. Deploy **Firestore rules**, **Storage rules**, and **Cloud Functions** as needed for your project.  
4. For **email OTP password reset** in production, configure Firebase **Secrets** for the SMTP-related parameters used by the functions (see `functions/index.js`).

Until real keys are present, the app can skip Firebase initialization in development (see `lib/main.dart`).

---

## Cloud Functions (backend)

From `functions/`:

```bash
npm install
npm run serve    # Firebase emulators, functions only
npm run deploy   # firebase deploy --only functions
```

Requires Firebase CLI login and a linked Firebase project.

---

## Useful commands

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
```

---

## Sharing and security notes

- Do not commit **secrets**, service accounts, or production `.env` files.  
- Prefer **relative paths** in scripts and docs.  
- Optional `.gitattributes` for consistent line endings:

```gitattributes
* text=auto eol=lf
*.bat text eol=crlf
```

---

## License / status

Private / unpublished (`publish_to: "none"` in `pubspec.yaml`). Adjust this section if you open-source the project.
