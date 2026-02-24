from __future__ import annotations

import json
import sqlite3
from dataclasses import asdict
from pathlib import Path
from typing import Any

from cantrip.errors import CantripError
from cantrip.models import Thread, Turn


class LoomStore:
    def append_turn(self, thread: Thread, turn: Turn) -> None:
        raise NotImplementedError

    def delete_turn(self, _idx: int) -> None:
        raise CantripError("loom is append-only")

    def list_threads(self) -> list[Thread]:
        raise NotImplementedError

    def get_thread(self, thread_id: str) -> Thread | None:
        raise NotImplementedError


class InMemoryLoomStore(LoomStore):
    def __init__(self) -> None:
        self.threads: list[Thread] = []
        self.turns: list[Turn] = []

    def append_turn(self, thread: Thread, turn: Turn) -> None:
        thread.turns.append(turn)
        self.turns.append(turn)

    def list_threads(self) -> list[Thread]:
        return list(self.threads)

    def get_thread(self, thread_id: str) -> Thread | None:
        for t in self.threads:
            if t.id == thread_id:
                return t
        return None


class SQLiteLoomStore(LoomStore):
    def __init__(self, db_path: str | Path) -> None:
        self.db_path = str(db_path)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self._init_schema()
        self.threads: list[Thread] = []
        self.turns: list[Turn] = []

    def _init_schema(self) -> None:
        self.conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS threads (
              id TEXT PRIMARY KEY,
              entity_id TEXT NOT NULL,
              intent TEXT NOT NULL,
              call_json TEXT NOT NULL,
              result_json TEXT,
              terminated INTEGER NOT NULL DEFAULT 0,
              truncated INTEGER NOT NULL DEFAULT 0,
              usage_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS turns (
              id TEXT PRIMARY KEY,
              thread_id TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              sequence INTEGER NOT NULL,
              parent_id TEXT,
              utterance_json TEXT NOT NULL,
              observation_json TEXT NOT NULL,
              terminated INTEGER NOT NULL DEFAULT 0,
              truncated INTEGER NOT NULL DEFAULT 0,
              reward REAL,
              metadata_json TEXT NOT NULL,
              FOREIGN KEY(thread_id) REFERENCES threads(id)
            );
            """
        )
        self.conn.commit()

    def register_thread(self, thread: Thread) -> None:
        self.threads.append(thread)
        self.conn.execute(
            """
            INSERT INTO threads(id, entity_id, intent, call_json, result_json, terminated, truncated, usage_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                thread.id,
                thread.entity_id,
                thread.intent,
                json.dumps(asdict(thread.call)),
                json.dumps(thread.result),
                int(thread.terminated),
                int(thread.truncated),
                json.dumps(thread.cumulative_usage),
            ),
        )
        self.conn.commit()

    def update_thread(self, thread: Thread) -> None:
        self.conn.execute(
            """
            UPDATE threads
            SET result_json=?, terminated=?, truncated=?, usage_json=?
            WHERE id=?
            """,
            (
                json.dumps(thread.result),
                int(thread.terminated),
                int(thread.truncated),
                json.dumps(thread.cumulative_usage),
                thread.id,
            ),
        )
        self.conn.commit()

    def append_turn(self, thread: Thread, turn: Turn) -> None:
        thread.turns.append(turn)
        self.turns.append(turn)
        obs_json = json.dumps([asdict(r) for r in turn.observation])
        self.conn.execute(
            """
            INSERT INTO turns(id, thread_id, entity_id, sequence, parent_id, utterance_json,
                              observation_json, terminated, truncated, reward, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                turn.id,
                thread.id,
                turn.entity_id,
                turn.sequence,
                turn.parent_id,
                json.dumps(turn.utterance),
                obs_json,
                int(turn.terminated),
                int(turn.truncated),
                turn.reward,
                json.dumps(turn.metadata),
            ),
        )
        self.conn.commit()

    def list_threads(self) -> list[Thread]:
        return list(self.threads)

    def get_thread(self, thread_id: str) -> Thread | None:
        for t in self.threads:
            if t.id == thread_id:
                return t
        row = self.conn.execute(
            "SELECT id, entity_id, intent, call_json, result_json, terminated, truncated, usage_json FROM threads WHERE id=?",
            (thread_id,),
        ).fetchone()
        if not row:
            return None
        from cantrip.models import Call

        call_payload = json.loads(row[3])
        call = Call(**call_payload)
        thread = Thread(
            id=row[0],
            entity_id=row[1],
            intent=row[2],
            call=call,
            result=json.loads(row[4]) if row[4] is not None else None,
            terminated=bool(row[5]),
            truncated=bool(row[6]),
            cumulative_usage=json.loads(row[7]),
        )
        return thread


class Loom:
    def __init__(self, store: LoomStore | None = None) -> None:
        self.store = store or InMemoryLoomStore()

    @property
    def threads(self):
        return self.store.threads

    @property
    def turns(self):
        return self.store.turns

    def register_thread(self, thread: Thread) -> None:
        if hasattr(self.store, "register_thread"):
            self.store.register_thread(thread)
        else:
            self.store.threads.append(thread)

    def update_thread(self, thread: Thread) -> None:
        if hasattr(self.store, "update_thread"):
            self.store.update_thread(thread)

    def append_turn(self, thread: Thread, turn: Turn) -> None:
        self.store.append_turn(thread, turn)

    def delete_turn(self, idx: int) -> None:
        self.store.delete_turn(idx)

    def annotate_reward(self, thread: Thread, index: int, reward: float) -> None:
        thread.turns[index].reward = reward

    def extract_thread(self, thread: Thread) -> list[dict[str, Any]]:
        return [
            {
                "utterance": t.utterance,
                "observation": [asdict(r) for r in t.observation],
                "terminated": t.terminated,
                "truncated": t.truncated,
            }
            for t in thread.turns
        ]

    def list_threads(self) -> list[Thread]:
        return self.store.list_threads()

    def get_thread(self, thread_id: str) -> Thread | None:
        return self.store.get_thread(thread_id)
