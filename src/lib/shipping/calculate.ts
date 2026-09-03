/**
 * The shipping calculation itself.
 *
 * Port of `ShippingCalculationService`. Given a company, a destination and a
 * cart, it answers the `shipping_options` array Fluid puts in front of the
 * shopper.
 *
 * ## What is deliberately NOT ported
 *
 * Rails wrapped the option lookup in `Rails.cache.fetch(..., 10.minutes)`.
 * There is no cache here. The Rails cache was a per-process Solid Cache store
 * invalidated by `ShippingOption#invalidate_cache!` from the same process, so
 * on Cloud Run it was already only as good as one instance's memory — and a
 * stale entry prices a live cart wrongly for up to ten minutes. The query it
 * replaced is a single indexed read scoped to one company. Correctness over a
 * saved millisecond on the checkout path.
 */

import { prisma } from "@/lib/db";

import { readCartSession } from "./cart-session";
import { totalWeightLbs } from "./weight";
import type {
  CartItem,
  ShippingCalculationResult,
  ShippingOptionResult,
} from "./types";

/** Sorts last: Rails' `COALESCE(..., 2147483647)` for an unpositioned option. */
const UNPOSITIONED = 2_147_483_647;

type RateRow = {
  country: string;
  region: string | null;
  minRangeLbs: { toNumber(): number };
  maxRangeLbs: { toNumber(): number };
  flatRate: { toNumber(): number };
  minCharge: { toNumber(): number };
};

type OptionRow = {
  id: bigint;
  name: string | null;
  deliveryTime: number | null;
  countries: unknown;
  countrySortPositions: unknown;
  rates: RateRow[];
};

export interface CalculationCompany {
  id: bigint;
  settings: unknown;
}

export interface CalculationInput {
  company: CalculationCompany;
  /** Already upper-cased by the caller, as Rails upper-cased it. */
  shipToCountry: string | null;
  shipToState: string | null;
  items: CartItem[] | null | undefined;
  cartId: number | null;
  cartEmail: string | null;
}

/**
 * Whether this company has the subscriber free-shipping feature switched on.
 *
 * Port of `Company#free_shipping_enabled?`, including its string comparison:
 * the admin form writes a boolean but older rows hold the string "true", and
 * both must count.
 */
export function freeShippingEnabled(settings: unknown): boolean {
  if (typeof settings !== "object" || settings === null) return false;
  const value = (settings as Record<string, unknown>).free_shipping_for_subscribers;
  return value === true || value === "true";
}

function countriesOf(option: OptionRow): string[] {
  return Array.isArray(option.countries)
    ? option.countries.filter((c): c is string => typeof c === "string")
    : [];
}

function positionFor(option: OptionRow, country: string): number {
  const positions = option.countrySortPositions;
  if (typeof positions !== "object" || positions === null) return UNPOSITIONED;

  const raw = (positions as Record<string, unknown>)[country];
  const parsed = Number.parseInt(String(raw), 10);
  return Number.isFinite(parsed) ? parsed : UNPOSITIONED;
}

/**
 * Rails' `format_delivery_time`.
 *
 * `delivery_time` is nullable in the database even though the model validates
 * presence, and Ruby's `"#{nil} days"` produced `" days"`. Reproduced rather
 * than tidied: an option row with a NULL delivery time renders the same string
 * it renders in production today.
 */
function formatDeliveryTime(deliveryTime: number | null): string {
  if (deliveryTime === 0) return "Available same day";
  if (deliveryTime === 1) return "1 day";
  return `${deliveryTime ?? ""} days`;
}

/**
 * The best rate for one option: a region-specific band first, then a
 * country-level one. Both must also contain the cart's weight.
 */
function findBestRate(
  option: OptionRow,
  country: string,
  state: string,
  weightLbs: number,
): RateRow | null {
  const inBand = (rate: RateRow) =>
    weightLbs >= rate.minRangeLbs.toNumber() &&
    weightLbs <= rate.maxRangeLbs.toNumber();

  const regional = option.rates.find(
    (rate) =>
      rate.country === country &&
      !!rate.region &&
      rate.region === state &&
      inBand(rate),
  );
  if (regional) return regional;

  return (
    option.rates.find(
      (rate) => rate.country === country && !rate.region && inBand(rate),
    ) ?? null
  );
}

function serialize(
  option: OptionRow,
  country: string,
  state: string,
  weightLbs: number,
): ShippingOptionResult | null {
  const rate = findBestRate(option, country, state, weightLbs);
  if (!rate) return null;

  return {
    shipping_total: Math.max(rate.flatRate.toNumber(), rate.minCharge.toNumber()),
    shipping_title: option.name,
    shipping_delivery_time_estimate: formatDeliveryTime(option.deliveryTime),
  };
}

/**
 * The single option offered when a company has no active option for this
 * country at all. Not an error: it tells the shopper to arrange shipping with
 * the shop, at no charge, rather than blocking checkout.
 */
function coordinateWithShop(): ShippingOptionResult {
  return {
    shipping_total: 0,
    shipping_title: "Coordinate with the shop",
    shipping_delivery_time_estimate: 0,
  };
}

/**
 * Whether the logged-in shopper on THIS cart holds a subscription.
 *
 * Read-only: the answer was computed and stored by `cart_customer_logged_in`.
 * The stored email is re-checked against the cart's current email, so a cart
 * whose address changed after login does not keep the previous customer's
 * benefit.
 */
async function cartHoldsSubscription(
  input: CalculationInput,
): Promise<boolean> {
  if (input.cartId === null) return false;
  if (!freeShippingEnabled(input.company.settings)) return false;

  const session = await readCartSession(input.cartId);
  if (!session?.email) return false;

  if (
    input.cartEmail &&
    input.cartEmail.toLowerCase() !== session.email.toLowerCase()
  ) {
    return false;
  }

  return session.hasActiveSubscription;
}

export async function calculateShipping(
  input: CalculationInput,
): Promise<ShippingCalculationResult> {
  const { company, shipToCountry, shipToState } = input;

  // Rails' ActiveModel validations: country and state are both required, and a
  // missing one is a 422 rather than an empty answer.
  if (!shipToCountry || !shipToState) {
    return { success: false, error: "Invalid parameters", shipping_options: [] };
  }

  const options = (await prisma.shippingOption.findMany({
    where: { companyId: company.id, status: "active" },
    // Only this country's rates. Rails loaded every rate of every matching
    // option; `find_best_rate` then discarded all the other countries' rows.
    include: { rates: { where: { country: shipToCountry } } },
    orderBy: { id: "asc" },
  })) as OptionRow[];

  // `countries` is a jsonb array, filtered here rather than with a `@>` query:
  // the set is one company's active options, and doing it in SQL would need a
  // raw fragment carrying an operator-supplied country code.
  const forCountry = options
    .filter((option) => countriesOf(option).includes(shipToCountry))
    .sort(
      (a, b) =>
        positionFor(a, shipToCountry) - positionFor(b, shipToCountry) ||
        Number(a.id - b.id),
    );

  // No option serves this country: offer the fallback. Note this checks the
  // OPTION list, not the priced list — an option that exists but has no rate
  // band for this cart's weight yields an empty array further down, which
  // leaves the cart's existing shipping alone.
  if (forCountry.length === 0) {
    return { success: true, shipping_options: [coordinateWithShop()] };
  }

  const weightLbs = totalWeightLbs(input.items);

  const seen = new Set<bigint>();
  const shippingOptions: ShippingOptionResult[] = [];
  for (const option of forCountry) {
    if (seen.has(option.id)) continue;
    seen.add(option.id);

    const serialized = serialize(option, shipToCountry, shipToState, weightLbs);
    if (serialized) shippingOptions.push(serialized);
  }

  if (shippingOptions.length > 0 && (await cartHoldsSubscription(input))) {
    // The cheapest option becomes free — the whole list is not zeroed, and the
    // shopper keeps the choice.
    const cheapest = shippingOptions.reduce((a, b) =>
      b.shipping_total < a.shipping_total ? b : a,
    );
    cheapest.shipping_total = 0;
  }

  return { success: true, shipping_options: shippingOptions };
}
