import type { Call, CallHyperparameters } from "./call";

/**
 * Identity is the entity's immutable instruction and generation profile.
 * Kept as an alias to `Call` for backwards compatibility during v0.2.0 cutover.
 */
export type Identity = Call;
export type IdentityHyperparameters = CallHyperparameters;

