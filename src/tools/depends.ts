export type DependencyFactory<T> = () => T | Promise<T>;
export type DependencyOverrides = Map<DependencyFactory<any>, DependencyFactory<any>> | Record<string, DependencyFactory<any>>;

export class Depends<T> {
  dependency: DependencyFactory<T>;

  constructor(dependency: DependencyFactory<T>) {
    this.dependency = dependency;
  }

  async resolve(overrides?: DependencyOverrides): Promise<T> {
    let factory: DependencyFactory<T> = this.dependency;

    if (overrides instanceof Map) {
      const override = overrides.get(this.dependency as any);
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
