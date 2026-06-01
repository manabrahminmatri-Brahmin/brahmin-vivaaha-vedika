# Deploy website to Firebase Hosting (GitHub Actions)

The workflow [`.github/workflows/firebase-hosting.yml`](workflows/firebase-hosting.yml) deploys the `web_deploy/` folder to Firebase Hosting when you push to `main` or `master`.

**Live site (after deploy):**  
https://manabrahminmatri-de0ad.web.app  
https://manabrahminmatri-de0ad.firebaseapp.com

---

## One-time setup

### 1. Commit hosting files

Make sure these are in Git:

- `web_deploy/` (including `web_deploy/assets/app_logo.png`)
- `firebase.json`
- `.firebaserc`
- `.github/workflows/firebase-hosting.yml`

### 2. Create a Firebase service account key

1. Open [Firebase Console](https://console.firebase.google.com/) → project **manabrahminmatri-de0ad**
2. **Project settings** (gear) → **Service accounts**
3. Click **Generate new private key** → save the JSON file securely (do not commit it)

### 3. Add GitHub secret

1. GitHub repo → **Settings** → **Secrets and variables** → **Actions**
2. **New repository secret**
3. Name: `FIREBASE_SERVICE_ACCOUNT`
4. Value: paste the **entire** contents of the JSON file from step 2

### 4. Push to GitHub

```bash
git add web_deploy firebase.json .firebaserc .github
git commit -m "Add Firebase Hosting and GitHub deploy workflow"
git push origin main
```

Check **Actions** tab — the workflow should run and deploy.

---

## Manual deploy (from your PC)

```bash
cd brahmin_Vivaaha_Vedika
firebase login
firebase deploy --only hosting
```

---

## Deploy only hosting (not Firestore/Functions)

The workflow uses `FirebaseExtended/action-hosting-deploy` with `channelId: live`, which deploys **Hosting only** (not rules, functions, or database).

To deploy everything locally:

```bash
firebase deploy
```
