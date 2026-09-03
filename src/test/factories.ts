/**
 * Test fixtures.
 *
 * Shaped like the Prisma rows, BigInt ids included, so a test that gets them
 * wrong fails here rather than in production.
 */

export function companyFixture(overrides: Record<string, unknown> = {}) {
  return {
    id: 1n,
    fluidShop: "acme.fluid.app",
    authenticationToken: "cat_acme",
    name: "Acme",
    settings: {},
    webhookVerificationToken: "wvt_acme",
    fluidCompanyId: 42n,
    serviceCompanyId: null,
    companyDropletUuid: "drp_test",
    active: true,
    uninstalledAt: null,
    createdAt: new Date("2026-01-01T00:00:00Z"),
    updatedAt: new Date("2026-01-01T00:00:00Z"),
    dropletInstallationUuid: "dri_acme",
    installedCallbackIds: [],
    previousDris: [],
    ...overrides,
  };
}

export function registrationFixture(overrides: Record<string, unknown> = {}) {
  return {
    uuid: "cbr_acme",
    dri: "dri_acme",
    definitionName: "update_cart_shipping",
    tokenDigest: "unset",
    url: "https://droplet.test/api/callbacks/update-cart-shipping",
    ...overrides,
  };
}

/**
 * A `shipping_options` row with its rates, shaped the way
 * `prisma.shippingOption.findMany({ include: { rates: … } })` returns it —
 * Decimal columns included, because the calculator calls `.toNumber()` on them
 * and a plain JS number would let a test pass against code that cannot work.
 */
export function shippingOptionFixture(
  overrides: Record<string, unknown> = {},
  rates: Array<Record<string, unknown>> = [],
) {
  return {
    id: 10n,
    name: "Standard",
    deliveryTime: 3,
    startingRate: decimal(0),
    countries: ["US"],
    status: "active",
    companyId: 1n,
    createdAt: new Date("2026-01-01T00:00:00Z"),
    updatedAt: new Date("2026-01-01T00:00:00Z"),
    countrySortPositions: { US: 1 },
    rates: rates.map((rate) => rateFixture(rate)),
    ...overrides,
  };
}

export function rateFixture(overrides: Record<string, unknown> = {}) {
  return {
    id: 100n,
    shippingOptionId: 10n,
    country: "US",
    region: null,
    minRangeLbs: decimal(0),
    maxRangeLbs: decimal(10),
    flatRate: decimal(5),
    minCharge: decimal(0),
    createdAt: new Date("2026-01-01T00:00:00Z"),
    updatedAt: new Date("2026-01-01T00:00:00Z"),
    ...overrides,
  };
}

/**
 * Stands in for a Prisma Decimal. Only `toNumber()` is used by the calculator,
 * and importing Decimal.js here would tie the fixtures to the generated client.
 */
export function decimal(value: number) {
  return { toNumber: () => value };
}
