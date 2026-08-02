"use client";

import { createContext, useCallback, useContext, useState, type ReactNode } from "react";

type Tone = "success" | "error";
type Toast = { id: number; message: string; tone: Tone };

const ToastContext = createContext<(message: string, tone?: Tone) => void>(() => {});

export function useToast() {
  return useContext(ToastContext);
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const push = useCallback((message: string, tone: Tone = "success") => {
    // Date.now() would collide when two toasts land in the same millisecond,
    // and React would then render two nodes with the same key.
    const id = Math.random();
    setToasts((current) => [...current, { id, message, tone }]);
    setTimeout(
      () => setToasts((current) => current.filter((toast) => toast.id !== id)),
      3200,
    );
  }, []);

  return (
    <ToastContext.Provider value={push}>
      {children}
      <div
        // aria-live so a screen reader announces the toast. Without it the
        // confirmation exists only for people who can see the corner of the
        // screen they were not looking at.
        aria-live="polite"
        className="pointer-events-none fixed bottom-4 right-4 z-[60] flex w-full
                   max-w-xs flex-col gap-2"
      >
        {toasts.map((toast) => (
          <div
            key={toast.id}
            className={`animate-fade-up rounded-lg px-4 py-3 text-sm shadow-lg
                        ring-1 backdrop-blur ${
                          toast.tone === "error"
                            ? "bg-surface-raised text-caution ring-caution/30"
                            : "bg-surface-raised text-content ring-edge"
                        }`}
          >
            {toast.message}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}
