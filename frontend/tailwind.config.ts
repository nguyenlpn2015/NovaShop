import type { Config } from "tailwindcss";

const config: Config = {
  // Class-based rather than media-based, so the toggle can override the
  // operating system preference. Media-only dark mode means a user who prefers
  // light at night has no way to say so.
  darkMode: "class",
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // Named by role, not by hue. A palette named "blue" is a palette you
        // cannot restyle without touching every file that uses it.
        surface: {
          DEFAULT: "rgb(var(--surface) / <alpha-value>)",
          raised: "rgb(var(--surface-raised) / <alpha-value>)",
          sunken: "rgb(var(--surface-sunken) / <alpha-value>)",
        },
        content: {
          DEFAULT: "rgb(var(--content) / <alpha-value>)",
          muted: "rgb(var(--content-muted) / <alpha-value>)",
          faint: "rgb(var(--content-faint) / <alpha-value>)",
        },
        accent: {
          DEFAULT: "rgb(var(--accent) / <alpha-value>)",
          hover: "rgb(var(--accent-hover) / <alpha-value>)",
          alt: "rgb(var(--accent-alt) / <alpha-value>)",
          contrast: "rgb(var(--accent-contrast) / <alpha-value>)",
        },
        edge: "rgb(var(--edge) / <alpha-value>)",
        positive: "rgb(var(--positive) / <alpha-value>)",
        caution: "rgb(var(--caution) / <alpha-value>)",
      },
      borderRadius: {
        card: "1.125rem",
      },
      // Two shadows, each with a job. `lift` is geometry -- something moved
      // toward the reader. `glow` is emphasis, and it is tinted with the accent
      // so it reads as the same system in both themes rather than as a grey
      // blur on dark and a black blur on light.
      boxShadow: {
        lift: "0 1px 2px rgb(0 0 0 / 0.16), 0 18px 40px -22px rgb(0 0 0 / 0.45)",
        glow: "0 8px 30px -10px rgb(var(--accent) / 0.55)",
      },
      letterSpacing: {
        display: "-0.025em",
      },
      keyframes: {
        "fade-up": {
          from: { opacity: "0", transform: "translateY(6px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
        shimmer: {
          "100%": { transform: "translateX(100%)" },
        },
        // The slow wander behind the hero. 18s and a tiny translation, because
        // anything faster or larger becomes the thing you look at instead of
        // the product.
        drift: {
          "0%, 100%": { transform: "translate3d(0, 0, 0) scale(1)" },
          "50%": { transform: "translate3d(2%, -3%, 0) scale(1.08)" },
        },
      },
      animation: {
        "fade-up": "fade-up 220ms ease-out both",
        shimmer: "shimmer 1.6s infinite",
        drift: "drift 18s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
