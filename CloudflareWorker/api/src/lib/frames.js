// Picks the frames shown during one round.
//
// Curators tag approved images with a coarse difficulty tier (hard/medium/easy)
// rather than exact positions, because three buckets are far easier to judge
// than six ranks. Turning those buckets into an ordered set of six frames is
// what this file does.
//
// The rule is an even split across whichever tiers actually have images, and
// where a tier cannot fill its share, the shortfall moves to the tiers that
// can. No image is ever repeated inside a round — a short tier means other
// tiers contribute more, never that a frame appears twice.

const TIER_ORDER = ["hard", "medium", "easy"];

// Least-voted first: a frame the community barely engaged with tends to be the
// obscure one, and the iconic shots accumulate votes. This is a tendency the
// ordering leans on, not a promise about any individual image.
function byAscendingVote(a, b) {
    if (a.tmdb_vote_average !== b.tmdb_vote_average) return a.tmdb_vote_average - b.tmdb_vote_average;
    return a.tmdb_vote_count - b.tmdb_vote_count;
}

function shuffled(items) {
    const copy = [...items];
    for (let i = copy.length - 1; i > 0; i -= 1) {
        const j = Math.floor(Math.random() * (i + 1));
        [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy;
}

// Spreads `total` slots across the populated tiers, then repeatedly hands any
// shortfall to tiers that still have spare images, until either every slot is
// claimed or nothing has capacity left.
export function allocateSlots(available, total) {
    const populated = TIER_ORDER.filter((tier) => (available[tier] || 0) > 0);
    const allocation = { hard: 0, medium: 0, easy: 0 };
    if (populated.length === 0) return allocation;

    const base = Math.floor(total / populated.length);
    let remainder = total % populated.length;

    for (const tier of populated) {
        allocation[tier] = base + (remainder > 0 ? 1 : 0);
        if (remainder > 0) remainder -= 1;
    }

    // Move the overflow from tiers that are short onto tiers with room to spare.
    for (let pass = 0; pass < populated.length; pass += 1) {
        let deficit = 0;
        for (const tier of populated) {
            if (allocation[tier] > available[tier]) {
                deficit += allocation[tier] - available[tier];
                allocation[tier] = available[tier];
            }
        }
        if (deficit === 0) break;

        for (const tier of populated) {
            if (deficit === 0) break;
            const spare = available[tier] - allocation[tier];
            if (spare <= 0) continue;
            const taken = Math.min(spare, deficit);
            allocation[tier] += taken;
            deficit -= taken;
        }
        if (deficit > 0) break; // Every tier is exhausted; caller tops up elsewhere.
    }

    return allocation;
}

export function selectRoundFrames(images, frameCount = 6) {
    const approved = images.filter((image) => image.status === "approved");

    // An explicit rank is a curator overriding one exact position. Last write
    // wins on collisions, matching how the curator UI assigns them.
    const pinned = new Map();
    for (const image of approved) {
        const rank = image.difficulty_rank;
        if (rank && rank >= 1 && rank <= frameCount && !pinned.has(rank)) pinned.set(rank, image);
    }

    const pinnedIds = new Set([...pinned.values()].map((image) => image.id));
    const remaining = approved.filter((image) => !pinnedIds.has(image.id));
    const slotsToFill = frameCount - pinned.size;

    const buckets = { hard: [], medium: [], easy: [] };
    const untagged = [];
    for (const image of remaining) {
        if (TIER_ORDER.includes(image.difficulty_tier)) buckets[image.difficulty_tier].push(image);
        else untagged.push(image);
    }

    const allocation = allocateSlots(
        { hard: buckets.hard.length, medium: buckets.medium.length, easy: buckets.easy.length },
        slotsToFill
    );

    const chosen = [];
    for (const tier of TIER_ORDER) {
        const count = allocation[tier];
        if (count <= 0) continue;
        // Random subset from a tier with surplus keeps replays varied; the
        // vote sort then fixes a stable order within the tier.
        const picked = shuffled(buckets[tier]).slice(0, count).sort(byAscendingVote);
        chosen.push(...picked);
    }

    // Nothing is tagged at all, or the tagged images could not cover six slots.
    // Untagged images fall back to the automatic vote ordering.
    if (chosen.length < slotsToFill) {
        chosen.push(...untagged.sort(byAscendingVote).slice(0, slotsToFill - chosen.length));
    }

    const result = [];
    let cursor = 0;
    for (let position = 1; position <= frameCount; position += 1) {
        if (pinned.has(position)) result.push(pinned.get(position));
        else if (cursor < chosen.length) result.push(chosen[cursor++]);
    }

    return result;
}

// Six approved images is the eligibility bar for the six-frame mode. It counts
// raw images, deliberately not visual variety: a film shot entirely at night
// legitimately has six near-identical frames and is still playable.
export function hasEnoughFrames(images, frameCount = 6) {
    return images.filter((image) => image.status === "approved").length >= frameCount;
}
