# mana Vivaaha Vedika

Flutter matrimony app for the Telugu Brahmin community.

## Website (landing + legal pages)

Edit only **`web_deploy/`** — `index.html`, `privacy.html`, `terms.html`, `refund.html`, plus `assets/`, `favicon.png`, and `app_logo.png`.

| Host | Deploys from | URL |
|------|----------------|-----|
| Firebase Hosting | `web_deploy/` (`firebase.json`) | https://manabrahminmatri-de0ad.web.app |
| GitHub Pages | `web_deploy/` → `gh-pages` branch (GitHub Actions) | https://manabrahminmatri-brahmin.github.io/brahmin-vivaaha-vedika/ |

### GitHub Pages shows README instead of the website?

1. Push website files (see commands below).
2. Wait for **Actions** → **Deploy GitHub Pages** to finish (green).
3. **Settings** → **Pages** → **Build and deployment**:
   - **Source:** Deploy from a branch
   - **Branch:** `gh-pages` → folder **`/ (root)`**
4. Hard refresh the site (Ctrl+F5).

Do **not** use `main` as the Pages branch — that serves this README file.

```bash
git add web_deploy .github/workflows/github-pages.yml
git commit -m "Update website"
git push origin main
```

## App

```bash
flutter pub get
flutter run
```

**Note:** `web/index.html` is the Flutter web build shell — not the marketing site. Do not edit it for landing-page content.
