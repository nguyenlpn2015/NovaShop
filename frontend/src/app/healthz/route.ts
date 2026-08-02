import { NextResponse } from "next/server";

/**
 * Liveness and readiness for the frontend container.
 *
 * A dedicated route rather than "/", which is what the probes used before.
 * Probing "/" means the liveness check renders the home page, which fetches the
 * catalogue -- so a slow or unreachable backend would restart every frontend
 * replica. A restart cannot fix a backend outage, and the restarts remove the
 * one thing still able to serve an error page.
 *
 * This answers from the Node process alone and asserts nothing about the
 * backend, deliberately.
 */
export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json({ status: "alive" });
}
