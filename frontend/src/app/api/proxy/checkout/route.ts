import { NextRequest, NextResponse } from "next/server";

import { apiSend } from "@/lib/api";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  const body = await request.json();
  // The status is passed through unchanged. A 409 from checkout carries a
  // message written for a customer -- "Not enough stock for: X" -- and
  // flattening it to 500 would lose both the message and the distinction
  // between a conflict and a fault.
  const result = await apiSend("POST", "/orders", body);
  return NextResponse.json(result.body, { status: result.status });
}
