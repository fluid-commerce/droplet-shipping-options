/**
 * Every body these four routes can emit, checked against the response schema
 * fluid publishes for its definition.
 *
 * This is not pedantry. `Callback::Client#classify_response` in fluid validates
 * each response against `response_schema` and classifies a failure as
 * `:schema_invalid`, which raises a Sentry report and a Slack notification for
 * every affected request — and the classification is one line away from being
 * enforcement. The Rails app shipped two bodies that fail: the
 * coordinate-with-the-shop fallback (an integer where a string is required) and
 * `verify_email_success` (a `valid` key on a branch that forbids extra keys).
 *
 * The schemas are transcribed from
 * fluid-main/app/lib/callback_definitions/<name>.yml. They are inlined rather
 * than read from disk because that repo is not checked out in CI — so when a
 * definition changes upstream, this file is what has to be updated, and the
 * mismatch shows up here rather than in a Slack alert.
 */

import { describe, it, expect } from "vitest";
import Ajv2020 from "ajv/dist/2020";

import { NEUTRAL_RESULT } from "./types";

const ajv = new Ajv2020({ strict: false, allErrors: true });

function check(schema: object, body: unknown) {
  const validate = ajv.compile(schema);
  const ok = validate(body);
  return { ok, errors: validate.errors ?? [] };
}

/** update_cart_shipping.yml — response_schema */
const UPDATE_CART_SHIPPING = {
  oneOf: [
    { type: "object", maxProperties: 0 },
    {
      type: "object",
      required: ["shipping_options"],
      properties: {
        shipping_options: {
          type: "array",
          items: {
            type: "object",
            required: ["shipping_total"],
            properties: {
              shipping_total: { type: ["number", "string"] },
              shipping_title: { type: "string" },
              shipping_code: { type: "string" },
              shipping_delivery_time_estimate: { type: "string" },
            },
          },
        },
      },
    },
  ],
};

/** cart_customer_logged_in.yml — response_schema */
const CART_CUSTOMER_LOGGED_IN = {
  type: "object",
  required: ["success"],
  properties: {
    success: { type: "boolean" },
    message: { type: "string" },
    data: { type: "object" },
  },
};

/** update_cart_email.yml — response_schema */
const UPDATE_CART_EMAIL = {
  type: "object",
  required: ["success", "valid"],
  properties: {
    success: { type: "boolean" },
    valid: { type: "boolean" },
    message: { type: "string" },
    error_code: { type: "string" },
    metadata: { type: "object" },
  },
};

/** verify_email_success.yml — response_schema */
const VERIFY_EMAIL_SUCCESS = {
  oneOf: [
    { type: "object", required: ["ok"], properties: { ok: { type: "boolean" } } },
    {
      type: "object",
      required: ["success"],
      properties: { success: { type: "boolean" }, message: { type: "string" } },
      additionalProperties: false,
    },
    { type: "object", maxProperties: 0 },
  ],
};

describe("update_cart_shipping responses", () => {
  it("accepts the neutral body every failure path returns", () => {
    expect(check(UPDATE_CART_SHIPPING, NEUTRAL_RESULT)).toMatchObject({
      ok: true,
    });
  });

  it("accepts an ordinary priced option", () => {
    const body = {
      success: true,
      shipping_options: [
        {
          shipping_total: 6,
          shipping_title: "Standard",
          shipping_delivery_time_estimate: "3 days",
        },
      ],
    };
    expect(check(UPDATE_CART_SHIPPING, body)).toMatchObject({ ok: true });
  });

  it("accepts the coordinate-with-the-shop fallback", () => {
    // Rails sent the INTEGER 0 for the estimate here, which fails this schema
    // on `shipping_delivery_time_estimate` — see calculate.ts. The string does
    // not.
    const body = {
      success: true,
      shipping_options: [
        {
          shipping_total: 0,
          shipping_title: "Coordinate with the shop",
          shipping_delivery_time_estimate: "0",
        },
      ],
    };
    expect(check(UPDATE_CART_SHIPPING, body)).toMatchObject({ ok: true });
  });

  it("rejects the integer estimate the Rails app sent, so this test can fail", () => {
    const railsBody = {
      success: true,
      shipping_options: [
        {
          shipping_total: 0,
          shipping_title: "Coordinate with the shop",
          shipping_delivery_time_estimate: 0,
        },
      ],
    };
    const result = check(UPDATE_CART_SHIPPING, railsBody);
    expect(result.ok).toBe(false);
    expect(
      result.errors.some((e) =>
        e.instancePath.endsWith("shipping_delivery_time_estimate"),
      ),
    ).toBe(true);
  });

  it("accepts the logged_in_email key the route adds", () => {
    const body = {
      ...NEUTRAL_RESULT,
      shipping_options: [{ shipping_total: 5, shipping_title: "S", shipping_delivery_time_estimate: "1 day" }],
      logged_in_email: "shopper@example.com",
    };
    expect(check(UPDATE_CART_SHIPPING, body)).toMatchObject({ ok: true });
  });
});

describe("the other three routes' bodies", () => {
  it("cart_customer_logged_in: both bodies are valid", () => {
    expect(
      check(CART_CUSTOMER_LOGGED_IN, { success: true, has_subscription: true }),
    ).toMatchObject({ ok: true });
    expect(
      check(CART_CUSTOMER_LOGGED_IN, {
        success: true,
        message: "Subscription check skipped",
      }),
    ).toMatchObject({ ok: true });
    expect(check(CART_CUSTOMER_LOGGED_IN, { success: true })).toMatchObject({
      ok: true,
    });
  });

  it("update_cart_email: the accept body carries both required keys", () => {
    expect(
      check(UPDATE_CART_EMAIL, { success: true, valid: true }),
    ).toMatchObject({ ok: true });
    // `valid` is required, so the bare acknowledgement is NOT valid here — the
    // reason this route and verify_email_success answer differently.
    expect(check(UPDATE_CART_EMAIL, { success: true })).toMatchObject({
      ok: false,
    });
  });

  it("verify_email_success: {success} is valid and Rails' {success, valid} is not", () => {
    expect(check(VERIFY_EMAIL_SUCCESS, { success: true })).toMatchObject({
      ok: true,
    });
    // The branch that allows `success` sets additionalProperties: false, so the
    // `valid` key Rails also sent matches none of the three branches.
    expect(
      check(VERIFY_EMAIL_SUCCESS, { success: true, valid: true }),
    ).toMatchObject({ ok: false });
  });
});
