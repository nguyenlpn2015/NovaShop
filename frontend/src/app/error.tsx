"use client";

import Link from "next/link";

/**
 * Rendered when a server component throws -- most often because the backend is
 * unreachable. It says which layer failed rather than "something went wrong",
 * because the first question during an incident is where to look.
 */
export default function Error({ reset }: { error: Error; reset: () => void }) {
  return (
    <div className="card mx-auto max-w-lg p-10 text-center">
      <h1 className="text-lg font-medium">The catalogue is unavailable.</h1>
      <p className="mt-2 text-sm text-content-muted">
        The frontend is running; it could not reach the backend API. Readiness
        for each service is reported at <code>/ready</code>.
      </p>
      <div className="mt-5 flex justify-center gap-2">
        <button
          type="button"
          onClick={reset}
          className="rounded-lg bg-accent px-4 py-2 text-sm font-medium
                     text-accent-contrast hover:bg-accent-hover"
        >
          Try again
        </button>
        <Link
          href="/"
          className="rounded-lg border border-edge px-4 py-2 text-sm hover:border-accent"
        >
          Home
        </Link>
      </div>
    </div>
  );
}
