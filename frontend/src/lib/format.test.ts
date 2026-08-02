import { describe, expect, it } from "vitest";

import { formatPrice, slugHue } from "@/lib/format";

describe("formatPrice", () => {
  it("renders integer cents as currency", () => {
    // Asserted on the digits rather than the exact string, because the
    // separator and symbol placement come from Intl and vary by ICU build --
    // a test that pins the whole string fails on a different Node image
    // without anything being wrong.
    expect(formatPrice(1290000).replace(/\D/g, "")).toBe("1290000");
  });

  it("handles zero", () => {
    expect(formatPrice(0)).toContain("0");
  });

  it("never introduces a fractional part", () => {
    // The column is integer cents precisely so nothing rounds. A formatter
    // that reintroduces decimals would undo that.
    expect(formatPrice(999)).not.toMatch(/[.,]\d\d\b/);
  });
});

describe("slugHue", () => {
  it("is deterministic", () => {
    // The placeholder colour must be identical across renders and across
    // environments. A random hue would mean a screenshot from staging did not
    // describe production.
    expect(slugHue("apparel-aurora-jacket-00")).toBe(
      slugHue("apparel-aurora-jacket-00"),
    );
  });

  it("stays inside the hue circle", () => {
    for (const slug of ["a", "apparel-aurora-jacket-00", "x".repeat(200), ""]) {
      const hue = slugHue(slug);
      expect(hue).toBeGreaterThanOrEqual(0);
      expect(hue).toBeLessThan(360);
    }
  });

  it("separates different products", () => {
    const hues = new Set(
      ["apparel-00", "footwear-01", "home-02", "outdoor-03"].map(slugHue),
    );
    expect(hues.size).toBeGreaterThan(1);
  });
});
