// A stand-in for the D1 binding over node:sqlite, so the real worker can be run
// without wrangler or a network: `node --no-warnings test/run.mjs`.
//
// D1 binds `?1`-style placeholders by position and allows reusing one, which
// node:sqlite refuses, so they are rewritten into plain `?` in order.

import { DatabaseSync } from "node:sqlite";

function normalise(sql, values) {
    if (!/\?\d/.test(sql)) return { sql, values };
    const ordered = [];
    const rewritten = sql.replace(/\?(\d+)/g, (_, index) => {
        ordered.push(values[Number(index) - 1]);
        return "?";
    });
    return { sql: rewritten, values: ordered };
}

function clean(value) {
    if (value === undefined) return null;
    if (typeof value === "boolean") return value ? 1 : 0;
    return value;
}

export class D1 {
    constructor(path = ":memory:") {
        this.db = new DatabaseSync(path);
    }

    exec(sql) {
        this.db.exec(sql);
    }

    prepare(sql) {
        const d1 = this;
        const statement = {
            values: [],
            bind(...values) {
                return { ...statement, values: values.map(clean) };
            },
            run() {
                const { sql: text, values } = normalise(sql, this.values);
                // D1 refuses more than 100 bound parameters per statement.
                if (values.length > 100) throw new Error(`D1_ERROR: too many SQL variables (${values.length})`);
                const trimmed = text.trim().toUpperCase();
                if (/\bRETURNING\b/i.test(text) || trimmed.startsWith("SELECT") || trimmed.startsWith("WITH")) {
                    return Promise.resolve({ results: d1.db.prepare(text).all(...values), success: true, meta: {} });
                }
                const info = d1.db.prepare(text).run(...values);
                return Promise.resolve({ results: [], success: true, meta: { changes: info.changes } });
            },
            all() {
                return this.run();
            },
            async first(column) {
                const result = await this.run();
                const row = result.results[0] ?? null;
                return column && row ? row[column] : row;
            }
        };
        return statement;
    }

    async batch(statements) {
        this.db.exec("BEGIN");
        try {
            const results = [];
            for (const statement of statements) results.push(await statement.run());
            this.db.exec("COMMIT");
            return results;
        } catch (error) {
            this.db.exec("ROLLBACK");
            throw error;
        }
    }

    plan(sql, values = []) {
        const { sql: text, values: ordered } = normalise(sql, values.map(clean));
        return this.db.prepare(`EXPLAIN QUERY PLAN ${text}`).all(...ordered).map((row) => row.detail);
    }
}
