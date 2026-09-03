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

/**
 * Ruby's `Float#round(2)`, not JavaScript's.
 *
 * `Math.round(x * 100) / 100` is NOT the same function. Ruby's `flo_round`
 * applies a correction after scaling — `round_half_up` in numeric.c — that
 * recovers the half-way case the binary representation lost, and JavaScript has
 * no equivalent:
 *
 *     1.005.round(2)  # => 1.01     Math.round(1.005 * 100) / 100  === 1
 *     0.145.round(2)  # => 0.15     Math.round(0.145 * 100) / 100  === 0.14
 *     1.015.round(2)  # => 1.02     Math.round(1.015 * 100) / 100  === 1.01
 *
 * That is not cosmetic here. The rounded weight is compared against contiguous
 * rate bands, so a cart landing on one of these values is priced from the band
 * below in one app and the band above in the other — the two apps quoting
 * different shipping for the same cart, which is the one thing a per-company
 * cutover must not produce.
 *
 * This is a direct port of numeric.c's `round_half_up`, cross-checked against
 * real Ruby output in weight.test.ts.
 */
function roundHalfUpAsRuby(x: number, scale: number): number {
  const scaled = x * scale;
  // C's `round()` goes half AWAY FROM ZERO; JS's `Math.round` goes half toward
  // +Infinity, so they disagree on every negative half.
  let f = scaled < 0 ? -Math.round(-scaled) : Math.round(scaled);

  if (x > 0) {
    if ((f + 0.5) / scale <= x) f += 1;
  } else if (x < 0) {
    if ((f - 0.5) / scale >= x) f -= 1;
  }

  return f / scale;
}

/** Total cart weight in pounds, rounded to 2dp exactly as Rails rounded it. */
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

  return roundHalfUpAsRuby(total, 100);
}
