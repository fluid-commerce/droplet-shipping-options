/**
 * Cart weight, in pounds.
 *
 * Port of `ShippingCalculationService#compute_total_weight` and
 * `#convert_to_pounds`. The rate tables are keyed on pounds, so every item is
 * converted before it is summed.
 *
 * The skip rules are load-bearing and are Rails' rules exactly: an item with no
 * variant, no weight, or no quantity contributes NOTHING rather than raising or
 * counting as zero-weight-but-present. A cart of such items totals 0 lbs, which
 * matches the lowest weight band — that is the existing production behaviour
 * and changing it here would silently reprice live carts.
 */

import type { CartItem } from "./types";

/**
 * Converts `weight` in `unit` to pounds.
 *
 * An unrecognised or missing unit is treated as pounds, matching Rails' `else`
 * branch. That is a real decision, not a fallthrough: Fluid's variant weights
 * are pounds when the unit is absent.
 */
export function convertToPounds(weight: number, unit?: string | null): number {
  switch (unit?.toLowerCase()) {
    case "kg":
    case "kgs":
    case "kilogram":
    case "kilograms":
      return weight * 2.20462;
    case "g":
    case "gram":
    case "grams":
      return weight * 0.00220462;
    case "oz":
    case "ounce":
    case "ounces":
      return weight * 0.0625;
    default:
      return weight;
  }
}

/** Total cart weight in pounds, rounded to 2dp as Rails rounded it. */
export function totalWeightLbs(items: CartItem[] | null | undefined): number {
  if (!items || items.length === 0) return 0;

  let total = 0;

  for (const item of items) {
    const variant = item.variant;
    // No variant, no weight, or no quantity: skipped entirely. `weight` is
    // compared to null/undefined rather than falsy so that a genuine 0 lb
    // variant still counts (as 0), which is what Rails' `weight.nil?` did.
    if (!variant) continue;
    if (variant.weight === null || variant.weight === undefined) continue;
    if (item.quantity === null || item.quantity === undefined) continue;

    const weight = Number(variant.weight);
    const quantity = Number.parseInt(String(item.quantity), 10);
    if (!Number.isFinite(weight) || !Number.isFinite(quantity)) continue;

    total += convertToPounds(weight, variant.unit_of_weight) * quantity;
  }

  return Math.round(total * 100) / 100;
}
