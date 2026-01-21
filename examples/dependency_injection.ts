import { tool } from "../src/tools/decorator";
import { Depends } from "../src/tools/depends";

class Database {
  async execute(sql: string): Promise<string> {
    return `Executed: ${sql}`;
  }
}

function getDb(): Database {
  return new Database();
}

const query = tool(
  "Query database",
  async ({ sql }: { sql: string }, deps) => {
    const db = deps.db as Database;
    return db.execute(sql);
  },
  {
    name: "query",
    params: { sql: "string" },
    dependencies: { db: new Depends(getDb) },
  }
);

async function main() {
  const result = await query.execute({ sql: "SELECT 1" });
  console.log(result);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
