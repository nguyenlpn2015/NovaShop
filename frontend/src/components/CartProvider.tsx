"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";

import { useToast } from "@/components/Toast";

export type CartItem = {
  product_id: number;
  slug: string;
  name: string;
  image_path: string;
  unit_price_cents: number;
  quantity: number;
  subtotal_cents: number;
  in_stock: boolean;
};

export type Cart = {
  cart_id: string;
  items: CartItem[];
  total_cents: number;
  item_count: number;
};

const EMPTY: Cart = { cart_id: "", items: [], total_cents: 0, item_count: 0 };

type CartApi = {
  cart: Cart;
  busy: boolean;
  setQuantity: (productId: number, quantity: number) => Promise<void>;
  refresh: () => Promise<void>;
  checkout: () => Promise<number | null>;
};

const CartContext = createContext<CartApi>({
  cart: EMPTY,
  busy: false,
  setQuantity: async () => {},
  refresh: async () => {},
  checkout: async () => null,
});

export function useCart() {
  return useContext(CartContext);
}

const STORAGE_KEY = "novashop-cart-id";

/**
 * The cart identifier lives in localStorage, and the cart itself lives in
 * Redis on the server. Only the id is held here.
 *
 * Keeping the contents in the browser would make the cart a client-side
 * feature and demonstrate nothing about the platform. Keeping only the id means
 * the cart survives a refresh, a new tab, and a pod restart -- which is the
 * point worth showing.
 *
 * The id is generated once and matches the character set the backend accepts,
 * because it becomes part of a Redis key.
 */
function readOrCreateId(): string {
  const existing = localStorage.getItem(STORAGE_KEY);
  if (existing) return existing;
  const created =
    typeof crypto !== "undefined" && "randomUUID" in crypto
      ? crypto.randomUUID().replace(/-/g, "")
      : Math.random().toString(36).slice(2).padEnd(16, "0");
  localStorage.setItem(STORAGE_KEY, created);
  return created;
}

export function CartProvider({ children }: { children: ReactNode }) {
  const [cartId, setCartId] = useState<string | null>(null);
  const [cart, setCart] = useState<Cart>(EMPTY);
  const [busy, setBusy] = useState(false);
  const toast = useToast();

  // localStorage is unavailable during server rendering, so the id is resolved
  // after mount. Until then the badge shows nothing rather than zero -- a zero
  // that becomes three is a worse first impression than a blank that fills in.
  useEffect(() => setCartId(readOrCreateId()), []);

  const refresh = useCallback(async () => {
    if (!cartId) return;
    try {
      const response = await fetch(`/api/proxy/cart/${cartId}`);
      if (response.ok) setCart(await response.json());
    } catch {
      // A cart that cannot be read must not break the page it appears on.
    }
  }, [cartId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const setQuantity = useCallback(
    async (productId: number, quantity: number) => {
      if (!cartId) return;
      setBusy(true);
      try {
        const response = await fetch(`/api/proxy/cart/${cartId}`, {
          method: "PUT",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ product_id: productId, quantity }),
        });
        if (!response.ok) {
          toast("Could not update the cart.", "error");
          return;
        }
        setCart(await response.json());
        toast(quantity === 0 ? "Removed from cart." : "Cart updated.");
      } catch {
        toast("Could not reach the server.", "error");
      } finally {
        setBusy(false);
      }
    },
    [cartId, toast],
  );

  const checkout = useCallback(async () => {
    if (!cartId) return null;
    setBusy(true);
    try {
      const response = await fetch("/api/proxy/checkout", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ cart_id: cartId }),
      });
      const body = await response.json();
      if (!response.ok) {
        // 409 carries a message written for a customer -- "Not enough stock
        // for: X" -- so it is shown rather than replaced with a generic error.
        toast(body.detail ?? "Checkout failed.", "error");
        return null;
      }
      setCart(EMPTY);
      return body.order_id as number;
    } catch {
      toast("Could not reach the server.", "error");
      return null;
    } finally {
      setBusy(false);
    }
  }, [cartId, toast]);

  return (
    <CartContext.Provider value={{ cart, busy, setQuantity, refresh, checkout }}>
      {children}
    </CartContext.Provider>
  );
}
