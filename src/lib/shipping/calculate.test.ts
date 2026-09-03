/**
 * The pricing rules, against the real calculator with fixture rows.
 *
 * Every assertion here is a rule the Rails service had and a shopper can see:
 * which band is chosen, whether a region rate beats a country rate, what
 * happens when a company serves no option for the destination, and who gets
 * free shipping.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

import {
  companyFixture,
  decimal,
  rateFixture,
  shippingOptionFixture,
} from "@/test/factories";

const mockPrisma = vi.hoisted(() => ({
  shippingOption: { findMany: vi.fn() },
  cartSession: { findFirst: vi.fn() },
}));

vi.mock("@/lib/db", () => ({ prisma: mockPrisma, default: mockPrisma }));

const { calculateShipping, freeShippingEnabled } = await import("./calculate");

const company = () => companyFixture() as unknown as { id: bigint; settings: unknown };

const subscriberCompany = () =>
  companyFixture({
    settings: { free_shipping_for_subscribers: true },
  }) as unknown as { id: bigint; settings: unknown };

const base = {
  shipToCountry: "US",
  shipToState: "UT",
  items: [{ id: 1, quantity: 1, variant: { id: 2, weight: 1, unit_of_weight: "lb" } }],
  cartId: 77,
  cartEmail: null as string | null,
};

beforeEach(() => {
  vi.clearAllMocks();
  mockPrisma.cartSession.findFirst.mockResolvedValue(null);
});

describe("freeShippingEnabled", () => {
  it("accepts the boolean the form writes and the string older rows hold", () => {
    expect(freeShippingEnabled({ free_shipping_for_subscribers: true })).toBe(true);
    expect(freeShippingEnabled({ free_shipping_for_subscribers: "true" })).toBe(true);
  });

  it("is false for anything else, including a missing settings blob", () => {
    expect(freeShippingEnabled({ free_shipping_for_subscribers: false })).toBe(false);
    expect(freeShippingEnabled({})).toBe(false);
    expect(freeShippingEnabled(null)).toBe(false);
  });
});

describe("calculateShipping", () => {
  it("prices the band the cart's weight falls into", async () => {
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture({}, [
        rateFixture({ id: 100n, minRangeLbs: decimal(0), maxRangeLbs: decimal(1) , flatRate: decimal(4) }),
        rateFixture({ id: 101n, minRangeLbs: decimal(1), maxRangeLbs: decimal(10), flatRate: decimal(9) }),
      ]),
    ]);

    const result = await calculateShipping({
      ...base,
      company: company(),
      items: [
        { id: 1, quantity: 3, variant: { id: 2, weight: 1, unit_of_weight: "lb" } },
      ],
    });

    expect(result).toEqual({
      success: true,
      shipping_options: [
        {
          shipping_total: 9,
          shipping_title: "Standard",
          shipping_delivery_time_estimate: "3 days",
        },
      ],
    });
  });

  it("charges min_charge when it exceeds the flat rate", async () => {
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture({}, [
        rateFixture({ flatRate: decimal(2), minCharge: decimal(7.5) }),
      ]),
    ]);

    const result = await calculateShipping({ ...base, company: company() });

    expect(result.shipping_options[0].shipping_total).toBe(7.5);
  });

  it("prefers a region rate over the country rate for the same band", async () => {
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture({}, [
        rateFixture({ id: 100n, region: null, flatRate: decimal(5) }),
        rateFixture({ id: 101n, region: "UT", flatRate: decimal(3) }),
      ]),
    ]);

    const result = await calculateShipping({ ...base, company: company() });

    expect(result.shipping_options[0].shipping_total).toBe(3);
  });

  it("falls back to the country rate when no region rate matches the state", async () => {
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture({}, [
        rateFixture({ id: 100n, region: null, flatRate: decimal(5) }),
        rateFixture({ id: 101n, region: "CA", flatRate: decimal(3) }),
      ]),
    ]);

    const result = await calculateShipping({ ...base, company: company() });

    expect(result.shipping_options[0].shipping_total).toBe(5);
  });

  it("drops an option whose bands do not cover the cart weight", async () => {
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture({}, [
        rateFixture({ minRangeLbs: decimal(50), maxRangeLbs: decimal(100) }),
      ]),
    ]);

    const result = await calculateShipping({ ...base, company: company() });

    // Not the "Coordinate with the shop" fallback: an option DID serve this
    // country, it just had no band. An empty list leaves the cart's existing
    // shipping untouched.
    expect(result).toEqual({ success: true, shipping_options: [] });
  });

  it("offers the coordinate-with-the-shop option when no option serves the country", async () => {
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture({ countries: ["CA"] }, [rateFixture()]),
    ]);

    const result = await calculateShipping({ ...base, company: company() });

    expect(result.shipping_options).toEqual([
      {
        shipping_total: 0,
        shipping_title: "Coordinate with the shop",
        shipping_delivery_time_estimate: "0",
      },
    ]);
  });

  it("treats a whitespace-only region as country-level, as Rails did", async () => {
    // `rates.region` has no NOT-BLANK constraint and no model validation, and
    // Rails asked `state_code.blank?` — so " " is a country-level rate there.
    // Under a plain truthiness test it would be neither country-level nor a
    // match for any state, and the option would lose its only rate.
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture({}, [
        rateFixture({ region: "  ", flatRate: decimal(7) }),
      ]),
    ]);

    const result = await calculateShipping({ ...base, company: company() });

    expect(result.shipping_options).toHaveLength(1);
    expect(result.shipping_options[0].shipping_total).toBe(7);
  });

  it("settles two overlapping bands by rate id rather than by query plan", async () => {
    // The Rails overlap validation permits adjacent bands, and both ends are
    // inclusive, so a 5 lb cart matches BOTH of these. Nothing ordered the
    // rates in either app; this pins the tie-break.
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture({}, [
        rateFixture({
          id: 100n,
          minRangeLbs: decimal(0),
          maxRangeLbs: decimal(5),
          flatRate: decimal(4),
        }),
        rateFixture({
          id: 101n,
          minRangeLbs: decimal(5),
          maxRangeLbs: decimal(10),
          flatRate: decimal(9),
        }),
      ]),
    ]);

    const result = await calculateShipping({
      ...base,
      company: company(),
      items: [
        { id: 1, quantity: 5, variant: { id: 2, weight: 1, unit_of_weight: "lb" } },
      ],
    });

    expect(result.shipping_options[0].shipping_total).toBe(4);
    // ...and the query asked for that order rather than relying on the plan.
    expect(mockPrisma.shippingOption.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        include: {
          rates: { where: { country: "US" }, orderBy: { id: "asc" } },
        },
      }),
    );
  });

  it("orders options by this country's sort position, then by id", async () => {
    mockPrisma.shippingOption.findMany.mockResolvedValue([
      shippingOptionFixture(
        { id: 10n, name: "Slow", countrySortPositions: { US: 2 } },
        [rateFixture({ shippingOptionId: 10n, flatRate: decimal(1) })],
      ),
      shippingOptionFixture(
        { id: 11n, name: "Fast", countrySortPositions: { US: 1 } },
        [rateFixture({ shippingOptionId: 11n, flatRate: decimal(2) })],
      ),
      shippingOptionFixture(
        // No position for US at all: sorts last, as COALESCE(..., 2147483647).
        { id: 12n, name: "Unpositioned", countrySortPositions: { CA: 1 } },
        [rateFixture({ shippingOptionId: 12n, flatRate: decimal(3) })],
      ),
    ]);

    const result = await calculateShipping({ ...base, company: company() });

    expect(result.shipping_options.map((o) => o.shipping_title)).toEqual([
      "Fast",
      "Slow",
      "Unpositioned",
    ]);
  });

  it("formats the delivery estimate the way Rails formatted it", async () => {
    for (const [deliveryTime, expected] of [
      [0, "Available same day"],
      [1, "1 day"],
      [4, "4 days"],
    ] as const) {
      mockPrisma.shippingOption.findMany.mockResolvedValue([
        shippingOptionFixture({ deliveryTime }, [rateFixture()]),
      ]);

      const result = await calculateShipping({ ...base, company: company() });
      expect(result.shipping_options[0].shipping_delivery_time_estimate).toBe(
        expected,
      );
    }
  });

  it("refuses to price without a destination", async () => {
    const result = await calculateShipping({
      ...base,
      company: company(),
      shipToState: null,
    });

    expect(result).toEqual({
      success: false,
      error: "Invalid parameters",
      shipping_options: [],
    });
    expect(mockPrisma.shippingOption.findMany).not.toHaveBeenCalled();
  });

  describe("free shipping for subscribers", () => {
    const twoOptions = () => [
      shippingOptionFixture({ id: 10n, name: "Express", countrySortPositions: { US: 1 } }, [
        rateFixture({ shippingOptionId: 10n, flatRate: decimal(20) }),
      ]),
      shippingOptionFixture({ id: 11n, name: "Standard", countrySortPositions: { US: 2 } }, [
        rateFixture({ shippingOptionId: 11n, flatRate: decimal(8) }),
      ]),
    ];

    it("zeroes only the cheapest option for a stored subscriber", async () => {
      mockPrisma.shippingOption.findMany.mockResolvedValue(twoOptions());
      mockPrisma.cartSession.findFirst.mockResolvedValue({
        id: 1n,
        cartId: 77,
        email: "sub@example.com",
        hasActiveSubscription: true,
      });

      const result = await calculateShipping({
        ...base,
        company: subscriberCompany(),
        cartEmail: "sub@example.com",
      });

      expect(
        result.shipping_options.map((o) => [o.shipping_title, o.shipping_total]),
      ).toEqual([
        ["Express", 20],
        ["Standard", 0],
      ]);
    });

    it("does not zero anything when the company has the feature off", async () => {
      mockPrisma.shippingOption.findMany.mockResolvedValue(twoOptions());
      mockPrisma.cartSession.findFirst.mockResolvedValue({
        id: 1n,
        cartId: 77,
        email: "sub@example.com",
        hasActiveSubscription: true,
      });

      const result = await calculateShipping({
        ...base,
        company: company(),
        cartEmail: "sub@example.com",
      });

      expect(result.shipping_options.map((o) => o.shipping_total)).toEqual([20, 8]);
    });

    it("does not zero anything when the cart's email is no longer the one that logged in", async () => {
      mockPrisma.shippingOption.findMany.mockResolvedValue(twoOptions());
      mockPrisma.cartSession.findFirst.mockResolvedValue({
        id: 1n,
        cartId: 77,
        email: "sub@example.com",
        hasActiveSubscription: true,
      });

      const result = await calculateShipping({
        ...base,
        company: subscriberCompany(),
        cartEmail: "someone.else@example.com",
      });

      expect(result.shipping_options.map((o) => o.shipping_total)).toEqual([20, 8]);
    });

    it("matches the stored email case-insensitively", async () => {
      mockPrisma.shippingOption.findMany.mockResolvedValue(twoOptions());
      mockPrisma.cartSession.findFirst.mockResolvedValue({
        id: 1n,
        cartId: 77,
        email: "Sub@Example.com",
        hasActiveSubscription: true,
      });

      const result = await calculateShipping({
        ...base,
        company: subscriberCompany(),
        cartEmail: "sub@example.com",
      });

      expect(result.shipping_options.map((o) => o.shipping_total)).toEqual([20, 0]);
    });

    it("does not zero anything when the stored session says not subscribed", async () => {
      mockPrisma.shippingOption.findMany.mockResolvedValue(twoOptions());
      mockPrisma.cartSession.findFirst.mockResolvedValue({
        id: 1n,
        cartId: 77,
        email: "sub@example.com",
        hasActiveSubscription: null,
      });

      const result = await calculateShipping({
        ...base,
        company: subscriberCompany(),
        cartEmail: "sub@example.com",
      });

      expect(result.shipping_options.map((o) => o.shipping_total)).toEqual([20, 8]);
    });
  });
});
