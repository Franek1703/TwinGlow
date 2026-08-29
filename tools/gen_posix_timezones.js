#!/usr/bin/env node
/*
 * Generates twin_glow/lib/core/utils/posix_timezones.dart.
 *
 * The device has no tzdata, so the app has to hand it a ready-made POSIX TZ rule
 * ("CET-1CEST,M3.5.0,M10.5.0/3") rather than an IANA name. Those rules are not
 * invented here: a TZif v2+ file ends with the rule as its footer, which is
 * exactly what the C library reads for dates past its transition table. So the
 * table below is transcribed from the system tzdata, not hand-written.
 *
 * Usage:  node tools/gen_posix_timezones.js [tzdataDir]
 * Default tzdataDir is /usr/share/zoneinfo.
 *
 * The generated file is committed, so a normal build does not depend on the
 * host's tzdata. Re-run this when tzdata ships new DST rules.
 */

const fs = require('fs');
const path = require('path');

const TZDATA_DIR = process.argv[2] || '/usr/share/zoneinfo';
const OUT = path.join(__dirname, '..', 'twin_glow', 'lib', 'core', 'utils', 'posix_timezones.dart');

// Region-less legacy aliases (Poland, Zulu) and the deprecated country groups
// resolve fine but would clutter a picker, so they stay in the map and out of
// the list. Etc/* is excluded too - plain "UTC" covers the only useful case.
const LEGACY_GROUPS = new Set(['Brazil', 'Canada', 'Chile', 'Etc', 'Mexico', 'US', 'SystemV']);

function collectZoneFiles(dir, prefix = '') {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    const name = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      out.push(...collectZoneFiles(full, name));
    } else if (entry.isFile()) {
      out.push({ name, full });
    }
  }
  return out;
}

/**
 * A TZif v2+ file is: v1 block, v2 block, then "\n" + POSIX rule + "\n" at EOF.
 * Returns null for v1-only files and for zones with no rule (a footer of "").
 */
function readPosixFooter(buf) {
  if (buf.length < 5 || buf.toString('ascii', 0, 4) !== 'TZif') return null;
  if (buf[4] === 0x00) return null; // version 1: no footer
  if (buf[buf.length - 1] !== 0x0a) return null;
  const start = buf.lastIndexOf(0x0a, buf.length - 2);
  if (start < 0) return null;
  const rule = buf.toString('ascii', start + 1, buf.length - 1).trim();
  return rule.length > 0 ? rule : null;
}

const zones = new Map();
for (const { name, full } of collectZoneFiles(TZDATA_DIR)) {
  const rule = readPosixFooter(fs.readFileSync(full));
  if (rule) zones.set(name, rule);
}

if (zones.size === 0) {
  console.error(`No zones found under ${TZDATA_DIR}`);
  process.exit(1);
}

let version = 'unknown';
try {
  version = fs.readFileSync(path.join(TZDATA_DIR, '+VERSION'), 'utf8').trim();
} catch { /* not present on every platform */ }

const names = [...zones.keys()].sort();
const pickable = names.filter((n) => n.includes('/') && !LEGACY_GROUPS.has(n.split('/')[0]));

const entries = names
  .map((n) => `  '${n}': '${zones.get(n).replace(/'/g, "\\'")}',`)
  .join('\n');
const pickableEntries = pickable.map((n) => `  '${n}',`).join('\n');

const dart = `// GENERATED FILE - do not edit by hand.
// Regenerate with: node tools/gen_posix_timezones.js
//
// tzdata version: ${version}
// ${zones.size} zones transcribed from the TZif footers under ${TZDATA_DIR}.

/// IANA zone name -> the POSIX TZ rule the firmware feeds to \`tzset()\`.
///
/// The device carries no tzdata, so the app resolves the rule and writes it to
/// the device document as \`tzPosix\`. Rules carry their own DST transitions, so
/// the device handles changeovers itself even if it never hears from the app
/// again.
const Map<String, String> kIanaToPosixTz = {
${entries}
};

/// Zone names to offer in a picker: canonical region/city names only, with the
/// deprecated country groups and region-less aliases filtered out. Those remain
/// resolvable through [kIanaToPosixTz] - they are just not worth showing.
const List<String> kPickableTimeZones = [
  'UTC',
${pickableEntries}
];

/// POSIX TZ rule for [iana], falling back to a fixed offset built from
/// [fallbackOffset] when the zone is not in the table.
///
/// The fallback is correct right now but carries no DST rules, so a device on
/// it drifts by an hour at the next changeover until the app corrects it. That
/// only happens for a zone newer than the generated table.
String posixTzFor(String iana, Duration fallbackOffset) {
  return kIanaToPosixTz[iana] ?? fixedOffsetTz(fallbackOffset);
}

/// Builds a POSIX rule for a plain UTC offset, e.g. \`UTC-2\` for UTC+02:00.
///
/// The sign is inverted on purpose: a POSIX offset is what you add to local
/// time to get UTC, which is the opposite of how offsets are usually written.
String fixedOffsetTz(Duration offset) {
  final minutes = offset.inMinutes;
  if (minutes == 0) return 'UTC0';
  final sign = minutes > 0 ? '-' : '+';
  final abs = minutes.abs();
  final hours = abs ~/ 60;
  final rem = abs % 60;
  if (rem == 0) return 'UTC\$sign\$hours';
  return 'UTC\$sign\$hours:\${rem.toString().padLeft(2, '0')}';
}
`;

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, dart);
console.log(`Wrote ${OUT}: ${zones.size} zones (${pickable.length} pickable), tzdata ${version}`);
