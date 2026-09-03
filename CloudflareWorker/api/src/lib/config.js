// Runtime knobs that live in the database so they can change without a deploy.

const DEFAULTS = {
    curationGateEnabled: false,
    dailyFreeAttempts: 6,
    attemptsPerCorrectStreak: 1,
    curationRewardAttempts: 1,
    playlistCompletionReward: 3,
    autoHideReportWeight: 3,
    catalogCacheTTLSeconds: 86400,
    // Rounds an account must have played before its curation vote carries any
    // weight. Set to 0 to let brand new accounts vote at full strength.
    voteWeightMinRounds: 5,
    // Approved frames after which a title stops being offered for curation.
    // Not a playability gate — six approved frames already make a title
    // playable. This is only the point where asking humans to look at it again
    // stops being worth their time.
    targetApprovedFrames: 12,
    onboardingMediaKey: ""
};

function coerce(key, raw) {
    const fallback = DEFAULTS[key];
    if (typeof fallback === "boolean") return raw === "true";
    if (typeof fallback === "number") {
        const parsed = Number(raw);
        return Number.isFinite(parsed) ? parsed : fallback;
    }
    return raw;
}

export async function readConfig(env) {
    const rows = await env.DB.prepare("SELECT key, value FROM app_config").all();
    const config = { ...DEFAULTS };
    for (const row of rows.results) {
        if (row.key in DEFAULTS) config[row.key] = coerce(row.key, row.value);
    }
    return config;
}

export async function writeConfig(env, updates) {
    const statements = [];
    for (const [key, value] of Object.entries(updates)) {
        if (!(key in DEFAULTS)) continue;
        statements.push(
            env.DB.prepare("INSERT INTO app_config (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value")
                .bind(key, String(value))
        );
    }
    if (statements.length) await env.DB.batch(statements);
    return readConfig(env);
}

export { DEFAULTS as CONFIG_DEFAULTS };
