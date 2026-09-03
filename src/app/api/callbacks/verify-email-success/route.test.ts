/**
 * `verify_email_success` shares its invalidation with `update_cart_email`, so
 * this file covers what is DIFFERENT about it: the response shape its
 * definition allows, and the null cart its definition says fluid may send —
 * which the Rails handler dereferenced unguarded and answered with a 500.
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
const URL_ = "https://droplet.test/api/callbacks/verify-email-success";

beforeEach(() => {
  vi.clearAllMocks();
  mockPrisma.fluidCallbackRegistration.findUnique.mockImplementation(
    async ({ where }: { where: { tokenDigest: string } }) =>
      where.tokenDigest === tokenDigest(TOKEN)
        ? registrationFixture({
            tokenDigest: tokenDigest(TOKEN),
            definitionName: "verify_email_success",
          })
        : null,
  );
  mockPrisma.company.findFirst.mockResolvedValue(companyFixture());
  mockPrisma.cartSession.findFirst.mockResolvedValue({
    id: 9n,
    cartId: 77,
    email: "shopper@example.com",
    hasActiveSubscription: true,
  });
});

describe("POST /api/callbacks/verify-email-success", () => {
  it("answers the acknowledgement shape verify_email_success.yml allows", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: {
          email: "shopper@example.com",
          cart: { id: 77, email: "shopper@example.com" },
        },
      }),
    );

    expect(response.status).toBe(200);
    // Exactly `{success}`. The definition's `{success, message}` branch sets
    // additionalProperties: false, so the `valid` key Rails also sent made the
    // response invalid against every branch.
    await expect(response.json()).resolves.toEqual({ success: true });
  });

  it("drops the session when the verified address is not the one that logged in", async () => {
    await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: { email: "someone.else@example.com", cart: { id: 77 } },
      }),
    );

    expect(mockPrisma.cartSession.deleteMany).toHaveBeenCalledWith({
      where: { cartId: 77 },
    });
  });

  it("answers 200 for the null cart the definition says fluid may send", async () => {
    // Rails read payload[:cart][:id] with no guard here and raised
    // NoMethodError — a 500 on a checkout callback.
    const response = await POST(
      signedCallbackRequest({
        token: TOKEN,
        url: URL_,
        body: { email: "shopper@example.com", cart: null, customer: null },
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ success: true });
    expect(mockPrisma.cartSession.deleteMany).not.toHaveBeenCalled();
  });

  it("touches nothing for a request it cannot verify, and still answers 200", async () => {
    const response = await POST(
      signedCallbackRequest({
        token: "cvt_someone_else",
        url: URL_,
        body: { email: "someone.else@example.com", cart: { id: 77 } },
      }),
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ success: true });
    expect(mockPrisma.cartSession.deleteMany).not.toHaveBeenCalled();
  });
});
