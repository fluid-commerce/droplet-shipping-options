/**
 * `update_cart_shipping` — the callback this droplet exists for.
 *
 * Port of `Callbacks::ShippingOptionsController#create`.
 *
 * ## The definition name is not the Rails route name
 *
 * Rails served this at `POST /callbacks/shipping_options`. `shipping_options`
 * is a LOCAL name — it is the Rails resource, and it names this droplet's
 * `shipping_options` table. The Fluid definition is `update_cart_shipping`,
 * from app/lib/callback_definitions/update_cart_shipping.yml. That is not
 * inferred: `DropletInstalledJob#register_active_callbacks` registers
 * `definition_name: "update_cart_shipping"` against the URL
 * `#{droplet_url}/callbacks/shipping_options`.
 *
 * ## Everything answers 200
 *
 * Fluid calls this synchronously while a shopper is in checkout and blocks the
 * storefront request on the answer, so a 401 is a broken cart rather than a
 * protected one. Auth failures, malformed bodies and handler errors therefore
 * all return the same neutral body the route's own no-op path returns.
 *
 * That body is `{success: true, shipping_options: []}`, and the empty array is
 * the whole reason fail-open is safe HERE: `Commerce::ShippingOptionAssigner
 * #apply` does `return @cart if shipping_options.empty?`, leaving the cart's
 * existing shipping untouched. It is not "free shipping". `update_cart_tax` is
 * the counter-example — a 200 carrying a zero there is applied as real zero tax
 * — so this policy does not generalise.
 *
 * The status code tells an operator nothing. The
 * `[fluid-callback:update-cart-shipping] rejected` log line is the only signal,
 * and is what an alert should be built on.
 *
 * ## Rails returned 401 when it could not find the company; this does not
 *
 * The Rails controller looked the company up from `cart.company.id` in the
 * BODY. Here the tenant comes from the verified registration
 * (`resolvePrincipal`, src/lib/callbacks/store.ts) and a body naming another
 * company is ignored, so there is no such failure to answer.
 */

import { withFluidCallback } from "@fluid-app/droplet-sdk/next";
import { NextResponse } from "next/server";

import { callbackStore, resolvePrincipal } from "@/lib/callbacks";
import {
  NEUTRAL_RESULT,
  calculateShipping,
  freeShippingEnabled,
  readCartSession,
  shippingCallbackSchema,
  toCartId,
} from "@/lib/shipping";

const neutral = () => NextResponse.json(NEUTRAL_RESULT);

export const POST = withFluidCallback(
  {
    definitions: ["update_cart_shipping"],
    store: callbackStore,
    resolvePrincipal,
    name: "update-cart-shipping",
    onAuthFailure: neutral,
    onInvalidBody: neutral,
    onHandlerError: neutral,
  },
  async ({ payload, principal: company }) => {
    const parsed = shippingCallbackSchema.safeParse(payload);
    if (!parsed.success) {
      // Never the body: it carries the shopper's address.
      console.warn(
        `[update-cart-shipping] Unusable payload for company ${company.id}`,
      );
      return neutral();
    }

    const { cart } = parsed.data;
    const shipTo = cart.ship_to;

    // Rails answered 400 for each of these. Neutral instead, for the same
    // reason every other failure is neutral: a cart part-way through address
    // entry legitimately has no country yet, and refusing it breaks checkout.
    const country = shipTo?.country_code?.toString().trim().toUpperCase() || null;
    const state = shipTo?.state?.toString().trim().toUpperCase() || null;
    if (!country || !state) {
      return neutral();
    }

    const cartId = toCartId(cart.id);
    const cartEmail = cart.email?.toString().trim() || null;

    const result = await calculateShipping({
      company,
      shipToCountry: country,
      shipToState: state,
      items: cart.items ?? [],
      cartId,
      cartEmail,
    });

    if (!result.success) return neutral();

    // Echoed for the storefront, exactly as Rails echoed it, and only when the
    // feature is on and a login was recorded for this cart.
    if (cartId !== null && freeShippingEnabled(company.settings)) {
      const session = await readCartSession(cartId);
      if (session?.email) result.logged_in_email = session.email;
    }

    return NextResponse.json(result);
  },
);
