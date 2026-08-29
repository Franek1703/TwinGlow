#!/usr/bin/env node
/*
 * Migrate Firestore `assets` documents from SPARSE_I16_RGB888 to SPARSE_PACKED_V1.
 *
 * WHY
 * ---
 * The old encoding stored one Firestore map per pixel ({color, index}). A
 * 78-pixel image became a ~23KB document. The device's Firebase client has no
 * PSRAM, so its response String grows by repeated realloc in 2KB steps with no
 * reservation; a contiguous ~23KB block is not available on a TLS-fragmented
 * heap. The fetch returned an EMPTY body with error code 0 and the IMAGE screen
 * rendered black.
 *
 * SPARSE_PACKED_V1 stores the same image as one string of fixed-width 8-char
 * groups, "IIRRGGBB" per pixel (II = index 0-255, RRGGBB = colour). The same
 * image drops to roughly 1KB.
 *
 * NOTE: this DELETES the legacy `pixels` field. That is the point - leaving it
 * behind keeps the document large and the device still cannot fetch it.
 *
 * USAGE
 * -----
 *   npm install firebase-admin
 *
 *   # Service account key from:
 *   # Firebase Console > Project Settings > Service Accounts > Generate new private key
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *
 *   node tools/migrate_assets_to_packed.js            # dry run, writes nothing
 *   node tools/migrate_assets_to_packed.js --apply    # perform the migration
 *
 * ALTERNATIVE: with only a handful of assets, simply opening each one in the
 * app and saving it does the same thing - updateAsset() now writes the packed
 * field and deletes the legacy array.
 */

const admin = require('firebase-admin');

const PROJECT_ID = 'twinglow-bab2e';
const APPLY = process.argv.includes('--apply');

function toPacked(pixels) {
  let out = '';
  for (const entry of pixels) {
    let index;
    let rgb888;

    if (Array.isArray(entry) && entry.length >= 2) {
      // Legacy array-of-arrays shape
      index = entry[0];
      rgb888 = entry[1];
    } else if (entry && typeof entry === 'object') {
      index = entry.index;
      rgb888 = entry.color;
    } else {
      continue;
    }

    if (typeof index !== 'number' || typeof rgb888 !== 'number') continue;
    if (index < 0 || index > 255) continue;

    out += index.toString(16).padStart(2, '0');
    out += (rgb888 & 0xffffff).toString(16).padStart(6, '0');
  }
  return out;
}

async function main() {
  admin.initializeApp({ projectId: PROJECT_ID });
  const db = admin.firestore();

  const snapshot = await db.collection('assets').get();
  console.log(`Found ${snapshot.size} asset document(s)\n`);

  let migrated = 0;
  let skipped = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();

    if (data.pixelsPacked !== undefined) {
      console.log(`  SKIP  ${doc.id} - already packed`);
      skipped++;
      continue;
    }
    if (!Array.isArray(data.pixels)) {
      console.log(`  SKIP  ${doc.id} - no 'pixels' array (animation or empty?)`);
      skipped++;
      continue;
    }

    const packed = toPacked(data.pixels);
    const before = JSON.stringify(data).length;
    const after = before - JSON.stringify(data.pixels).length + packed.length;

    console.log(
      `  ${APPLY ? 'WRITE' : 'DRY  '} ${doc.id} - ${data.pixels.length} pixels, ` +
        `${packed.length} chars, approx ${before} -> ${after} bytes`
    );

    if (APPLY) {
      await doc.ref.update({
        encoding: 'SPARSE_PACKED_V1',
        pixelsPacked: packed,
        pixels: admin.firestore.FieldValue.delete(),
      });
    }
    migrated++;
  }

  console.log(
    `\n${APPLY ? 'Migrated' : 'Would migrate'} ${migrated}, skipped ${skipped}.`
  );
  if (!APPLY && migrated > 0) {
    console.log('Re-run with --apply to write the changes.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
