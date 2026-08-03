"use client";

import Link from "next/link";

/**
 * Rendered when a server component throws -- most often because the backend is
 * unreachable. It says which layer failed rather than "something went wrong",
 * because the first question during an incident is where to look.
 */
export default function Error({ reset }: { error: Error; reset: () => void }) {
  return (
    <div className="card mx-auto max-w-lg p-12 text-center">
      <span
        aria-hidden
        className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl
                   bg-caution/10 text-caution ring-1 ring-caution/20"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={1.6}
          strokeLinecap="round"
          strokeLinejoin="round"
          className="h-6 w-6"
        >
          <path d="M12 9v4m0 4h.01M10.3 3.9 2.4 17.4A2 2 0 0 0 4.1 20.5h15.8a2 2 0 0 0 1.7-3.1L13.7 3.9a2 2 0 0 0-3.4 0Z" />
        </svg>
      </span>

      <h1 className="mt-5 text-xl font-semibold tracking-display">
        The catalogue is unavailable.
      </h1>
      <p className="mt-3 text-sm leading-relaxed text-content-muted">
        The frontend is running; it could not reach the backend API. Readiness
        for each service is reported at{" "}
        <code className="font-mono text-content">/ready</code>.
      </p>
      <div className="mt-7 flex justify-center gap-2.5">
        <button type="button" onClick={reset} className="btn-primary">
          Try again
        </button>
        <Link href="/" className="btn-secondary">
          Home
        </Link>
      </div>
    </div>
  );
}
