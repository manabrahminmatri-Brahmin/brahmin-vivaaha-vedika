# Live website (Firebase & GitHub Pages)

This folder is the **published site**. Edit `index.html`, `privacy.html`, `terms.html`, and `refund.html` here only.

After changes, sync to repo root (needed if GitHub Pages uses branch deploy):

```powershell
.\scripts\sync-web-deploy-to-root.ps1
git add web_deploy index.html privacy.html terms.html refund.html assets
git commit -m "Update landing page"
git push origin main
```

**Assets:** Keep `app_logo.png`, `favicon.png`, and `assets/` in this folder.

| Host | URL | Notes |
|------|-----|--------|
| Firebase | https://manabrahminmatri-de0ad.web.app | Deploys `web_deploy/` via `firebase.json` |
| GitHub Pages | https://manabrahminmatri-brahmin.github.io/brahmin-vivaaha-vedika/ | Use **Settings → Pages → GitHub Actions**. If you still see old content, run the sync script above. |
