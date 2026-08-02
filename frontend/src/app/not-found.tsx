import Link from "next/link";

export default function NotFound() {
  return (
    <div className="card mx-auto max-w-lg p-10 text-center">
      <p className="text-5xl font-semibold text-content-faint">404</p>
      <h1 className="mt-3 text-lg font-medium">That page does not exist.</h1>
      <Link
        href="/products"
        className="mt-4 inline-block rounded-lg bg-accent px-4 py-2 text-sm
                   font-medium text-accent-contrast hover:bg-accent-hover"
      >
        Browse products
      </Link>
    </div>
  );
}
