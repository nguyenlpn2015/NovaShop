"use client";

import { useState } from "react";

import { useCart } from "@/components/CartProvider";

export function AddToCart({
  productId,
  inStock,
}: {
  productId: number;
  inStock: boolean;
}) {
  const { cart, setQuantity, busy } = useCart();
  const [pending, setPending] = useState(false);

  const existing =
    cart.items.find((item) => item.product_id === productId)?.quantity ?? 0;

  async function add() {
    setPending(true);
    // Absolute quantity, not a delta -- the endpoint is idempotent so a
    // double-click adds one item, not two.
    await setQuantity(productId, Math.min(existing + 1, 10));
    setPending(false);
  }

  return (
    <div className="mt-7 flex flex-wrap items-center gap-3">
      <button
        type="button"
        onClick={add}
        disabled={!inStock || busy || pending || existing >= 10}
        className="btn-primary w-full py-3.5 text-base sm:w-auto sm:px-8"
      >
        {!inStock
          ? "Out of stock"
          : existing >= 10
            ? "Maximum quantity"
            : pending
              ? "Adding…"
              : "Add to cart"}
      </button>
      {existing > 0 && (
        <span className="text-sm text-content-muted">
          {existing} already in your cart
        </span>
      )}
    </div>
  );
}
