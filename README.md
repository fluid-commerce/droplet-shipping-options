## README

> ### ⚠️ This repository currently contains two apps
>
> A **Next.js** app is being migrated in alongside the existing **Rails 8** app.
> Both run against the same PostgreSQL database. The Rails app is still the one
> deployed and the one every installation points at; the Next app takes no
> traffic until an installation's registrations are repointed at it.
>
> **Only the Fluid-facing half is ported.** The Next app answers the four
> callbacks and the webhook. The merchant UI an operator opens from inside Fluid
> — shipping methods, the rate tables and their CSV importer, the React rate
> editor, the subscriber toggle — is still Rails only, so **Rails is not being
> retired by this work**. See [`CUTOVER.md`](CUTOVER.md) step 5.
>
> See [Next.js app](#nextjs-app) below and [`CUTOVER.md`](CUTOVER.md).

Droplets are integrations between third-party services and Fluid. This one
prices shipping: it answers Fluid's `update_cart_shipping` callback with the
options a company has configured for the cart's destination, priced from its own
`shipping_options` / `rates` tables by weight band and region.

Three further callbacks exist only to support one feature —
free shipping for subscribers. `cart_customer_logged_in` asks Fluid whether the
shopper holds a `yoli_plus` subscription and records the answer against the cart;
`update_cart_email` and `verify_email_success` throw that record away when the
cart's email moves to someone else. The calculation callback only ever reads it,
because it runs on the blocking checkout path.

Documentation can be found in the [project's GitHub page](https://fluid-commerce.github.io/droplet-template/)

## Next.js app

The Next.js port of this droplet. Same database, same Fluid integration points,
plus callback signature verification via `@fluid-app/droplet-sdk`.

### Layout

| Path | What |
|---|---|
| `src/` | The Next app — **and its project directory**. `next.config.ts`, `tsconfig.json` and `next-env.d.ts` live here, not at the repo root. |
| `src/app/api/callbacks/` | The four callback routes, one directory per Fluid definition name in kebab-case |
| `src/lib/shipping/` | The port of `ShippingCalculationService`, `CartSessionService` and `MetafieldSubscriptionService` |
| `src/lib/` | Fluid client, settings, callbacks, handlers, events, permissions |
| `src/instrumentation.ts` | Boot-time probe: reports whether any callback registration tokens are stored |
| `prisma/schema.prisma` | The **existing Rails tables**, mapped with `@@map`/`@map` |
| `db/migrate/` | Rails owns the schema, including `fluid_callback_registrations` — the Next app runs no migration step |
| `scripts/` | `cutover.ts`, `smoke-next.sh`, `backfill-callback-tokens.ts`, `create-admin.ts`, `create-default-settings.ts` |
| `vendor/droplet-sdk/` | Temporary vendored copy of the SDK — see below |
| `Dockerfile.next` | Production image (the Rails `docker/Dockerfile` still builds the Rails service) |
| `.github/workflows/ci-next.yml` | Lint / typecheck / test / build / docker |

**The two apps serve different paths.** Rails answers `POST /webhook` and
`POST /callbacks/<local_name>`; Next answers `POST /api/webhooks` and
`POST /api/callbacks/<kebab-definition-name>`. The full mapping, including the
one definition whose Rails route name is not its Fluid definition name, is in
[`CUTOVER.md`](CUTOVER.md).

**Why `next.config.ts` is inside `src/`.** Next resolves its app directory with
`findDir(root, "app")`, which prefers `<root>/app` over `<root>/src/app` and
cannot be overridden. This repo still contains Rails' `app/`, so building from
the repo root makes Next scan Rails' directory and emit an empty app. Next is
therefore pointed at `src` as its project directory — `next build src`. When
Rails is removed, those three config files move up one level and the commands
drop the `src` argument. No source file moves and no import path changes.

### Commands

```bash
pnpm install
pnpm db:generate          # prisma generate
pnpm dev                  # next dev src
pnpm build                # prisma generate && next build src
pnpm test                 # vitest
pnpm lint
pnpm typecheck

pnpm setup:create-admin   # ADMIN_EMAIL / ADMIN_PASSWORD
pnpm settings:defaults    # create the default `settings` rows
pnpm backfill:callbacks   # copy callback verification tokens out of Fluid
pnpm cutover status <shop>
```

The Rails frontend's Vite build is still here under `pnpm build:vite` and
`pnpm test:jest`. The repo's JS toolchain moved from yarn to pnpm when the Next
app took over the root `package.json`; `ci.yml`, `docker/Dockerfile*`, `makefile`,
`Procfile.dev` and `bin/setup` were updated to match, and nothing under `app/`,
`config/`, `db/` (other than the one additive migration) or `Gemfile` changed.

### The SDK is vendored, temporarily

`@fluid-app/droplet-sdk` is **not published yet**, so the SDK source is vendored
at `vendor/droplet-sdk` and depended on as
`"@fluid-app/droplet-sdk": "link:./vendor/droplet-sdk"`. `pnpm install`,
`pnpm build` and `pnpm test` therefore work on a clean clone with no registry
authentication.

Import specifiers are already the published name, so switching to the registry
copy is one line in `package.json` and nothing else. The directory is a
**verbatim copy** — refresh it by replacing it wholesale from the droplet
template, never by editing it in place, or the fleet's copies diverge.

## Production environment

### Google cloud infrastructure

- Google Cloud Run (Web)
- Google Cloud Storage (Terraform)
- Google Cloud SQL (postgreSQL)
- Google Cloud Build (CI/CD)
- Google Cloud Compute Engine (jobs console)
- Artifact Registry (Docker)

web: Google Cloud Run name `fluid-droplet-droplet-shipping-options`  

migrations: Google Cloud Run `fluid-droplet-shipping-options`  

jobs console: Google Cloud Compute Engine name `fluid-droplet-droplet-shipping-options-jobs-console`  

### Deploy to google cloud

Run github action to deploy to google cloud `deploy production`
or run the following command to deploy to google cloud  

`gcloud beta builds submit --config cloudbuild-production.yml --region=europe-west1 --substitutions=COMMIT_SHA=$(git rev-parse --short HEAD),_TIMESTAMP=$(date +%Y%m%d%H%M%S) --project=fluid-417204 .`

### Add environment variables to google cloud

Add environment variables to google cloud `add-update-env-gcloud.sh` and run the following command to add environment variables to google cloud
`sh add-update-env-gcloud.sh`

### Access console rails from google cloud

Access VM with SSH from google console  
jobs console: Google Cloud Compute Engine name `fluid-droplet-shipping-options-jobs-console`  

Rails console: Run `docker exec -it $(docker ps -q | head -n 1) bin/rails c`  
Bash: `docker exec -it $(docker ps -q | head -n 1) bash`  
Logs: `docker logs $(docker ps -q | head -n 1)`  

### Sentry Configuration

This project includes Sentry integration for error monitoring and performance tracking. To enable Sentry:

1. **Create a Sentry project:**
   - Go to [Sentry.io](https://sentry.io) and create a new project
   - Select "Ruby" as the platform
   - Copy the DSN from your project settings

2. **Set the environment variable:**
   - Add `SENTRY_DSN` to your environment variables with the DSN from your Sentry project
   - For local development, add it to your `.env` file:
     ```bash
     SENTRY_DSN=https://your-dsn@sentry.io/project-id
     ```
   - For production, add it to your Google Cloud environment variables

3. **Sentry features enabled:**
   - Automatic error tracking and reporting
   - Performance monitoring
   - Request headers and IP data collection (for debugging)
   - Active Support and HTTP logger breadcrumbs

The Sentry integration will only be active when the `SENTRY_DSN` environment variable is present and configured.

### Technology Stack

![PostgreSQL 17](https://img.shields.io/badge/PostgreSQL-17-336791?logo=postgresql&logoColor=white)
![Ruby](https://img.shields.io/badge/Ruby-3.4.2-CC342D?logo=ruby&logoColor=white)
![Rails](https://img.shields.io/badge/Rails-8.0.2-CC0000?logo=ruby-on-rails&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-23.8.0-339933?logo=node.js&logoColor=white)
![pnpm](https://img.shields.io/badge/pnpm-10.17.1-F69220?logo=pnpm&logoColor=white)
![Next.js](https://img.shields.io/badge/Next.js-15.5.7-000000?logo=next.js&logoColor=white)
![Font Awesome](https://img.shields.io/badge/Font_Awesome-6.7.2-528DD7?logo=fontawesome&logoColor=white)
![Tailwind CSS 4.0](https://img.shields.io/badge/Tailwind_CSS-4.0-38B2AC?logo=tailwindcss&logoColor=white)
<br>

## Local environment

### Running locally

Install dependencies with `bundle install` and `pnpm install`
and install foreman with `gem install foreman`  
Just the rails server (port 3000)<br>
`foreman start -f Procfile.dev`

Running everything (port 3200)<br>
`bin/dev`

### Running locally with docker

Configure your environment variables in `.env` file
and run the following command:  
`make install`
Running it as a docker service (port 3600)<br>
`make up`

Run `make help` to see all commands

### License

MIT License

Copyright (c) 2025 Fluid Commerce

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
