/**
 * Asks Fluid to reprice a cart.
 *
 * Port of `Callbacks::CartCallbacksController#request_shipping_recalculate`.
 * Called after a login is recorded, because the shopper's shipping was already
 * calculated — without subscription state — before they authenticated. The
 * recalculation calls `update_cart_shipping` straight back at this droplet,
 * which now reads the freshly stored session and can zero the cheapest option.
 *
 * Failures are logged and swallowed, as in Rails. The login itself has already
 * been persisted; refusing the callback over a failed reprice would make Fluid
 * retry the whole thing, and the shopper's next cart change reprices anyway.
 */

import { fluidApiSettings } from "@/lib/settings";

const REQUEST_TIMEOUT_MS = 5_000;

export async function requestCartRecalculate(
  cartToken: string,
  authenticationToken: string,
): Promise<void> {
  try {
    const { base_url: baseUrl } = await fluidApiSettings();

    await fetch(
      `${baseUrl.replace(/\/$/, "")}/api/carts/${encodeURIComponent(cartToken)}/recalculate`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${authenticationToken}`,
          "Content-Type": "application/json",
        },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      },
    );
  } catch (error) {
    console.error(
      "[CartCallback] Failed to recalculate:",
      error instanceof Error ? error.message : error,
    );
  }
}
