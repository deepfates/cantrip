export const Laminar = null;

export function observe<T extends (...args: any[]) => any>(fn: T): T {
  return fn;
}

export function observe_debug<T extends (...args: any[]) => any>(fn: T): T {
  return fn;
}
