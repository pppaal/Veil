# Hosting the privacy policy (GitHub Pages)

Google Play and the App Store both require a **publicly reachable privacy
policy URL**. The bilingual (KO/EN) policy lives in [`site/index.html`](../site/index.html)
and is published with the [`.github/workflows/pages.yml`](../.github/workflows/pages.yml)
workflow.

## Public URL

```
https://pppaal.github.io/Veil/
```

- Defaults to Korean; `#en` shows English (`https://pppaal.github.io/Veil/#en`).
- The page source of truth is `site/index.html`. The Markdown copies in
  `docs/privacy-policy-ko.md` / `-en.md` are kept for reference and review.

## One-time setup (required once)

The deploy workflow is already committed, but GitHub Pages must be switched on:

1. Repo **Settings → Pages**.
2. **Build and deployment → Source → "GitHub Actions"**.
3. Merge this branch to `main` (the workflow triggers on `main`), or open the
   **Actions** tab → "Deploy privacy policy to GitHub Pages" → **Run workflow**.
4. Wait for the run to finish; the live URL appears in the run summary and at
   Settings → Pages.

After that, any push to `main` that changes `site/` redeploys automatically.

## Updating the policy

Edit `site/index.html` (and keep the Markdown copies in sync if you rely on
them for review), commit to `main`, and the workflow redeploys. Update the
"Last updated" date in both languages when the content changes.

## Custom domain (optional, later)

If you later move to `https://veil.app/privacy`, add a `site/CNAME` file with
the domain and configure DNS per GitHub's custom-domain docs. The in-app and
store references already point at `veil.app/privacy`, so a custom domain keeps
those links valid without code changes.
