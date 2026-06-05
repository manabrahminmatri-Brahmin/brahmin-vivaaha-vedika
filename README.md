# Live website (Firebase & GitHub Pages)

**Single source of truth** for the public site. Edit these files here only:

- `index.html` — landing page
- `privacy.html` — privacy policy
- `terms.html` — terms & conditions
- `refund.html` — return & refund policy
- `app_logo.png`, `favicon.png`, `assets/`

Do **not** duplicate these at the repo root. CI deploys this folder directly.

| Host | URL |
|------|-----|
| Firebase | https://manabrahminmatri-de0ad.web.app |
| GitHub Pages | https://manabrahminmatri-brahmin.github.io/brahmin-vivaaha-vedika/ |

```bash
git add web_deploy
git commit -m "Update website"
git push origin main
```
