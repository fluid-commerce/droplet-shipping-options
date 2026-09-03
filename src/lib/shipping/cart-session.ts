/**
 * Per-cart record of who logged in and whether they hold a subscription.
 *
 * Port of `CartSessionService`. Written by `cart_customer_logged_in`, cleared by
 * the two email-change callbacks, and only ever READ by `update_cart_shipping`
 * — which is the point. Checking subscription status costs two Fluid API calls,
 * and `update_cart_shipping` is on the blocking checkout path.
 *
 * `cart_sessions.cart_id` carries a plain index, not a unique one (db/schema.rb),
 * even though the Rails model validates uniqueness. So every access here is
 * findFirst / deleteMany rather than findUnique / delete: `prisma.cartSession
 * .upsert({ where: { cartId } })` would not even compile, and if the column
 * ever does hold a duplicate, deleting "the" row would leave the other behind
 * holding stale subscription state.
 */

import { prisma } from "@/lib/db";

/** Normalises the cart id Fluid sends (number or numeric string) to an Int. */
export function toCartId(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const parsed = Number.parseInt(String(value), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

export interface CartSessionState {
  email: string | null;
  hasActiveSubscription: boolean;
}

export async function readCartSession(
  cartId: number,
): Promise<CartSessionState | null> {
  const row = await prisma.cartSession.findFirst({ where: { cartId } });
  if (!row) return null;

  return {
    email: row.email,
    // Rails compared `== true`, so a NULL column is false rather than unknown.
    hasActiveSubscription: row.hasActiveSubscription === true,
  };
}

export async function storeCartLogin(
  cartId: number,
  email: string,
  hasActiveSubscription: boolean,
): Promise<void> {
  const existing = await prisma.cartSession.findFirst({ where: { cartId } });

  if (existing) {
    await prisma.cartSession.update({
      where: { id: existing.id },
      data: { email, hasActiveSubscription },
    });
    return;
  }

  await prisma.cartSession.create({
    data: { cartId, email, hasActiveSubscription },
  });
}

export async function clearCartSession(cartId: number): Promise<void> {
  await prisma.cartSession.deleteMany({ where: { cartId } });
}
