import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ProductCard, RatingStars, StockBadge } from "@/components/ProductCard";
import type { ProductSummary } from "@/lib/api";

const product: ProductSummary = {
  id: 1,
  slug: "apparel-aurora-jacket-00",
  name: "Aurora Jacket",
  price_cents: 1290000,
  image_path: "/img/products/apparel-00.webp",
  category_slug: "apparel",
  category_name: "Apparel",
  in_stock: true,
  rating: 4.2,
  review_count: 23,
};

describe("ProductCard", () => {
  it("links to the product using its slug", () => {
    render(<ProductCard product={product} />);
    expect(screen.getByRole("link")).toHaveProperty(
      "href",
      expect.stringContaining("/products/apparel-aurora-jacket-00"),
    );
  });

  it("requests the image from /img/, not /products/", () => {
    // /products/<file>.webp collides with the /products/[slug] route: the
    // request matched the page, returned 200 with HTML under an <img> tag, and
    // every card silently fell back to its gradient. This asserts the fix.
    render(<ProductCard product={product} />);
    const image = document.querySelector("img");
    expect(image?.getAttribute("src")).toMatch(/^\/img\/products\//);
  });

  it("gives the image an empty alt because the name is already a heading", () => {
    // Repeating the product name in alt text makes a screen reader announce it
    // twice for one card.
    render(<ProductCard product={product} />);
    expect(document.querySelector("img")?.getAttribute("alt")).toBe("");
  });
});

describe("RatingStars", () => {
  it("says so when a product has no reviews", () => {
    render(<RatingStars rating={null} count={0} />);
    expect(screen.getByText(/no reviews/i)).toBeTruthy();
  });

  it("exposes the rating to assistive technology as text", () => {
    // The stars are aria-hidden decoration; without this the rating is
    // invisible to anyone not looking at the glyphs.
    render(<RatingStars rating={4.2} count={23} />);
    expect(screen.getByText("4.2 out of 5")).toBeTruthy();
  });
});

describe("StockBadge", () => {
  it("distinguishes in stock from out of stock", () => {
    const { unmount } = render(<StockBadge inStock />);
    expect(screen.getByText("In stock")).toBeTruthy();
    unmount();

    render(<StockBadge inStock={false} />);
    expect(screen.getByText("Out of stock")).toBeTruthy();
  });
});
