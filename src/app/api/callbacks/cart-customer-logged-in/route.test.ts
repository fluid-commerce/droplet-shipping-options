/**
 * `cart_customer_logged_in` is the only route that WRITES subscription state,
 * so the properties worth pinning are: it stores what the metafield lookup
 * said, it asks fluid to reprice, and a request it cannot verify writes
 * nothing at all.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import { tokenDigest } from "@fluid-app/droplet-sdk";

import { companyFixture, registrationFixture } from "@/test/factories";
import { signedCallbackRequest } from "@/test/signing";

const mockPrisma = vi.hoisted(() => ({
  company: { findFirst: vi.fn() },
  cartSession: { findFirst: vi.fn(), create: vi.fn(), update: vi.fn() },
  fluidCallbackRegistration: { findUnique: vi.fn() },
}));
const mockSubscription = vi.hoisted(() => ({ hasActiveSubscription: vi.fn() }));
const mockRecalculate = vi.hoisted(() => ({ requestCartRecalculate: vi.fn() }));

vi.mock("@/lib/db", () => ({ prisma: mockPrisma, default: mockPrisma }));
vi.mock("@/lib/shipping/subscription", () => mockSubscription);
vi.mock("@/lib/shipping/recalculate", () => mockRecalculate);

const { POST } = await import("./route");

const TOKEN = "cvt_acme_token";
const SUBSCRIBER_COMPANY = companyFixture({
  settings: { free_shipping_for_subscribers: true },
});

const body = (over: Record<string, unknown> = {}) => ({
  cart: { id: 77, email: "shopper@example.com", cart_token: "crt_1", ...over },
  customer: { id: 5 },
  context: { customer_id: 5, company_id: 42, is_rep: false, customer_role: "customer" },
});

beforeEach(() => {
  vi.clearAllMocks();
  mockPrisma.fluidCallbackRegistration.findUnique.mockImplementation(
    async ({ where }: { where: { tokenDigest: string } }) =>
      where.tokenDigest === tokenDigest(TOKEN)
        ? registrationFixture({
            tokenDigest: tokenDigest(TOKEN),
            definitionName: "cart_customer_logged_in",
          })
        : null,
  );
  mockPrisma.company.findFirst.mockResolvedValue(SUBSCRIBER_COMPANY);
  mockPrisma.cartSession.findFirst.mockResolvedValue(null);
  mockSubscription.hasActiveSubscription.mockResolvedValue(true);
});

describe("POST /api/callbacks/cart-customer-logged-in", () => {
  it("stores the subscription answer against the cart and reports it", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: "https://droplet.test/api/callbacks/cart-customer-logged-in",
        body: body(),
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      success: true,
      has_subscription: true,
    });

    expect(mockSubscription.hasActiveSubscription).toHaveBeenCalledWith(
      "shopper@example.com",
      SUBSCRIBER_COMPANY,
    );
    expect(mockPrisma.cartSession.create).toHaveBeenCalledWith({
      data: {
        cartId: 77,
        email: "shopper@example.com",
        hasActiveSubscription: true,
      },
    });
  });

  it("updates the existing row rather than inserting a second one", async () => {
    mockPrisma.cartSession.findFirst.mockResolvedValue({ id: 9n, cartId: 77 });

    await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: "https://droplet.test/api/callbacks/cart-customer-logged-in",
        body: body(),
      }),
    );

    expect(mockPrisma.cartSession.update).toHaveBeenCalledWith({
      where: { id: 9n },
      data: { email: "shopper@example.com", hasActiveSubscription: true },
    });
    expect(mockPrisma.cartSession.create).not.toHaveBeenCalled();
  });

  it("asks fluid to reprice the cart, so shipping is recalculated with the new state", async () => {
    await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: "https://droplet.test/api/callbacks/cart-customer-logged-in",
        body: body(),
      }),
    );

    expect(mockRecalculate.requestCartRecalculate).toHaveBeenCalledWith(
      "crt_1",
      SUBSCRIBER_COMPANY.authenticationToken,
    );
  });

  it("skips the lookup entirely for a company without subscriber shipping", async () => {
    mockPrisma.company.findFirst.mockResolvedValue(companyFixture());

    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: "https://droplet.test/api/callbacks/cart-customer-logged-in",
        body: body(),
      }),
    );

    await expect(response.json()).resolves.toEqual({
      success: true,
      message: "Subscription check skipped",
    });
    expect(mockSubscription.hasActiveSubscription).not.toHaveBeenCalled();
    expect(mockPrisma.cartSession.create).not.toHaveBeenCalled();
  });

  it("writes nothing for a request it cannot verify, and still answers 200", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: "cvt_someone_else",
        url: "https://droplet.test/api/callbacks/cart-customer-logged-in",
        body: body(),
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ success: true });
    expect(mockPrisma.cartSession.create).not.toHaveBeenCalled();
    expect(mockPrisma.cartSession.update).not.toHaveBeenCalled();
    expect(mockSubscription.hasActiveSubscription).not.toHaveBeenCalled();
  });

  it("does nothing when the payload carries no cart id to key a session on", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: "https://droplet.test/api/callbacks/cart-customer-logged-in",
        body: { cart: { email: "shopper@example.com" } },
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ success: true });
    expect(mockPrisma.cartSession.create).not.toHaveBeenCalled();
  });
});
