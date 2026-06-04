# mana Vivaaha Vedika

Flutter matrimony app for the Telugu Brahmin community.

## App

```bash
flutter pub get
flutter run
```

Build release:

```bash
flutter build appbundle
# or: flutter build apk
```

## Firebase

Deploy rules, indexes, storage, and functions from the project root:

```bash
firebase deploy --only firestore,database,storage,functions
```

Project: `manabrahminmatri-de0ad` (see `.firebaserc`).

**Note:** `web/index.html` is the Flutter web build shell, not a separate marketing site.
