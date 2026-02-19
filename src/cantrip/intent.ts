/**
 * An Intent is a natural-language instruction that an Entity executes.
 *
 * It is the "what" — the user's goal expressed as a string.
 * The Entity interprets the Intent through its Crystal (LLM),
 * using the Gates in its Circle to take actions in the world.
 *
 * Examples:
 *   "Summarize this document"
 *   "Find all TODO comments in the codebase"
 *   "Book a flight from SFO to JFK on March 15"
 */
export type Intent = string;
