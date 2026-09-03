/**
 * "Does this email hold an active subscription?", answered from Fluid metafields.
 *
 * Port of `MetafieldSubscriptionService`. Two calls against Fluid with the
 * COMPANY's own token: find the customer by email, then read the `yoli_plus`
 * metafields on that customer.
 *
 * Every failure answers `false`. That is deliberate and matches Rails: this
 * decides whether to GIVE something away (free shipping on the cheapest
 * option), so an unknown answer must not grant it. It is called only from
 * `cart_customer_logged_in`, never from the calculation callback.
 */

import { fluidApiSettings } from "@/lib/settings";

const REQUEST_TIMEOUT_MS = 5_000;
const METAFIELD_NAMESPACE = "yoli_plus";
/** A subscription older than this is treated as lapsed. */
const MAX_SUBSCRIPTION_AGE_MONTHS = 12;

export interface SubscriptionCompany {
  authenticationToken: string;
}

async function fluidGet(
  baseUrl: string,
  path: string,
  query: Record<string, string>,
  token: string,
): Promise<{ status: number; body: unknown }> {
  const url = new URL(`${baseUrl.replace(/\/$/, "")}${path}`);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "x-fluid-client": "fluid-middleware",
    },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  const text = await response.text();
  let body: unknown = undefined;
  try {
    body = text ? JSON.parse(text) : undefined;
  } catch {
    body = undefined;
  }

  return { status: response.status, body };
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : null;
}

/**
 * Resolves the Fluid customer id for `email`, or null.
 *
 * The search endpoint is fuzzy, so the exact address is re-checked here — Rails
 * did the same. Without it, "jo@x.com" could match "jo.smith@x.com" and grant
 * that customer's subscription to a different shopper.
 */
async function findCustomerId(
  baseUrl: string,
  email: string,
  token: string,
): Promise<string | number | null> {
  const { status, body } = await fluidGet(
    baseUrl,
    "/api/customers",
    { search_query: email, per_page: "5" },
    token,
  );
  if (status !== 200) return null;

  const customers = asRecord(body)?.customers;
  if (!Array.isArray(customers)) return null;

  const match = customers
    .map(asRecord)
    .find(
      (customer) =>
        typeof customer?.email === "string" &&
        customer.email.toLowerCase() === email.toLowerCase(),
    );

  const id = match?.id;
  return typeof id === "string" || typeof id === "number" ? id : null;
}

async function readMetafield(
  baseUrl: string,
  customerId: string | number,
  key: string,
  token: string,
) {
  return fluidGet(
    baseUrl,
    "/api/v2/metafields/show",
    {
      resource_type: "customer",
      resource_id: String(customerId),
      namespace: METAFIELD_NAMESPACE,
      key,
    },
    token,
  );
}

/**
 * Whether the subscription is recent enough to count.
 *
 * Rails answered `true` when the date could not be read or parsed — the
 * `subscription_status` flag has already said yes, and an unreadable date is
 * not evidence against it. Kept as-is.
 */
async function subscriptionDateIsCurrent(
  baseUrl: string,
  customerId: string | number,
  token: string,
): Promise<boolean> {
  const { status, body } = await readMetafield(
    baseUrl,
    customerId,
    "subscription_date",
    token,
  );
  if (status !== 200) return true;

  const value = asRecord(asRecord(body)?.metafield)?.value;
  if (typeof value !== "string" || value.trim() === "") return true;

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return true;

  const cutoff = new Date();
  cutoff.setMonth(cutoff.getMonth() - MAX_SUBSCRIPTION_AGE_MONTHS);
  return parsed > cutoff;
}

export async function hasActiveSubscription(
  email: string | null | undefined,
  company: SubscriptionCompany | null | undefined,
): Promise<boolean> {
  if (!email || email.trim() === "") return false;
  if (!company?.authenticationToken) return false;

  try {
    const { base_url: baseUrl } = await fluidApiSettings();
    const token = company.authenticationToken;

    const customerId = await findCustomerId(baseUrl, email, token);
    if (customerId === null) return false;

    const { status, body } = await readMetafield(
      baseUrl,
      customerId,
      "subscription_status",
      token,
    );
    if (status !== 200) return false;

    const value = asRecord(asRecord(body)?.metafield)?.value;
    if (value !== true && value !== "true") return false;

    return subscriptionDateIsCurrent(baseUrl, customerId, token);
  } catch (error) {
    // Never the response body: it carries customer PII.
    console.error(
      "[MetafieldSubscription] lookup failed:",
      error instanceof Error ? error.message : error,
    );
    return false;
  }
}
