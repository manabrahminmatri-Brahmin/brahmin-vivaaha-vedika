# mana Vivaaha Vedika — website

Telugu Brahmin matrimony landing page and privacy policy.

## Where to edit

| What | Path |
|------|------|
| **Landing page (use this)** | [`web_deploy/index.html`](web_deploy/index.html) |
| **Privacy policy** | [`web_deploy/privacy.html`](web_deploy/privacy.html) |
| Assets (logo, screenshots, MSME) | [`web_deploy/assets/`](web_deploy/assets/) |

Files in the **repo root** (`index.html`, `privacy.html`) are short redirects only — they point to `web_deploy/` so the repository is not confusing on GitHub.

`web_deploy/index-v2.html` is an old draft; do not edit it for production.

## Live URLs

- GitHub Pages: https://manabrahminmatri-brahmin.github.io/brahmin-vivaaha-vedika/
- Firebase Hosting: https://manabrahminmatri-de0ad.web.app/

## Deploy

**Firebase (primary hosting root = `web_deploy/`):**

```bash
firebase deploy --only hosting
```

**GitHub Pages:** push to `main` — [`.github/workflows/github-pages.yml`](.github/workflows/github-pages.yml) copies `web_deploy/` automatically.

## App

Android: [Google Play](https://play.google.com/store/apps/details?id=com.manavivaahavedika.brahmin)
