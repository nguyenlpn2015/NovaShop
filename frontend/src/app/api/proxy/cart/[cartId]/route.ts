import { NextRequest, NextResponse } from "next/server";

import { apiGet, apiSend } from "@/lib/api";

/**
 * Cart reads and writes, proxied.
 *
 * The cart is the one thing the browser must change directly -- a server
 * component cannot respond to a click. Proxying keeps the rule the rest of the
 * site follows: the browser never learns a backend address, and there is no
 * CORS configuration to get wrong.
 */
export const dynamic = "force-dynamic";

function clean(cartId: string): string | null {
  return /^[A-Za-z0-9_-]{8,64}$/.test(cartId) ? cartId : null;
}

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ cartId: string }> },
) {
  const { cartId } = await params;
  const id = clean(cartId);
  if (!id) return NextResponse.json({ detail: "Bad cart id." }, { status: 400 });

  try {
    return NextResponse.json(await apiGet(`/cart/${id}`));
  } catch {
    return NextResponse.json({ detail: "Unavailable." }, { status: 502 });
  }
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ cartId: string }> },
) {
  const { cartId } = await params;
  const id = clean(cartId);
  if (!id) return NextResponse.json({ detail: "Bad cart id." }, { status: 400 });

  const body = await request.json();
  const result = await apiSend("PUT", `/cart/${id}/items`, body);
  return NextResponse.json(result.body, { status: result.status });
}
