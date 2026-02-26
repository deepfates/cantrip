export type ObserveStartEvent = {
  name: string;
  args: unknown[];
  timestamp: number;
  debug: boolean;
};

export type ObserveEndEvent = {
  name: string;
  args: unknown[];
  result: unknown;
  timestamp: number;
  duration_ms: number;
  debug: boolean;
};

export type ObserveErrorEvent = {
  name: string;
  args: unknown[];
  error: unknown;
  timestamp: number;
  duration_ms: number;
  debug: boolean;
};

export type ObserveOptions = {
  name?: string;
  debug?: boolean;
};

export type Observer = {
  enabled?: boolean;
  onStart?: (event: ObserveStartEvent) => void | Promise<void>;
  onEnd?: (event: ObserveEndEvent) => void | Promise<void>;
  onError?: (event: ObserveErrorEvent) => void | Promise<void>;
};

let currentObserver: Observer | null = null;

export const Laminar = {
  setObserver(observer: Observer | null): void {
    currentObserver = observer;
  },
  getObserver(): Observer | null {
    return currentObserver;
  },
  clearObserver(): void {
    currentObserver = null;
  },
};

export function setObserver(observer: Observer | null): void {
  Laminar.setObserver(observer);
}

export function getObserver(): Observer | null {
  return Laminar.getObserver();
}

export function clearObserver(): void {
  Laminar.clearObserver();
}

export function observe<T extends (...args: any[]) => any>(
  fn: T,
  options?: ObserveOptions,
): T {
  return wrapObserved(fn, { ...options, debug: options?.debug ?? false });
}

export function observe_debug<T extends (...args: any[]) => any>(
  fn: T,
  options?: Omit<ObserveOptions, "debug">,
): T {
  return wrapObserved(fn, { ...options, debug: true });
}

function wrapObserved<T extends (...args: any[]) => any>(
  fn: T,
  options: ObserveOptions,
): T {
  const name = options.name ?? fn.name ?? "anonymous";
  const debug = options.debug ?? false;

  const wrapped = function (...args: Parameters<T>): ReturnType<T> {
    const observer = currentObserver;
    if (!observer || observer.enabled === false) {
      return fn(...args);
    }

    const start = Date.now();
    safeCall(observer.onStart, {
      name,
      args,
      timestamp: start,
      debug,
    });

    try {
      const result = fn(...args);
      if (result instanceof Promise) {
        return result
          .then((value) => {
            safeCall(observer.onEnd, {
              name,
              args,
              result: value,
              timestamp: Date.now(),
              duration_ms: Date.now() - start,
              debug,
            });
            return value;
          })
          .catch((error) => {
            safeCall(observer.onError, {
              name,
              args,
              error,
              timestamp: Date.now(),
              duration_ms: Date.now() - start,
              debug,
            });
            throw error;
          }) as ReturnType<T>;
      }

      safeCall(observer.onEnd, {
        name,
        args,
        result,
        timestamp: Date.now(),
        duration_ms: Date.now() - start,
        debug,
      });
      return result;
    } catch (error) {
      safeCall(observer.onError, {
        name,
        args,
        error,
        timestamp: Date.now(),
        duration_ms: Date.now() - start,
        debug,
      });
      throw error;
    }
  };

  return wrapped as T;
}

function safeCall<TEvent>(
  handler: ((event: TEvent) => void | Promise<void>) | undefined,
  event: TEvent,
): void {
  if (!handler) return;
  try {
    void handler(event);
  } catch {
    // Observability should never break the caller.
  }
}
