export type DependencyFactory<T> = () => T | Promise<T>;
export type DependencyOverrides =
  | Map<Depends<any>, DependencyFactory<any>>
  | Map<DependencyFactory<any>, DependencyFactory<any>>
  | Record<string, DependencyFactory<any>>;

export class Depends<T> {
  dependency: DependencyFactory<T>;

  constructor(dependency: DependencyFactory<T>) {
    this.dependency = dependency;
  }

  async resolve(overrides?: DependencyOverrides | null): Promise<T> {
    let factory: DependencyFactory<T> = this.dependency;

    if (overrides instanceof Map) {
      // Check if map key is Depends instance or factory function
      const overrideByInstance = overrides.get(this as any);
      const overrideByFactory = overrides.get(this.dependency as any);
      const override = overrideByInstance ?? overrideByFactory;
      if (override) factory = override as DependencyFactory<T>;
    } else if (overrides && typeof overrides === "object") {
      const override = (overrides as Record<string, DependencyFactory<any>>)[
        this.dependency.name
      ];
      if (override) factory = override as DependencyFactory<T>;
    }

    const result = factory();
    return result instanceof Promise ? await result : result;
  }
}
