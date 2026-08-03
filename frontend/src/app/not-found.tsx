import Link from "next/link";

export default function NotFound() {
  return (
    <div className="card mx-auto max-w-lg p-12 text-center">
      <p className="text-6xl font-semibold tracking-display text-content-faint/50">
        404
      </p>
      <h1 className="mt-4 text-xl font-semibold tracking-display">
        That page does not exist.
      </h1>
      <p className="mt-2 text-sm text-content-muted">
        The link may be stale, or the product may have left the catalogue.
      </p>
      <div className="mt-7 flex justify-center gap-2.5">
        <Link href="/products" className="btn-primary">
          Browse products
        </Link>
        <Link href="/" className="btn-secondary">
          Home
        </Link>
      </div>
    </div>
  );
}
