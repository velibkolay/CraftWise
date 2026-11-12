# Deploying wow.velikopter.com (#99)

Steps for Veli in the Cloudflare dashboard (first draft from #95; #99 finalizes them). Everything here
is on free plans: Workers Free, D1 Free, Zero Trust Free (Access), custom domain, cron trigger,
Workers Logs. **If any screen asks for a paid plan or a payment method, stop and ask first.**

The Worker lives in `web/` (code and API: `web/docs/api.md`). The repo holds no secrets; the only
value set in the dashboard is the Access audience tag.

## 1. D1 database
1. Dashboard > **Storage & Databases > D1 SQL Database > Create**. Name `craftwise`, location
   *Western Europe* (or automatic).
2. Copy its **Database ID** and put it into `web/wrangler.jsonc` under `d1_databases[0].database_id`
   (replacing the zeros). The ID is not a secret; commit it through a PR (or give it to the Scout).
   Deploys fail until it is in.
3. Create the tables, from PowerShell on the PC (Node 22 or newer):
   ```powershell
   cd <CraftWise checkout>\web
   npm ci
   npx wrangler login
   npx wrangler d1 migrations apply craftwise --remote
   ```
   `wrangler login` opens the browser once. Run the last line again whenever a PR adds a file to
   `web/migrations/`, **before merging it**: the Worker deployed from the merge reads the new tables
   at once, and Workers Builds' default token has no D1 permission, so builds don't migrate.
   Migrating first is safe: the running Worker ignores tables it doesn't know. To see what is still
   pending: `npx wrangler d1 migrations list craftwise --remote`.
   Don't paste the SQL into the D1 console instead: wrangler would not know it ran and would try
   again.
4. A PR that adds a migration is applied from its branch, before the merge. For #120
   (`0003_names_sell_price.sql`: class and subclass names, the items' sell price), in PowerShell:
   ```powershell
   cd C:\Users\Veli\Documents\GitHub\craftwise\web
   git fetch origin
   git switch names-sellprice-120
   npx wrangler d1 migrations apply craftwise --remote
   git switch main
   ```
   wrangler lists `0003_names_sell_price.sql` and asks to confirm; answer yes. Then merge the PR. The
   running Worker keeps working in between (it doesn't read the new column or tables yet).

## 2. Worker with Workers Builds
1. **Workers & Pages > Create > Import a repository**, GitHub `velibkolay/CraftWise`.
2. Project name `craftwise-web` (must match `name` in `web/wrangler.jsonc`).
3. Build settings: **Root directory** `web`, **Build command** `npm ci`, **Deploy command**
   `npx wrangler deploy`, production branch `main`. Builds for other branches: off.
4. Optional: **Build watch paths** include `web/*`, so pushes that only change the addon don't build.
5. Save and deploy. Pushes to `main` deploy again (no GitHub Actions change).

The site's page scripts (`web/site/`, #97) are bundled when wrangler deploys: `wrangler.jsonc` has
`build.command` = `npm run build` (esbuild, installed by `npm ci`), which writes `web/public/assets/` (ignored by
git) before the upload. Nothing to change in the build settings; `npm run dev` runs the same build.

## 3. Custom domain
Worker `craftwise-web` > **Settings > Domains & Routes > Add > Custom domain**: `wow.velikopter.com`.
Cloudflare creates the DNS record and the certificate.

## 4. Access for the private part
1. **Zero Trust > Access > Applications > Add an application > Self-hosted**.
2. Name `CraftWise private`. Add the public hostnames, all on `wow.velikopter.com`, with the paths
   `me`, `me/*`, `api/me`, `api/me/*`.
   Do **not** cover `/api/upload` or `/api/private/upload`: the companion app authenticates with its
   upload token, not with Access.
3. Policy: *Allow*, Include > Emails > Veli's address. Login method: One-time PIN (the existing one).
4. Save, then open the application again and copy the **Application Audience (AUD) Tag**.

## 5. Variables
Worker `craftwise-web` > **Settings > Variables and Secrets > Add**:
- `ACCESS_AUD` = the AUD tag from step 4, type **Secret** (deploys never overwrite it).

`ACCESS_TEAM_DOMAIN` (`velikopter.cloudflareaccess.com`) is already in `wrangler.jsonc`. Without
`ACCESS_AUD` the private API answers 503 and stays closed.

## 6. Check
- `https://wow.velikopter.com/` shows the price list (empty until the first upload);
  `https://wow.velikopter.com/api/houses` answers `{"houses":[]}` before the first upload.
- `https://wow.velikopter.com/me` asks for the One-time PIN, then shows the private page (My Characters).
- `https://wow.velikopter.com/api/me` (after the PIN) shows your e-mail.
- `https://wow.velikopter.com/api/upload` without a token answers 401.

## 7. Upload token for the companion
Open `https://wow.velikopter.com/me`, panel **Upload Tokens** (on a phone: the **Tokens** tab). Type a
name (e.g. `Companion PC`) and press **New Token**. The token (`cw_...`) is shown once in the gold
popup: press **Copy** and put it into the companion app (#94), then **Done**. **Revoke** next to a
token stops it at once (after a confirm step under its row).

`GET /api/me/tokens` lists tokens, `DELETE /api/me/tokens/<id>` revokes one (see `web/docs/api.md`).

## 8. Read access for Claude (optional)
A service token lets Claude read `/api/me/*` without the One-time PIN. The Worker lets a service
token (an Access login without an e-mail) only read: `POST` and `DELETE` answer 403 `read_only`.
1. **Zero Trust > Access > Service credentials > Service Tokens > Create**, name `claude-read`,
   duration as you like. Copy the Client ID and the Client Secret (the secret is shown once).
2. Application `CraftWise private` > **Policies > Add a policy**: name `claude-read`, action
   **Service Auth**, Include > Service Token > `claude-read`. Save.
3. Requests send the headers `CF-Access-Client-Id` and `CF-Access-Client-Secret`.
Revoke it under Service Tokens; nothing else changes.

## Watching the free limits
- `https://wow.velikopter.com/api/me/usage`: rows written today (uploads stop at 90,000 of D1's
  100,000) and the database size (free: 500 MB). See "Budget" in `web/docs/api.md`.
- Errors and logs: Worker > **Observability** (Workers Logs, free tier).
- Rollback: Worker > **Deployments** > an earlier version > Rollback.
