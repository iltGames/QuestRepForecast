import { createHash } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, rmdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { zstdDecompressSync } from 'node:zlib';

const archive = process.argv[2];
if (!archive) throw new Error('Pass the path to forever-db-2026.11.2.sqlite.zst.');

const input = readFileSync(archive);
const checksum = 'f66b358c55552f385aefd5a9d01aefb1c2254bd0d4147fc1cdf10c1befa9d767';
if (createHash('sha256').update(input).digest('hex') !== checksum) {
    throw new Error('The input does not match the Polestar forever-db 2026.11.2 release.');
}

const cloth = [2589, 2592, 2996, 2997, 4305, 4306, 4338, 4339, 14047, 14048, 14256, 14342];
const additionalClothQuests = [99191, 99192, 99193, 99194, 99196, 99197, 99198, 99199];
const temp = mkdtempSync(join(tmpdir(), 'quest-rep-data-'));
const sqlite = join(temp, 'forever-db.sqlite');

try {
    writeFileSync(sqlite, zstdDecompressSync(input));
    const db = new DatabaseSync(sqlite, { readOnly: true });
    try {
        const clothQuests = db.prepare(`
            SELECT DISTINCT quest FROM quest_objective
            WHERE kind = 'item' AND target IN (${cloth.map(() => '?').join(', ')})
        `).all(...cloth).map(row => row.quest);
        const excluded = new Set([...clothQuests, ...additionalClothQuests]);
        const turnIns = db.prepare(`
            SELECT q.id, q.min_level, q.repeatable,
                (SELECT group_concat(r.id) FROM quest_reward r
                    WHERE r.quest = q.id AND r.kind = 'rep' AND r.count > 0) AS factions,
                (SELECT group_concat(o.target || ':' || o.count) FROM quest_objective o
                    WHERE o.quest = q.id) AS items
            FROM quest q
            WHERE EXISTS (SELECT 1 FROM quest_reward r WHERE r.quest = q.id AND r.kind = 'rep' AND r.count > 0)
                AND EXISTS (SELECT 1 FROM quest_objective o WHERE o.quest = q.id)
                AND NOT EXISTS (SELECT 1 FROM quest_objective o WHERE o.quest = q.id
                    AND (o.kind <> 'item' OR o.count IS NULL OR o.count < 1 OR o.target IS NULL))
            ORDER BY q.id
        `).all().filter(row => !excluded.has(row.id));

        const lines = [
            'local _, addon = ...',
            '',
            '-- Item quantities and candidate factions from Polestar forever-db 2026.11.2.',
            '-- Reward amounts and quest eligibility come from Questie at runtime.',
            '-- Each entry contains the minimum level, repeatable flag, factions, and required items.',
            'addon.turnIns = {',
        ];
        for (const turnIn of turnIns) {
            const factions = turnIn.factions.split(',').map(Number).sort((left, right) => left - right);
            const items = new Map();
            for (const pair of turnIn.items.split(',')) {
                const [id, quantity] = pair.split(':').map(Number);
                items.set(id, (items.get(id) ?? 0) + quantity);
            }
            const requirements = [...items].sort(([left], [right]) => left - right)
                .map(([id, quantity]) => `[${id}] = ${quantity}`).join(', ');
            lines.push(`    [${turnIn.id}] = { ${turnIn.min_level ?? 0}, ${Boolean(turnIn.repeatable)}, { ${factions.join(', ')} }, { ${requirements} } },`);
        }
        lines.push('}', '', 'addon.clothItems = {');
        for (const id of cloth) lines.push(`    [${id}] = true,`);
        lines.push('}', '', 'addon.clothQuests = {');
        for (const id of [...excluded].sort((left, right) => left - right)) lines.push(`    [${id}] = true,`);
        lines.push('}', '');
        writeFileSync(new URL('../TurnInData.lua', import.meta.url), lines.join('\n'));
        console.log(`Generated ${turnIns.length} turn-ins and ${excluded.size} cloth quest exclusions.`);
    } finally {
        db.close();
    }
} finally {
    rmSync(sqlite, { force: true });
    rmdirSync(temp);
}
