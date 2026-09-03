/**
 * `update_cart_email`.
 *
 * Port of `Callbacks::CartCallbacksController#update_email`. Rails served it at
 * `POST /callbacks/update_cart_email`; local route name and definition name
 * match here.
 *
 * The job is to INVALIDATE, not to compute. When the cart's email is cleared or
 * changed away from the one that logged in, the stored subscription state no
 * longer describes whoever is now checking out, and leaving it would give a
 * stranger the previous shopper's free shipping. `update_cart_shipping` also
 * re-checks the email itself, so this is the second of two independent guards.
 *
 * The definition requires `{success, valid}` and this droplet never rejects an
 * email — it only observes the change — so `valid` is always true. Answering
 * `valid: false` would block the shopper from setting their own address.
 */

import { withFluidCallback } from "@fluid-app/droplet-sdk/next";
import { NextResponse } from "next/server";

import { callbackStore, resolvePrincipal } from "@/lib/callbacks";
import { emailChangeCallbackSchema, handleEmailChange } from "@/lib/shipping";

/** Required shape from update_cart_email.yml: `success` and `valid`. */
const accept = () => NextResponse.json({ success: true, valid: true });

export const POST = withFluidCallback(
  {
    definitions: ["update_cart_email"],
    store: callbackStore,
    resolvePrincipal,
    name: "update-cart-email",
    onAuthFailure: accept,
    onInvalidBody: accept,
    onHandlerError: accept,
  },
  async ({ payload, principal: company }) => {
    const parsed = emailChangeCallbackSchema.safeParse(payload);
    if (!parsed.success) {
      console.warn(
        `[update-cart-email] Unusable payload for company ${company.id}`,
      );
      return accept();
    }

    await handleEmailChange(parsed.data, "update-cart-email");
    return accept();
  },
);
