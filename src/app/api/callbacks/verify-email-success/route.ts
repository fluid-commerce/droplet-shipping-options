/**
 * `verify_email_success`.
 *
 * Port of `Callbacks::CartCallbacksController#email_verified`. Rails served it
 * at `POST /callbacks/verify_email_success`; local route name and definition
 * name match here. It does the same session invalidation as
 * `update_cart_email` — a verified address is another point at which the cart's
 * email may have moved away from the one that logged in.
 *
 * ## Two differences from Rails, both deliberate
 *
 * The definition is `checkout_async`: fluid dispatches it fire-and-forget and
 * never reads the response. Rails answered `{success: true, valid: true}`,
 * which satisfies none of the three branches of this definition's
 * `response_schema` — the `{success, ...}` branch sets
 * `additionalProperties: false`, so `valid` makes it invalid. Since nothing
 * reads the body, answering the schema-valid `{success: true}` cannot change
 * any behaviour, and stops the droplet publishing a response it is not allowed
 * to publish.
 *
 * And `cart` is typed `object | null` here. Rails read `payload[:cart][:id]`
 * with no guard and raised NoMethodError — a 500 — whenever fluid sent the null
 * it says it may send. A null cart simply means there is no session to clear.
 */

import { withFluidCallback } from "@fluid-app/droplet-sdk/next";
import { NextResponse } from "next/server";

import { callbackStore, resolvePrincipal } from "@/lib/callbacks";
import { emailChangeCallbackSchema, handleEmailChange } from "@/lib/shipping";

const ok = () => NextResponse.json({ success: true });

export const POST = withFluidCallback(
  {
    definitions: ["verify_email_success"],
    store: callbackStore,
    resolvePrincipal,
    name: "verify-email-success",
    onAuthFailure: ok,
    onInvalidBody: ok,
    onHandlerError: ok,
  },
  async ({ payload, principal: company }) => {
    const parsed = emailChangeCallbackSchema.safeParse(payload);
    if (!parsed.success) {
      console.warn(
        `[verify-email-success] Unusable payload for company ${company.id}`,
      );
      return ok();
    }

    await handleEmailChange(parsed.data, "verify-email-success");
    return ok();
  },
);
