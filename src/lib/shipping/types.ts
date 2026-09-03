/**
 * Shapes of the callback payloads this droplet reads, and of what it answers.
 *
 * Parsed with Zod rather than trusted, but deliberately LENIENT: Fluid's
 * `update_cart_shipping` request schema types `cart` as an open object, so the
 * blueprint can gain fields at any time and a strict parse would start refusing
 * live checkouts on a change nobody here made. Everything optional is optional
 * here too, and the handler decides what it cannot proceed without.
 */

import { z } from "zod";

/** A cart line item. Only weight and quantity are used. */
export const cartItemSchema = z.object({
  id: z.union([z.number(), z.string()]).optional(),
  name: z.string().optional(),
  quantity: z.union([z.number(), z.string()]).nullish(),
  price: z.union([z.number(), z.string()]).nullish(),
  variant: z
    .object({
      id: z.union([z.number(), z.string()]).optional(),
      weight: z.union([z.number(), z.string()]).nullish(),
      unit_of_weight: z.string().nullish(),
      unit_of_size: z.string().nullish(),
    })
    .nullish(),
});

export type CartItem = z.infer<typeof cartItemSchema>;

export const shipToSchema = z.object({
  country_code: z.string().nullish(),
  state: z.string().nullish(),
  city: z.string().nullish(),
  zip: z.string().nullish(),
  address1: z.string().nullish(),
  address2: z.string().nullish(),
});

/** `update_cart_shipping` — the calculation callback. */
export const shippingCallbackSchema = z.object({
  cart: z
    .object({
      id: z.union([z.number(), z.string()]).nullish(),
      email: z.string().nullish(),
      items: z.array(cartItemSchema).nullish(),
      ship_to: shipToSchema.nullish(),
    })
    .passthrough(),
});

/** `cart_customer_logged_in`. */
export const loggedInCallbackSchema = z.object({
  cart: z
    .object({
      id: z.union([z.number(), z.string()]).nullish(),
      email: z.string().nullish(),
      cart_token: z.string().nullish(),
    })
    .passthrough()
    .nullish(),
});

/**
 * `update_cart_email` and `verify_email_success`.
 *
 * `cart` is nullish because `verify_email_success` types it as
 * `object | null` — see verify_email_success.yml. The Rails handler read
 * `payload[:cart][:id]` unguarded and raised NoMethodError on exactly that
 * case; here a null cart simply means there is no session to clear.
 */
export const emailChangeCallbackSchema = z.object({
  email: z.string().nullish(),
  cart: z
    .object({
      id: z.union([z.number(), z.string()]).nullish(),
      email: z.string().nullish(),
    })
    .passthrough()
    .nullish(),
});

/**
 * One entry of the `shipping_options` array Fluid reads.
 *
 * Field names are fixed by
 * `Commerce::Calculation::ShippingStrategy::Droplet#build_shipping_option` in
 * fluid: it reads `shipping_title`, `shipping_total` and
 * `shipping_delivery_time_estimate` and nothing else. Renaming any of them
 * makes the option silently unusable rather than an error.
 */
export interface ShippingOptionResult {
  shipping_total: number;
  shipping_title: string | null;
  shipping_delivery_time_estimate: string | number;
}

export interface ShippingCalculationResult {
  success: boolean;
  shipping_options: ShippingOptionResult[];
  error?: string;
  /** Echoed back for the storefront when free-shipping-for-subscribers is on. */
  logged_in_email?: string;
}

/**
 * The body every failure path answers with.
 *
 * An EMPTY option list, not a zero-priced one. `Commerce::ShippingOptionAssigner
 * #apply` returns the cart untouched when the array is empty, so this leaves
 * whatever shipping the cart already had — it does not offer free shipping. A
 * single zero-priced entry would be applied as a real zero.
 */
export const NEUTRAL_RESULT: ShippingCalculationResult = {
  success: true,
  shipping_options: [],
};
