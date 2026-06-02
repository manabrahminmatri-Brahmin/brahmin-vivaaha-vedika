# Live website (Firebase & GitHub Pages)

This folder is the **published site**. Edit `index.html`, `privacy.html`, and `terms.html` here — not the old `index.html` in the repo root.

**Assets:** Keep `app_logo.png`, `favicon.png`, and `assets/` (screenshots, MSME logo) in this folder for the live site. If images are missing locally, run: `git checkout HEAD -- web_deploy/app_logo.png web_deploy/favicon.png web_deploy/assets/`

- **Firebase:** `firebase deploy --only hosting` → https://manabrahminmatri-de0ad.web.app
- **GitHub Pages:** push to `main` (workflow copies `web_deploy/` → https://manabrahminmatri-brahmin.github.io/brahmin-vivaaha-vedika/
