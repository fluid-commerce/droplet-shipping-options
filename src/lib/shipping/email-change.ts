/**
 * The invalidation both email callbacks share.
 *
 * Port of `Callbacks::CartCallbacksController#handle_email_change`, which
 * `update_cart_email` and `verify_email_success` both called.
 *
 * Two cases clear the stored login:
 *
 *  - the cart's email was removed while a login was recorded, and
 *  - the cart's email is now a DIFFERENT address from the one that logged in.
 *
 * The same address arriving again is left alone — re-clearing it would drop the
 * subscription answer and make the next `update_cart_shipping` price the cart
 * as if nobody had logged in.
 *
 * There is no tenant check on the cart id, because there is nothing to check
 * it against: `cart_sessions` has no company column. That is the Rails shape
 * too. The row holds an email and a boolean and is keyed by a cart id the
 * caller already proved it can act for, so the exposure is bounded to clearing
 * a session — the same thing the shopper does by editing their address.
 */

import { z } from "zod";

import { clearCartSession, readCartSession, toCartId } from "./cart-session";
import type { emailChangeCallbackSchema } from "./types";

export type EmailChangePayload = z.infer<typeof emailChangeCallbackSchema>;

export async function handleEmailChange(
  payload: EmailChangePayload,
  logLabel: string,
): Promise<void> {
  const cartId = toCartId(payload.cart?.id);
  if (cartId === null) return;

  // Rails preferred the top-level `email` and fell back to the one on the cart.
  // `update_cart_email` sends the new address at the top level; the cart object
  // in that payload still carries the OLD one.
  const newEmail =
    payload.email?.toString().trim() ||
    payload.cart?.email?.toString().trim() ||
    null;

  const session = await readCartSession(cartId);
  const cachedEmail = session?.email ?? null;
  if (!cachedEmail) return;

  if (!newEmail) {
    console.log(`[${logLabel}] Email cleared, dropping cart session`);
    await clearCartSession(cartId);
    return;
  }

  if (newEmail.toLowerCase() !== cachedEmail.toLowerCase()) {
    // Neither address is logged: both are shopper PII.
    console.log(`[${logLabel}] Email changed, dropping cart session`);
    await clearCartSession(cartId);
  }
}
