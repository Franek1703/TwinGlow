// No historical events are copied into the new mailboxes. Dry-run by default.
import {initializeApp,applicationDefault} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getDatabase} from 'firebase-admin/database';
import {getAuth} from 'firebase-admin/auth';
import {readFileSync} from 'node:fs';
import {verifiedLegacyAssetPatch} from './legacy-asset-migration.mjs';
const args=process.argv.slice(2),option=n=>{const i=args.indexOf(n);return i<0?null:args[i+1];};
const projectId=option('--project'),databaseURL=option('--database-url');
if(!projectId||!databaseURL)throw Error('Usage: node migrate-pairing.mjs --project PROJECT --database-url URL [--asset-owner-manifest VERIFIED.json] [--apply]');
initializeApp({credential:applicationDefault(),projectId,databaseURL});
const fs=getFirestore(),db=getDatabase();
const pairs=await fs.collection('pairs').get(),legacy=await db.ref('pairs').get();
const manifestPath=option('--asset-owner-manifest');
const manifest=manifestPath?JSON.parse(readFileSync(manifestPath,'utf8')):{};
if(!manifest||typeof manifest!=='object'||Array.isArray(manifest))throw Error('Manifest must map asset IDs to verified owner UIDs');
const assets=[];
for(const [id,ownerUid] of Object.entries(manifest)){
  if(!id||id.includes('/'))throw Error('Invalid asset ID');
  await getAuth().getUser(ownerUid);
  const ref=fs.collection('assets').doc(id),doc=await ref.get();
  if(!doc.exists)throw Error('Manifest asset does not exist');
  assets.push({ref,patch:verifiedLegacyAssetPatch(doc.data(),ownerUid)});
}
console.log(JSON.stringify({projectId,verifiedLegacyAssets:assets.length,legacyFirestorePairs:pairs.size,legacyRtdbPairs:legacy.numChildren(),apply:args.includes('--apply')},null,2));
if(!args.includes('--apply'))process.exit(0);
for(const {ref,patch} of assets)await ref.update(patch);
for(const p of pairs.docs)await p.ref.set({state:'ENDED',migration:'snapshot-v1-repair-required'},{merge:true});
await db.ref('pairs').remove();
console.log('Legacy delivery retired. Local screen documents and assets were preserved. Users must explicitly pair again.');
