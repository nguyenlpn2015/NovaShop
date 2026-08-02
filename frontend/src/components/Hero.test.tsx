import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { Hero } from "@/components/Hero";

// jsdom has no matchMedia. The component reads it to honour reduced motion, so
// without this every test throws before it asserts anything.
/**
 * Advance the fake clock inside act().
 *
 * Without this the interval callback runs but React never flushes the state
 * update, so nothing re-renders. The "advances on its own" assertion then fails
 * -- and, worse, the two assertions that expect *no* change passed for entirely
 * the wrong reason. A test that cannot fail is not a test.
 */
function tick(ms: number) {
  act(() => {
    vi.advanceTimersByTime(ms);
  });
}

function stubMatchMedia(reducedMotion: boolean) {
  vi.stubGlobal(
    "matchMedia",
    vi.fn().mockImplementation((query: string) => ({
      matches: reducedMotion && query.includes("reduce"),
      media: query,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  );
}

describe("Hero", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    stubMatchMedia(false);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("advances on its own", () => {
    render(<Hero />);
    const first = screen.getByRole("heading", { level: 1 }).textContent;

    tick(7100);

    expect(screen.getByRole("heading", { level: 1 }).textContent).not.toBe(first);
  });

  it("stops advancing when the pointer is over it", () => {
    // Otherwise the slide can change mid-sentence while someone is reading it.
    render(<Hero />);
    const region = screen.getByRole("region", { name: /featured/i });
    const first = screen.getByRole("heading", { level: 1 }).textContent;

    fireEvent.mouseEnter(region);
    tick(21000);

    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe(first);
  });

  it("does not auto-advance when the reader prefers reduced motion", () => {
    // An automatic carousel is precisely the movement that setting exists to
    // stop, and ignoring it is the most common way a carousel fails someone.
    vi.unstubAllGlobals();
    stubMatchMedia(true);

    render(<Hero />);
    const first = screen.getByRole("heading", { level: 1 }).textContent;

    tick(30000);

    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe(first);
  });

  it("lets a keyboard move between slides", () => {
    render(<Hero />);
    const region = screen.getByRole("region", { name: /featured/i });
    const first = screen.getByRole("heading", { level: 1 }).textContent;

    fireEvent.keyDown(region, { key: "ArrowRight" });

    expect(screen.getByRole("heading", { level: 1 }).textContent).not.toBe(first);
  });

  it("gives every dot an accessible name", () => {
    // "Slide 2" tells a screen-reader user nothing about where they are going.
    render(<Hero />);
    const dots = screen.getAllByRole("button", { name: /show slide/i });
    expect(dots.length).toBeGreaterThan(1);
    expect(dots[0].getAttribute("aria-label")).toMatch(/show slide 1: .+/i);
  });
});
