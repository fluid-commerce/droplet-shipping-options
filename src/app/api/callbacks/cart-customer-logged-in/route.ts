/**
 * `cart_customer_logged_in`.
 *
 * Port of `Callbacks::CartCallbacksController#logged_in`. Rails served it at
 * `POST /callbacks/cart_customer_logged_in`; the local route name and the Fluid
 * definition name happen to be identical here, unlike `update_cart_shipping`.
 *
 * This is where the expensive question gets asked. Checking a subscription
 * costs two Fluid API calls, and `update_cart_shipping` runs on the blocking
 * checkout path — so the answer is computed once, here, and stored on the cart
 * session for the calculation callback to read.
 *
 * Then it asks Fluid to reprice the cart, because shipping was already
 * calculated for this cart before the shopper authenticated.
 *
 * The definition is `checkout_blocking`, so every path answers 200 with the
 * definition's `{success: true}` shape.
 */

import { withFluidCallback } from "@fluid-app/droplet-sdk/next";
import { NextResponse } from "next/server";

import { callbackStore, resolvePrincipal } from "@/lib/callbacks";
import {
  freeShippingEnabled,
  hasActiveSubscription,
  loggedInCallbackSchema,
  requestCartRecalculate,
  storeCartLogin,
  toCartId,
} from "@/lib/shipping";

/** The one neutral body this route returns when it does no work. */
const ok = () => NextResponse.json({ success: true });

export const POST = withFluidCallback(
  {
    definitions: ["cart_customer_logged_in"],
    store: callbackStore,
    resolvePrincipal,
    name: "cart-customer-logged-in",
    onAuthFailure: ok,
    onInvalidBody: ok,
    onHandlerError: ok,
  },
  async ({ payload, principal: company }) => {
    const parsed = loggedInCallbackSchema.safeParse(payload);
    if (!parsed.success) {
      console.warn(
        `[cart-customer-logged-in] Unusable payload for company ${company.id}`,
      );
      return ok();
    }

    const cart = parsed.data.cart;
    const cartId = toCartId(cart?.id);
    const email = cart?.email?.toString().trim() || null;

    // Rails answered 400 "Cart ID is required" here. There is nothing to key a
    // session on, so it is the neutral acknowledgement instead — a 400 on a
    // checkout_blocking callback breaks the cart.
    if (cartId === null) {
      console.warn(
        `[cart-customer-logged-in] No cart id for company ${company.id}`,
      );
      return ok();
    }

    if (!freeShippingEnabled(company.settings) || !email) {
      return NextResponse.json({
        success: true,
        message: "Subscription check skipped",
      });
    }

    const subscribed = await hasActiveSubscription(email, company);
    await storeCartLogin(cartId, email, subscribed);

    const cartToken = cart?.cart_token?.toString() || null;
    if (cartToken) {
      await requestCartRecalculate(cartToken, company.authenticationToken);
    }

    return NextResponse.json({ success: true, has_subscription: subscribed });
  },
);
