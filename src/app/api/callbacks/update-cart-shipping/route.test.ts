/**
 * The route, end to end, through the real wrapper with real signatures.
 *
 * Four properties, each of which has been a shipped defect somewhere in the
 * fleet:
 *
 *  1. a correctly signed request is PRICED, and served as the tenant the
 *     registration binds it to;
 *  2. an unknown token is refused — and still answers 200 with a body that
 *     leaves the cart's shipping alone, because fluid blocks a live checkout on
 *     this response;
 *  3. a payload naming a different company is still served as the
 *     registration's company; and
 *  4. a token issued for another definition cannot be replayed here.
 *
 * The first is the one that makes the rest meaningful: without it, a totally
 * misconfigured droplet that refused everything would pass this file.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import { tokenDigest } from "@fluid-app/droplet-sdk";

import {
  companyFixture,
  decimal,
  rateFixture,
  registrationFixture,
  shippingOptionFixture,
} from "@/test/factories";
import { signedCallbackRequest } from "@/test/signing";

const mockPrisma = vi.hoisted(() => ({
  company: { findFirst: vi.fn() },
  shippingOption: { findMany: vi.fn() },
  cartSession: { findFirst: vi.fn() },
  fluidCallbackRegistration: {
    findUnique: vi.fn(),
    upsert: vi.fn(),
    deleteMany: vi.fn(),
    count: vi.fn(),
  },
}));

vi.mock("@/lib/db", () => ({ prisma: mockPrisma, default: mockPrisma }));

const { POST } = await import("./route");

const TOKEN = "cvt_acme_token";
const OTHER_TOKEN = "cvt_someone_else";

/** What every failure path answers: an EMPTY list, not a zero-priced one. */
const NEUTRAL_BODY = { success: true, shipping_options: [] };

const cartBody = (over: Record<string, unknown> = {}) => ({
  change_type: "add_items",
  cart: {
    id: 77,
    email: "shopper@example.com",
    items: [
      { id: 1, quantity: 2, variant: { id: 2, weight: 1, unit_of_weight: "lb" } },
    ],
    ship_to: { country_code: "us", state: "ut" },
    ...over,
  },
});

beforeEach(() => {
  vi.clearAllMocks();
  mockPrisma.fluidCallbackRegistration.findUnique.mockImplementation(
    async ({ where }: { where: { tokenDigest: string } }) =>
      where.tokenDigest === tokenDigest(TOKEN)
        ? registrationFixture({ tokenDigest: tokenDigest(TOKEN) })
        : null,
  );
  mockPrisma.company.findFirst.mockResolvedValue(companyFixture());
  mockPrisma.cartSession.findFirst.mockResolvedValue(null);
  mockPrisma.shippingOption.findMany.mockResolvedValue([
    shippingOptionFixture({}, [rateFixture({ flatRate: decimal(6) })]),
  ]);
});

describe("POST /api/callbacks/update-cart-shipping", () => {
  it("prices a correctly signed cart as the registration's tenant", async () => {
    const response = await POST(
      signedCallbackRequest({ token: TOKEN, body: cartBody() }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      success: true,
      shipping_options: [
        {
          shipping_total: 6,
          shipping_title: "Standard",
          shipping_delivery_time_estimate: "3 days",
        },
      ],
    });

    // The tenant came from the registration's dri, not from the payload.
    expect(mockPrisma.company.findFirst).toHaveBeenCalledWith({
      where: {
        dropletInstallationUuid: "dri_acme",
        active: true,
        uninstalledAt: null,
      },
    });
    // ...and the options queried were that tenant's.
    expect(mockPrisma.shippingOption.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: 1n, status: "active" },
      }),
    );
  });

  it("upper-cases the destination before matching rates", async () => {
    await POST(signedCallbackRequest({ token: TOKEN, body: cartBody() }));

    // The fixture rate is country "US"; the payload said "us".
    expect(mockPrisma.shippingOption.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        include: {
          rates: { where: { country: "US" }, orderBy: { id: "asc" } },
        },
      }),
    );
  });

  it("refuses an unknown token, and still answers 200 with the neutral body", async () => {
    const response = await POST(
      signedCallbackRequest({ token: OTHER_TOKEN, body: cartBody() }),
    );

    // A 401 here would be a broken cart. The refusal is only visible in the
    // "[fluid-callback:update-cart-shipping] rejected" log line.
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(NEUTRAL_BODY);
    expect(mockPrisma.company.findFirst).not.toHaveBeenCalled();
    expect(mockPrisma.shippingOption.findMany).not.toHaveBeenCalled();
  });

  it("refuses a valid token whose signature was made with a different key", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        signingToken: "not-the-token",
        body: cartBody(),
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(NEUTRAL_BODY);
    expect(mockPrisma.company.findFirst).not.toHaveBeenCalled();
  });

  it("prices for the registration's company even when the body names another", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        body: {
          ...cartBody({ company: { id: 999, name: "Someone Else" } }),
        },
      }),
    );

    expect(response.status).toBe(200);
    expect(mockPrisma.company.findFirst).toHaveBeenCalledTimes(1);
    expect(mockPrisma.company.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ dropletInstallationUuid: "dri_acme" }),
      }),
    );
    expect(mockPrisma.shippingOption.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { companyId: 1n, status: "active" } }),
    );
  });

  it("refuses a token issued for a definition this route does not serve", async () => {
    mockPrisma.fluidCallbackRegistration.findUnique.mockResolvedValue(
      registrationFixture({
        tokenDigest: tokenDigest(TOKEN),
        definitionName: "update_cart_tax",
      }),
    );

    const response = await POST(
      signedCallbackRequest({ token: TOKEN, body: cartBody() }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(NEUTRAL_BODY);
    expect(mockPrisma.company.findFirst).not.toHaveBeenCalled();
  });

  it("refuses rather than 500s when the token store is unavailable", async () => {
    // The shape of deploying before db/migrate has created
    // fluid_callback_registrations.
    mockPrisma.fluidCallbackRegistration.findUnique.mockRejectedValue(
      new Error("relation does not exist"),
    );

    const response = await POST(
      signedCallbackRequest({ token: TOKEN, body: cartBody() }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(NEUTRAL_BODY);
  });

  it("refuses when the registration resolves to no active company", async () => {
    mockPrisma.company.findFirst.mockResolvedValue(null);

    const response = await POST(
      signedCallbackRequest({ token: TOKEN, body: cartBody() }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(NEUTRAL_BODY);
  });

  it("returns the neutral body, not an error, for a cart with no destination yet", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        body: cartBody({ ship_to: { country_code: "US" } }),
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(NEUTRAL_BODY);
    expect(mockPrisma.shippingOption.findMany).not.toHaveBeenCalled();
  });

  it("echoes logged_in_email only when the company has subscriber shipping on", async () => {
    mockPrisma.cartSession.findFirst.mockResolvedValue({
      id: 1n,
      cartId: 77,
      email: "shopper@example.com",
      hasActiveSubscription: false,
    });

    const off = await POST(
      signedCallbackRequest({ token: TOKEN, body: cartBody() }),
    );
    await expect(off.json()).resolves.not.toHaveProperty("logged_in_email");

    mockPrisma.company.findFirst.mockResolvedValue(
      companyFixture({ settings: { free_shipping_for_subscribers: true } }),
    );

    const on = await POST(
      signedCallbackRequest({ token: TOKEN, body: cartBody() }),
    );
    await expect(on.json()).resolves.toMatchObject({
      logged_in_email: "shopper@example.com",
    });
  });

  it("answers the neutral body rather than 500 when the calculation throws", async () => {
    mockPrisma.shippingOption.findMany.mockRejectedValue(new Error("db down"));

    const response = await POST(
      signedCallbackRequest({ token: TOKEN, body: cartBody() }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(NEUTRAL_BODY);
  });
});
