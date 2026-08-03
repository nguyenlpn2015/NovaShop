import react from "@vitejs/plugin-react";
import { resolve } from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  resolve: {
    // Mirrors the "@/*" path alias in tsconfig.json. Without it every import
    // in a test resolves differently from the same import in the application,
    // and the tests exercise a module graph the build never produces.
    alias: { "@": resolve(__dirname, "src") },
  },
  test: {
    environment: "jsdom",
    globals: true,
    include: ["src/**/*.test.{ts,tsx}"],
    coverage: {
      provider: "v8",
      // text for the CI log, json-summary so the workflow can publish one
      // number without parsing a table, lcov for any external viewer.
      reporter: ["text", "json-summary", "lcov"],
      reportsDirectory: "./coverage",
      include: ["src/**/*.{ts,tsx}"],
      exclude: [
        "src/**/*.test.{ts,tsx}",
        // Route files are exercised by the running application, not by unit
        // tests. Counting them would report a low number that says nothing
        // about the components the tests do cover.
        "src/app/**/layout.tsx",
        "src/app/**/page.tsx",
        "src/app/**/loading.tsx",
        "src/app/**/route.ts",
      ],
      // No thresholds. The number is published, not enforced -- a threshold on
      // a suite this size invites tests written to move a percentage rather
      // than to catch a defect.
    },
  },
});
