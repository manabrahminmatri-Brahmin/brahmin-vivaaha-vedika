# mana Vivaaha Vedika

Flutter matrimony app for the Telugu Brahmin community.

## Website (landing + legal pages)

Edit only **`web_deploy/`** — `index.html`, `privacy.html`, `terms.html`, `refund.html`, plus `assets/`, `favicon.png`, and `app_logo.png`.

| Host | Deploys from | URL |
|------|----------------|-----|
| Firebase Hosting | `web_deploy/` (`firebase.json`) | https://manabrahminmatri-de0ad.web.app |
| GitHub Pages | `web_deploy/` (GitHub Actions) | https://manabrahminmatri-brahmin.github.io/brahmin-vivaaha-vedika/ |

```bash
git add web_deploy
git commit -m "Update website"
git push origin main
```

## App

```bash
flutter pub get
flutter run
```

**Note:** `web/index.html` is the Flutter web build shell — not the marketing site. Do not edit it for landing-page content.
