import { describe, it, expect } from "vitest";

import { convertToPounds, totalWeightLbs } from "./weight";

describe("convertToPounds", () => {
  it("converts each unit the Rails service converted", () => {
    expect(convertToPounds(1, "kg")).toBeCloseTo(2.20462, 5);
    expect(convertToPounds(1, "KILOGRAMS")).toBeCloseTo(2.20462, 5);
    expect(convertToPounds(1000, "g")).toBeCloseTo(2.20462, 5);
    expect(convertToPounds(16, "oz")).toBeCloseTo(1, 5);
  });

  it("treats a missing or unknown unit as pounds", () => {
    expect(convertToPounds(3, null)).toBe(3);
    expect(convertToPounds(3, "stone")).toBe(3);
  });
});

describe("totalWeightLbs", () => {
  const item = (over: Record<string, unknown> = {}) => ({
    id: 1,
    quantity: 1,
    variant: { id: 2, weight: 1, unit_of_weight: "lb" },
    ...over,
  });

  it("multiplies weight by quantity and rounds to 2dp", () => {
    expect(totalWeightLbs([item({ quantity: 3 })])).toBe(3);
    expect(
      totalWeightLbs([
        item({ quantity: 2, variant: { weight: 1, unit_of_weight: "kg" } }),
      ]),
    ).toBe(4.41);
  });

  it("sums across items", () => {
    expect(
      totalWeightLbs([
        item({ quantity: 2 }),
        item({ quantity: 1, variant: { weight: 0.5, unit_of_weight: "lb" } }),
      ]),
    ).toBe(2.5);
  });

  it("skips an item with no variant, no weight, or no quantity", () => {
    expect(totalWeightLbs([item({ variant: null })])).toBe(0);
    expect(
      totalWeightLbs([item({ variant: { weight: null, unit_of_weight: "lb" } })]),
    ).toBe(0);
    expect(totalWeightLbs([item({ quantity: null })])).toBe(0);
  });

  it("reads the numeric strings fluid actually sends", () => {
    // Cart JSON carries weights and quantities as strings often enough that
    // arithmetic on them raw would concatenate rather than add.
    expect(
      totalWeightLbs([
        item({ quantity: "3", variant: { weight: "2.5", unit_of_weight: "lb" } }),
      ]),
    ).toBe(7.5);
  });

  it("drops an unparseable weight instead of poisoning the whole total", () => {
    // Without the isFinite guard this is NaN, NaN fails every `>=` band
    // comparison, and the cart silently gets no shipping options at all — for
    // one bad variant among many.
    expect(
      totalWeightLbs([
        item({ quantity: 1, variant: { weight: "heavy", unit_of_weight: "lb" } }),
        item({ quantity: 1, variant: { weight: 2, unit_of_weight: "lb" } }),
      ]),
    ).toBe(2);
  });

  it("rounds the way Ruby rounds, not the way Math.round does", () => {
    // Every value here is one where `Math.round(x * 100) / 100` disagrees with
    // Ruby's `Float#round(2)`. The expectations are real `ruby -e` output, not
    // derived from the implementation:
    //
    //   1.005.round(2) # => 1.01     Math.round(1.005 * 100) / 100 === 1
    //   0.145.round(2) # => 0.15     Math.round(0.145 * 100) / 100 === 0.14
    //   1.015.round(2) # => 1.02     Math.round(1.015 * 100) / 100 === 1.01
    //
    // A single 1.005 lb item lands on 1.00 under the naive version and 1.01
    // under Rails, which with contiguous 0–1.00 and 1.01–10 bands is a
    // different price for the same cart in the two apps.
    const one = (weight: number) =>
      totalWeightLbs([
        { id: 1, quantity: 1, variant: { weight, unit_of_weight: "lb" } },
      ]);

    expect(one(1.005)).toBe(1.01);
    expect(one(0.145)).toBe(0.15);
    expect(one(1.015)).toBe(1.02);

    // ...and the cases where the two agree still agree.
    expect(one(2.675)).toBe(2.68);
    expect(one(4.405)).toBe(4.41);
    expect(one(8.835)).toBe(8.84);
  });

  it("is 0 for an empty or missing cart", () => {
    expect(totalWeightLbs([])).toBe(0);
    expect(totalWeightLbs(null)).toBe(0);
    expect(totalWeightLbs(undefined)).toBe(0);
  });
});
