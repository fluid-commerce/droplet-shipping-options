/**
 * Both email callbacks exist to INVALIDATE a stored login, so the tests are
 * about when the session is dropped and when it survives. Dropping it too
 * eagerly loses a subscriber their free shipping; not dropping it hands the
 * benefit to whoever types their address in next.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import { tokenDigest } from "@fluid-app/droplet-sdk";

import { companyFixture, registrationFixture } from "@/test/factories";
import { signedCallbackRequest } from "@/test/signing";

const mockPrisma = vi.hoisted(() => ({
  company: { findFirst: vi.fn() },
  cartSession: { findFirst: vi.fn(), deleteMany: vi.fn() },
  fluidCallbackRegistration: { findUnique: vi.fn() },
}));

vi.mock("@/lib/db", () => ({ prisma: mockPrisma, default: mockPrisma }));

const { POST } = await import("./route");

const TOKEN = "cvt_acme_token";
const URL_ = "https://droplet.test/api/callbacks/update-cart-email";
const ACCEPTED = { success: true, valid: true };

const storedLogin = (email = "shopper@example.com") => ({
  id: 9n,
  cartId: 77,
  email,
  hasActiveSubscription: true,
});

beforeEach(() => {
  vi.clearAllMocks();
  mockPrisma.fluidCallbackRegistration.findUnique.mockImplementation(
    async ({ where }: { where: { tokenDigest: string } }) =>
      where.tokenDigest === tokenDigest(TOKEN)
        ? registrationFixture({
            tokenDigest: tokenDigest(TOKEN),
            definitionName: "update_cart_email",
          })
        : null,
  );
  mockPrisma.company.findFirst.mockResolvedValue(companyFixture());
  mockPrisma.cartSession.findFirst.mockResolvedValue(storedLogin());
});

describe("POST /api/callbacks/update-cart-email", () => {
  it("drops the session when the email changes to a different address", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: {
          email: "someone.else@example.com",
          previous_email: "shopper@example.com",
          cart: { id: 77, email: "shopper@example.com" },
        },
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(ACCEPTED);
    expect(mockPrisma.cartSession.deleteMany).toHaveBeenCalledWith({
      where: { cartId: 77 },
    });
  });

  it("drops the session when the email is cleared", async () => {
    await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: { email: "", cart: { id: 77, email: null } },
      }),
    );

    expect(mockPrisma.cartSession.deleteMany).toHaveBeenCalledWith({
      where: { cartId: 77 },
    });
  });

  it("keeps the session when the same address is set again", async () => {
    await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: {
          email: "shopper@example.com",
          cart: { id: 77, email: "shopper@example.com" },
        },
      }),
    );

    // Re-clearing here would silently drop the subscription answer and reprice
    // the cart as if nobody had logged in.
    expect(mockPrisma.cartSession.deleteMany).not.toHaveBeenCalled();
  });

  it("compares addresses case-insensitively", async () => {
    mockPrisma.cartSession.findFirst.mockResolvedValue(
      storedLogin("Shopper@Example.com"),
    );

    await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: { email: "shopper@example.com", cart: { id: 77 } },
      }),
    );

    expect(mockPrisma.cartSession.deleteMany).not.toHaveBeenCalled();
  });

  it("prefers the top-level email over the stale one on the cart object", async () => {
    // `update_cart_email` sends the NEW address at the top level; the embedded
    // cart still carries the old one. Reading the cart's copy would compare the
    // stored email against itself and never invalidate anything.
    await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: {
          email: "new@example.com",
          cart: { id: 77, email: "shopper@example.com" },
        },
      }),
    );

    expect(mockPrisma.cartSession.deleteMany).toHaveBeenCalledWith({
      where: { cartId: 77 },
    });
  });

  it("does nothing when there is no stored login to invalidate", async () => {
    mockPrisma.cartSession.findFirst.mockResolvedValue(null);

    await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: { email: "new@example.com", cart: { id: 77 } },
      }),
    );

    expect(mockPrisma.cartSession.deleteMany).not.toHaveBeenCalled();
  });

  it("touches nothing for a request it cannot verify, and still answers 200", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: "cvt_someone_else",
        url: URL_,
        body: { email: "new@example.com", cart: { id: 77 } },
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(ACCEPTED);
    expect(mockPrisma.cartSession.findFirst).not.toHaveBeenCalled();
    expect(mockPrisma.cartSession.deleteMany).not.toHaveBeenCalled();
  });

  it("refuses a token issued for verify_email_success", async () => {
    mockPrisma.fluidCallbackRegistration.findUnique.mockResolvedValue(
      registrationFixture({
        tokenDigest: tokenDigest(TOKEN),
        definitionName: "verify_email_success",
      }),
    );

    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: { email: "new@example.com", cart: { id: 77 } },
      }),
    );

    expect(response.status).toBe(200);
    expect(mockPrisma.company.findFirst).not.toHaveBeenCalled();
    expect(mockPrisma.cartSession.deleteMany).not.toHaveBeenCalled();
  });
});
