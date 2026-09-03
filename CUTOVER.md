# Cutting the shipping-options droplet over from Rails to Next

Both apps read the same database — the Next app maps onto the Rails tables with
`@@map`, and there is no data migration. What decides which app serves a company
is not a hostname or a load balancer: **Fluid calls whatever url is recorded in
that installation's callback and webhook registrations.** The registration table
is the routing table, and it is keyed per company.

That is what makes this safe to do one tenant at a time.

The two services:

| | Cloud Run service | Webhook path |
|---|---|---|
| Rails | `fluid-droplet-shipping-options` | `POST /webhook` |
| Next | `fluid-droplet-shipping-options-next` | `POST /api/webhooks` |

Both live in `europe-west1`, project `fluid-417204`. The Rails service answers
at `https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app`
(the default in `DropletInstalledJob` and `DropletInstallationService`).

## The four callbacks, and the name each is really registered under

This droplet has **four** callbacks. The Rails route name is a LOCAL name and
one of the four does not match its Fluid definition at all.

| Fluid definition name | Rails path | Next path |
|---|---|---|
| `update_cart_shipping` | `POST /callbacks/shipping_options` | `POST /api/callbacks/update-cart-shipping` |
| `cart_customer_logged_in` | `POST /callbacks/cart_customer_logged_in` | `POST /api/callbacks/cart-customer-logged-in` |
| `update_cart_email` | `POST /callbacks/update_cart_email` | `POST /api/callbacks/update-cart-email` |
| `verify_email_success` | `POST /callbacks/verify_email_success` | `POST /api/callbacks/verify-email-success` |

How that was established, definition by definition:

- **`update_cart_shipping`.** `shipping_options` is the Rails *resource* — it
  names this droplet's own `shipping_options` table — and is not a Fluid
  definition name; there is no `shipping_options.yml` in fluid's
  `app/lib/callback_definitions/`. The real name is in the Rails code:
  `DropletInstalledJob#register_active_callbacks` and
  `DropletInstallationService#register_shipping_callback` both POST
  `definition_name: "update_cart_shipping"` with the url
  `#{droplet_url}/callbacks/shipping_options`. Confirmed against
  `app/lib/callback_definitions/update_cart_shipping.yml`.
- **The other three** are registered by an operator from the admin **Callbacks**
  screen, whose rows are synced from `GET /api/callback/definitions` by
  `CallbackSyncService` — so `callbacks.name` *is* a definition name by
  construction. Each is present in fluid as `cart_customer_logged_in.yml`,
  `update_cart_email.yml` and `verify_email_success.yml`.

The full valid set of definition names is exactly the filenames in
`fluid-main/app/lib/callback_definitions/`. A wrong name means fluid silently
stops calling: a missing shipping result is rescued into an empty option list,
so the symptom is a checkout offering no shipping rather than an error anyone
sees.

`scripts/cutover.ts` holds this table as `CALLBACK_PATHS` and refuses to guess a
path for a definition it does not know.

## Why not a percentage split

Two reasons, both concrete.

A split sends one recalculation of a cart to Rails and the next to Next. Both
read the same `cart_sessions` row but the subscriber discount is applied to
"the cheapest option" as each app computes it, so a shopper can be shown one set
of prices and charged against another.

And webhooks are at-least-once with per-app idempotency. Two apps behind one url
both act on the same event: two installs, two callback registrations, two
cleanup passes. Nothing deduplicates across the app boundary because neither app
knows the other exists.

Per-company cutover has a blast radius of one tenant, an instant rollback, and
no double-processing.

## The sequence

**0. Deploy.** Run the `deploy next` workflow. It builds `Dockerfile.next` and
deploys the `fluid-droplet-shipping-options-next` Cloud Run service. Nothing
points at it, so this changes nothing — that is the property worth having.

The service is created **once, by hand**, before the first run:
`cloudbuild-next.yml` does `run services update`, not `deploy`, so it cannot
invent configuration. It needs the same `DATABASE_URL` as the Rails service,
plus its own `FLUID_DROPLET_URL`, `AUTH_SECRET` and `FLUID_WEBHOOK_AUTH_TOKEN`.
See `.env.example`. There is no carrier or 3PL credential: rates come from this
droplet's own `shipping_options` / `rates` tables.

Before the first deploy, the Rails migration
`db/migrate/20260317000000_create_fluid_callback_registrations.rb` must have run
against production. It creates the table the Next app's callback verification
reads. Without it the store raises, the SDK reads a raising store as an auth
failure, and every callback is refused behind a neutral 200 — no error rate
moves and nothing alerts. `src/instrumentation.ts` reports the state of that
table on every boot; read the startup log.

**1. Smoke.** `scripts/smoke-next.sh <url>`. Read its header first: the four
callback routes fail open by design, so an unauthenticated probe cannot tell
verification working from verification broken. The webhook assertions are the
ones with teeth. Run it with `FLUID_WEBHOOK_AUTH_TOKEN` set — without it, only
the refusal half is checked.

**2. One internal installation.** Repoint it, watch it, put it back if needed.

```bash
pnpm cutover status  acme                                     # read-only
pnpm cutover repoint acme \
  --url  https://fluid-droplet-shipping-options-next-...run.app \
  --from https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app
APPLY=1 pnpm cutover repoint acme \
  --url  https://fluid-droplet-shipping-options-next-...run.app \
  --from https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app
pnpm cutover status  acme                                     # confirm
```

`--to` defaults to `next`, so the forward cutover needs no path flags at all —
the per-definition paths come from `CALLBACK_PATHS`. **Going back needs
`--to rails`**; see the rollback below.

The repoint is an **update in place**, not a delete-then-create, and that is
load-bearing. Fluid sets `verification_token` in `before_create` and never
rotates it, `UpdateAction` accepts `url`, and `api_show` renders the `:shared`
view which still carries the token. So the registration keeps its uuid and its
token while only the url moves, and the tool reads the token back afterwards to
store its digest.

That removes both ways the obvious shape goes wrong. There is no window where a
definition has no registration and fluid quietly stops calling — which for
`update_cart_shipping` means a checkout with no shipping at all. And there is no
create response whose loss would strand a live registration whose token was
issued exactly once, to nobody.

`--from` is only a hint. It lets the tool recognise a registration as ours
before we hold any digest for it, which is the state every company is in on its
first cutover. Where more than one registration could plausibly be ours, the
tool stops and prints them rather than guessing: the listing is company-scoped,
so another droplet installed for the same company can hold a registration with
the same `definition_name`, and repointing theirs at us is an outage for them.

All four definitions are planned before any of them is moved, and the run stops
on the first failure. A company answering `update_cart_shipping` from Next while
`cart_customer_logged_in` still writes its session on Rails is not a state to
discover halfway.

`cutover repoint` also moves the per-company webhooks a droplet registers from
`droplet.config.ts`, and refuses to touch anything if it cannot first list them.
**This droplet enables none** — both entries are `enabled: false`, matching the
Rails app, which registers only the two droplet-level lifecycle webhooks — so
the command prints a `NOTE` saying so and moves only the callbacks. Do not read
the absence of webhook lines as "the webhooks moved"; the droplet-level ones are
step 4.

**If a repoint fails halfway**, read which of two things happened — they need
opposite responses, and `reconcile` only fixes one of them.

*A url moved but its token did not get stored.* The failure message names the
definition and says the callback is live and being refused behind a 200. Only
the digest is missing, so:

```bash
APPLY=1 pnpm cutover reconcile acme \
  --url https://fluid-droplet-shipping-options-next-...run.app
```

*A later update failed outright.* Then some registrations are at one url and the
rest are still at the other. `reconcile` will NOT fix this and will report
"Nothing to fix", because every registration it can see is either already valid
or not at the target url. Either finish the move by re-running the repoint, or
put everything back with the rollback below. The failure message prints the
exact rollback command, along with everything it had already moved.

**3. Real companies, smallest first.** Same procedure. Stop at the first
surprise. The one to watch is a company with
`settings.free_shipping_for_subscribers` on — it is the only one whose
`cart_sessions` rows are read, and the only one where a wrong answer is visible
as a price.

**4. Move the droplet-level webhook and the callback configuration.**
`cutover repoint` moves one company's registrations. It does NOT move:

- the droplet-level lifecycle registrations, `droplet.installed` and
  `droplet.uninstalled`, which live on the droplet record itself rather than on
  any installation and still point at Rails; or
- the four `callbacks` table rows that a NEW installation registers from.

Nothing surfaces either by itself. Every company can be fully cut over and
working while the next install still goes to Rails and registers its callbacks
back onto Rails. Delete Rails first and those events are simply lost.

So, once every company has been repointed:

1. In Fluid's droplet settings, set `fluid_webhook.url` to
   `https://fluid-droplet-shipping-options-next-...run.app/api/webhooks` and
   press **Update Droplet**. Confirm an install arrives.
2. On the admin **Callbacks** screen, change all four rows to the Next paths in
   the table at the top of this document. `pnpm cutover status <shop>` prints
   every active row and flags each one still on a Rails path as `ON RAILS`.

Both are global, not per-tenant, and there is no partial version of either.

There is one difference worth knowing here. The Rails install path **hardcoded**
`update_cart_shipping`: `DropletInstalledJob` registered it whether or not a
`callbacks` row existed, and then registered every active row on top. The Next
install path registers **only** what is in the `callbacks` table. So a new
installation under Next gets exactly the rows an operator has marked active —
which is the point, but it means step 4.2 is not cosmetic. If the
`update_cart_shipping` row is missing or inactive when the first post-cutover
install arrives, that company gets no shipping callback at all.

**5. Retire Rails.** Min-instances to 0 first and leave it a while — that is
reversible in seconds. Delete only once nothing has needed it.

## Rules while both apps are live

**Rails owns the schema.** Two migration tools against one database produces a
schema neither app agrees with. `cloudbuild-next.yml` has no migrations step and
must not gain one; the `fluid-droplet-shipping-options-migrations` Cloud Run job
stays the Rails pipeline's. Freeze Rails migrations during a cutover window, and
keep Prisma read-shaped: `db pull`, never `db push`. There is no `db:push` guard
in this repo — `pnpm db:push` will happily reshape the Rails schema, so treat
that command as unavailable during a cutover window rather than as guarded.

**Watch for encrypted columns.** Where Rails uses `encrypts`, Prisma reads the
raw column and gets the base64 envelope. The droplet then reads every company as
*unconfigured* — no error, no exception, just a droplet that believes nobody has
set it up. **This droplet encrypts nothing today.** It did until
`20260316000000_clean_exigo_settings_from_companies`: `Company#exigo_db_password`
used a `MessageEncryptor` derived from `secret_key_base`, and the Exigo
subscription lookup it fed has been replaced by `MetafieldSubscriptionService`,
which calls Fluid with the company's own `authentication_token`. If an Exigo-style
credential is ever added back, it must not go in a Rails-encrypted column while
both apps are live.

**Cache invalidation is not shared.** Rails caches a company's shipping options
for ten minutes (`ShippingOption#invalidate_cache!` clears it on write). The Next
app has no such cache and queries every time. So during a cutover window an
option edited in the Rails admin takes effect immediately on Next and up to ten
minutes later on Rails. Prices can legitimately differ between the two apps for
that window; it is not evidence that the port is wrong.

**A rollback is `--to rails` with the urls swapped.**

```bash
APPLY=1 pnpm cutover repoint acme \
  --url  https://fluid-droplet-shipping-options-106074092699.europe-west1.run.app \
  --from https://fluid-droplet-shipping-options-next-...run.app \
  --to   rails
```

`--to rails` selects the Rails path for every definition — including
`/callbacks/shipping_options` for `update_cart_shipping`, which is the one that
cannot be derived from its definition name — and defaults the webhook path to
`/webhook`. Without it the rollback would register `update_cart_shipping` at
`https://<rails>/api/callbacks/update-cart-shipping`, a route Rails does not
have; because fluid rescues a failed shipping callback into an empty list, the
symptom would be a checkout with no shipping options rather than an error.

Because the repoint is an update, the rollback is symmetric and has the same
no-gap property. Keep the Rails service warm until you stop needing it.

## What changed in behaviour, deliberately

Everything else is a faithful port. These are the exceptions, each of which is
also commented at its call site.

- **Tenancy no longer comes from the payload.** The Rails callbacks looked the
  company up from `cart.company.id` in the request body and answered 401 when
  they could not find it. The Next routes resolve the tenant from the verified
  registration's `dri` and ignore any company named in the body. A signature
  proves only *which registration* signed, not who the request is about.
- **`verify_email_success` answers `{"success": true}`**, not Rails'
  `{"success": true, "valid": true}`. That definition's `{success, message}`
  branch sets `additionalProperties: false`, so the `valid` key made Rails'
  response invalid against all three branches. The definition is
  `checkout_async` — fluid does not read the response — so this cannot change
  any behaviour, and it stops the droplet publishing a body it is not allowed
  to publish.
- **A null `cart` on `verify_email_success` is a no-op, not a 500.** The
  definition types `cart` as `object | null`. Rails read `payload[:cart][:id]`
  unguarded and raised `NoMethodError`.
- **Failure statuses are 200, not 400/401/422.** Every one of the four routes is
  on a blocking or async checkout path where a non-2xx is a broken cart rather
  than a protected one. The `[fluid-callback:<name>] rejected` log line is the
  signal to alert on.
