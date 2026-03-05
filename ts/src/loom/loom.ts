/**
 * The Loom — an append-only tree of Turn records.
 * See SPEC.md §6.2–§6.6.
 *
 * LOOM-3: The loom is append-only. Turns MUST NOT be deleted or modified
 *         after creation. Reward annotation is the exception.
 */

import { promises as fs } from "fs";
import type { Turn } from "./turn";

/** Storage backend interface. */
export interface LoomStorage {
  append(turn: Turn): Promise<void>;
  getAll(): Promise<Turn[]>;
}

/** In-memory storage — used for tests and ephemeral runs. */
export class MemoryStorage implements LoomStorage {
  private turns: Turn[] = [];

  async append(turn: Turn): Promise<void> {
    this.turns.push(turn);
  }

  async getAll(): Promise<Turn[]> {
    return [...this.turns];
  }
}

/**
 * JSONL file storage — the reference storage format.
 * One JSON object per line, one turn per line, appended chronologically.
 */
export class JsonlStorage implements LoomStorage {
  constructor(private filePath: string) {}

  async append(turn: Turn): Promise<void> {
    const line = JSON.stringify(turn) + "\n";
    await fs.appendFile(this.filePath, line, "utf-8");
  }

  async getAll(): Promise<Turn[]> {
    let content: string;
    try {
      content = await fs.readFile(this.filePath, "utf-8");
    } catch (err: any) {
      if (err.code === "ENOENT") return [];
      throw err;
    }
    const lines = content.split("\n").filter((l) => l.trim().length > 0);
    return lines.map((line) => JSON.parse(line) as Turn);
  }
}

/**
 * The Loom: an append-only tree of turns.
 *
 * Turns form a tree via parent_id pointers. A thread is any root-to-leaf
 * path through the tree. Multiple threads can share turns via forking.
 */
export class Loom {
  private turnMap = new Map<string, Turn>();
  private childMap = new Map<string, string[]>(); // parent_id -> child ids
  private rootIds: string[] = [];

  constructor(private storage: LoomStorage) {}

  /** Load all turns from storage into the in-memory index. */
  async load(): Promise<void> {
    const turns = await this.storage.getAll();
    for (const turn of turns) {
      this.indexTurn(turn);
    }
  }

  /**
   * Append a turn to the loom.
   * LOOM-1: Every turn MUST be recorded before the next turn begins.
   */
  async append(turn: Turn): Promise<void> {
    if (this.turnMap.has(turn.id)) {
      throw new Error(`Turn ${turn.id} already exists in the loom`);
    }
    await this.storage.append(turn);
    this.indexTurn(turn);
  }

  /** Retrieve a turn by ID. */
  getTurn(id: string): Turn | undefined {
    return this.turnMap.get(id);
  }

  /** Get direct children of a turn. */
  getChildren(turnId: string): Turn[] {
    const childIds = this.childMap.get(turnId) ?? [];
    return childIds.map((id) => this.turnMap.get(id)!);
  }

  /** Get all root turns (those with parent_id === null). */
  getRoots(): Turn[] {
    return this.rootIds.map((id) => this.turnMap.get(id)!);
  }

  /**
   * Walk from a leaf turn to the root, returning the full thread.
   * LOOM-10: The loom MUST support extracting any root-to-leaf path.
   *
   * Returns turns in root-to-leaf order.
   */
  getThread(leafId: string): Turn[] {
    const path: Turn[] = [];
    let current = this.turnMap.get(leafId);
    if (!current) {
      throw new Error(`Turn ${leafId} not found in loom`);
    }

    while (current) {
      path.push(current);
      if (current.parent_id === null) break;
      current = this.turnMap.get(current.parent_id);
      if (!current) {
        throw new Error(`Broken parent chain: parent not found`);
      }
    }

    path.reverse(); // root-to-leaf order
    return path;
  }

  /**
   * Get all leaf turns (turns with no children).
   * Useful for finding all active/terminal threads.
   */
  getLeaves(): Turn[] {
    const leaves: Turn[] = [];
    for (const turn of this.turnMap.values()) {
      const children = this.childMap.get(turn.id);
      if (!children || children.length === 0) {
        leaves.push(turn);
      }
    }
    return leaves;
  }

  /**
   * Fork from a given turn — the next turn appended with this
   * turn as parent will create a new branch.
   * LOOM-4: Forking from turn N produces a new entity whose initial
   *         context is the path from root to turn N.
   *
   * Returns the fork-point turn (for the caller to use as parent_id).
   */
  fork(turnId: string): Turn {
    const turn = this.turnMap.get(turnId);
    if (!turn) {
      throw new Error(`Cannot fork: turn ${turnId} not found`);
    }
    return turn;
  }

  /**
   * Assign or update the reward on a turn.
   * LOOM-3 exception: reward MAY be assigned or updated after creation.
   */
  async setReward(turnId: string, reward: number): Promise<void> {
    const turn = this.turnMap.get(turnId);
    if (!turn) {
      throw new Error(`Turn ${turnId} not found`);
    }
    turn.reward = reward;
    // Note: JSONL is append-only, so reward updates are in-memory only.
    // A full implementation would write a reward-annotation record.
  }

  /** Get total number of turns in the loom. */
  get size(): number {
    return this.turnMap.size;
  }

  /** Index a turn into the in-memory maps. */
  private indexTurn(turn: Turn): void {
    this.turnMap.set(turn.id, turn);
    if (turn.parent_id === null) {
      this.rootIds.push(turn.id);
    } else {
      const siblings = this.childMap.get(turn.parent_id) ?? [];
      siblings.push(turn.id);
      this.childMap.set(turn.parent_id, siblings);
    }
  }
}
