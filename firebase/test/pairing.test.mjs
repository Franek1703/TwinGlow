import {createHash} from 'node:crypto';
import {before,after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {verifiedLegacyAssetPatch} from '../legacy-asset-migration.mjs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {ref,set,get,update,serverTimestamp,query,orderByChild,equalTo,limitToFirst} from 'firebase/database';
import {doc,setDoc,getDoc,updateDoc,collection,getDocs,query as fsQuery,where,writeBatch,deleteField,increment,runTransaction} from 'firebase/firestore';

let env;
const db = uid => env.authenticatedContext(uid,{email:`${uid}@example.com`}).database();
const deviceDb = id => env.authenticatedContext(`auth-${id}`,{twinGlowDeviceId:id}).database();
const bindings={A:{authUid:'auth-A',ownerUid:'alice',enabled:true},B:{authUid:'auth-B',ownerUid:'bob',enabled:true},C:{authUid:'auth-C',ownerUid:'eve',enabled:true}};
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-twinglow',database:{rules:readFileSync(new URL('../database.rules.json',import.meta.url),'utf8')},firestore:{rules:readFileSync(new URL('../firestore.rules',import.meta.url),'utf8')}});});
after(async()=>env?.cleanup());
beforeEach(async()=>{await env.clearDatabase();await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{
  await set(ref(c.database()),{deviceAccess:bindings,pairing:{directory:{alice:{email:'alice@example.com'},bob:{email:'bob@example.com'},eve:{email:'eve@example.com'}}}});
  for(const [id,binding] of Object.entries(bindings)) await setDoc(doc(c.firestore(),`deviceAccess/${id}`),binding);
});});
export function invitation(id='invite',fromUid='alice',toUid='bob',fromDeviceId='A'){
  return {[`pairing/invites/${id}`]:{schemaVersion:1,fromUid,toUid,fromDeviceId,fromEmail:`${fromUid}@example.com`,toEmail:`${toUid}@example.com`,status:'pending',createdAt:serverTimestamp(),updatedAt:serverTimestamp()},[`pairing/pending/${fromUid}/${toUid}`]:id};
}
function acceptance(id='invite',pairId='pair',fromUid='alice',toUid='bob',a='A',b='B'){
  return {[`pairing/invites/${id}/status`]:'accepted',[`pairing/invites/${id}/pairId`]:pairId,[`pairing/invites/${id}/updatedAt`]:serverTimestamp(),[`pairing/pending/${fromUid}/${toUid}`]:null,
  [`pairing/pairs/${pairId}`]:{schemaVersion:1,userA:fromUid,userB:toUid,deviceA:a,deviceB:b,userAEmail:`${fromUid}@example.com`,userBEmail:`${toUid}@example.com`,inviteId:id,state:'ACTIVE',createdAt:serverTimestamp()},
  [`pairing/users/${fromUid}`]:pairId,[`pairing/users/${toUid}`]:pairId,[`config/${a}/pair`]:{pairId,partnerDeviceId:b},[`config/${b}/pair`]:{pairId,partnerDeviceId:a}};
}
async function paired(){await update(ref(db('alice')),invitation());await update(ref(db('bob')),acceptance());}
function publication(sender='A',recipient='B',sequence=1,eventId=`event${sequence}`){
  const meta={schemaVersion:1,eventId,sequence,pairId:'pair',senderDeviceId:sender,recipientDeviceId:recipient,screenId:'screen',assetId:'asset',sentAt:serverTimestamp()};
  return {[`pairing/mailboxes/pair/${sender}`]:{meta,content:{type:'IMAGE',encoding:'SPARSE_PACKED_V1',pixelsPacked:'00ff0000'}},[`config/${recipient}/incoming`]:meta};
}
function endPair(){return {'pairing/pairs/pair/state':'ENDED','pairing/pairs/pair/endedAt':serverTimestamp(),'pairing/users/alice':null,'pairing/users/bob':null,'config/A/pair':null,'config/B/pair':null,'config/A/incoming':null,'config/B/incoming':null,'pairing/mailboxes/pair':null,'pairing/acks/pair':null};}
test('email lookup is bounded; directory cannot impersonate another identity',async()=>{
  await assertSucceeds(get(query(ref(db('alice'),'pairing/directory'),orderByChild('email'),equalTo('bob@example.com'),limitToFirst(1))));
  await assertFails(get(ref(db('alice'),'pairing/directory')));
  await assertFails(set(ref(db('eve'),'pairing/directory/bob'),{email:'bob@example.com'}));
  await assertFails(set(ref(db('eve'),'pairing/directory/eve'),{email:'bob@example.com'}));
});
test('create, receive and atomically accept an invitation',async()=>{
  await assertSucceeds(update(ref(db('alice')),invitation()));
  const received=await assertSucceeds(get(query(ref(db('bob'),'pairing/invites'),orderByChild('toUid'),equalTo('bob'))));
  assert.equal(received.child('invite/fromDeviceId').val(),'A');
  await assertSucceeds(update(ref(db('bob')),acceptance()));
  assert.equal((await get(ref(deviceDb('A'),'config/A/pair/partnerDeviceId'))).val(),'B');
  assert.equal((await get(ref(deviceDb('B'),'config/B/pair/partnerDeviceId'))).val(),'A');
});
test('self, duplicate, forged-device and unauthorised invitations are denied',async()=>{
  await assertFails(update(ref(db('alice')),invitation('self','alice','alice')));
  await assertFails(update(ref(db('alice')),invitation('bad','alice','bob','C')));
  await assertSucceeds(update(ref(db('alice')),invitation()));
  await assertFails(update(ref(db('alice')),invitation('duplicate')));
  await assertFails(update(ref(db('eve')),acceptance()));
  await assertFails(update(ref(db('alice')),acceptance()));
  await assertFails(update(ref(db('bob')),acceptance('invite','pair','alice','bob','A','C')));
});
test('partial acceptance or forged membership cannot establish a pair',async()=>{
  await update(ref(db('alice')),invitation());
  const changes=acceptance();delete changes['config/A/pair'];
  await assertFails(update(ref(db('bob')),changes));
  await assertFails(set(ref(db('bob'),'pairing/users/alice'),'pair'));
  assert.equal((await get(ref(db('bob'),'pairing/users/bob'))).exists(),false);
});
test('rejection/cancellation consumes pending slot without creating a pair',async()=>{
  await update(ref(db('alice')),invitation());
  const terminal=status=>({'pairing/invites/invite/status':status,'pairing/invites/invite/updatedAt':serverTimestamp(),'pairing/pending/alice/bob':null});
  await assertFails(update(ref(db('alice')),terminal('rejected')));
  await assertSucceeds(update(ref(db('bob')),terminal('rejected')));
  await assertFails(update(ref(db('bob')),acceptance()));
  await assertSucceeds(update(ref(db('alice')),invitation('second')));
});
test('expired invitation cannot be accepted',async()=>{
  await update(ref(db('alice')),invitation());
  await env.withSecurityRulesDisabled(c=>set(ref(c.database(),'pairing/invites/invite/createdAt'),Date.now()-8*86400000));
  await assertFails(update(ref(db('bob')),acceptance()));
});
test('simultaneous acceptances cannot pair the same user twice',async()=>{
  await update(ref(db('alice')),invitation());await update(ref(db('eve')),invitation('other','eve','bob','C'));
  const results=await Promise.allSettled([update(ref(db('bob')),acceptance()),update(ref(db('bob')),acceptance('other','otherpair','eve','bob','C','B'))]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
});
test('snapshot publication works both ways; old sequence and forged sender fail',async()=>{
  await paired();
  await assertSucceeds(update(ref(deviceDb('A')),publication()));
  await assertSucceeds(get(ref(deviceDb('B'),'pairing/mailboxes/pair/A')));
  await assertSucceeds(update(ref(deviceDb('B')),publication('B','A')));
  await assertFails(update(ref(deviceDb('C')),publication()));
  await assertFails(update(ref(db('alice')),publication('A','B',2)));
  await assertSucceeds(update(ref(deviceDb('A')),publication('A','B',3)));
  await assertFails(update(ref(deviceDb('A')),publication('A','B',2)));
  const partial=publication('A','B',4);delete partial['config/B/incoming'];
  await assertFails(update(ref(deviceDb('A')),partial));
  await assertFails(get(ref(env.unauthenticatedContext().database(),'pairing/mailboxes/pair/A')));
});
test('app previews are owner-written, partner-readable and revoked on unpair',async()=>{
  await paired();
  const preview={schemaVersion:1,deviceId:'A',screenId:'screen',name:'Image Screen',assetId:'image',assetName:'Lolypop',content:{type:'IMAGE',encoding:'SPARSE_PACKED_V1',pixelsPacked:'00ff0000'}};
  const catalog=(sourceVersion,screen=preview)=>({sourceVersion,updatedAt:serverTimestamp(),screens:screen?{screen}:{}});
  const path='pairing/sharedScreens/pair/alice';
  await assertSucceeds(set(ref(db('alice'),path),catalog(1)));
  assert.equal((await assertSucceeds(get(ref(db('bob'),path)))).child('screens/screen/assetName').val(),'Lolypop');
  await assertFails(set(ref(db('bob'),path),catalog(2)));
  await assertFails(get(ref(db('eve'),'pairing/sharedScreens/pair/alice')));
  await assertFails(get(ref(deviceDb('B'),'pairing/sharedScreens/pair/alice')));
  await assertFails(get(ref(env.unauthenticatedContext().database(),'pairing/sharedScreens/pair/alice')));
  for(const patch of [{deviceId:'B'},{screenId:'other'},{extra:'x'},{content:{...preview.content,pixelsPacked:'ff'.repeat(2048)}}]) {
    await assertFails(set(ref(db('alice'),path),catalog(2,{...preview,...patch})));
  }
  await assertSucceeds(set(ref(db('alice'),path),catalog(2,{...preview,content:{type:'ANIMATION',encoding:'DELTA_SPARSE_PACKED_V1',basePixelsPacked:'00ff0000',frameDeltasPacked:['00000000'],frameDurationsMs:[100,250],frameCount:2,loop:true}})));
  await assertSucceeds(set(ref(db('alice'),path),catalog(4,null)));
  await assertFails(set(ref(db('alice'),path),catalog(3)));
  await assertFails(set(ref(db('alice'),path),catalog(4)));
  await assertFails(set(ref(db('alice'),path),null));
  await assertSucceeds(set(ref(db('alice'),path),catalog(5)));
  const end={...endPair(),'pairing/sharedScreens/pair':null};
  await assertSucceeds(update(ref(db('bob')),end));
  await assertFails(get(ref(db('bob'),'pairing/sharedScreens/pair/alice')));
  await assertFails(set(ref(db('alice'),path),catalog(6)));
  await env.withSecurityRulesDisabled(async c=>assert.equal((await get(ref(c.database(),'pairing/sharedScreens/pair'))).exists(),false));
});
test('legacy unpair revokes reads even when it leaves the app preview catalog',async()=>{
  await paired();
  const path='pairing/sharedScreens/pair/alice';
  await assertSucceeds(set(ref(db('alice'),path),{sourceVersion:1,updatedAt:serverTimestamp(),screens:{screen:{schemaVersion:1,deviceId:'A',screenId:'screen',name:'Image',assetId:'image',assetName:'Private',content:{type:'IMAGE',encoding:'SPARSE_PACKED_V1',pixelsPacked:'00ff0000'}}}}));
  await assertSucceeds(update(ref(db('bob')),endPair()));
  await assertFails(get(ref(db('alice'),path)));
  await assertFails(get(ref(db('bob'),path)));
  await env.withSecurityRulesDisabled(async c=>assert.equal((await get(ref(c.database(),path))).exists(),true));
});
test('only the receiver can acknowledge the current event; unpair revokes all access',async()=>{
  await paired();await update(ref(deviceDb('A')),publication());
  const ack={eventId:'event1',sequence:1,status:'displayed',at:serverTimestamp()};
  await assertFails(set(ref(deviceDb('A'),'pairing/acks/pair/B'),ack));
  await assertSucceeds(set(ref(deviceDb('B'),'pairing/acks/pair/B'),ack));
  await assertFails(update(ref(db('eve')),endPair()));
  await assertSucceeds(update(ref(db('alice')),endPair()));
  await assertFails(update(ref(deviceDb('A')),publication('A','B',2)));
  await assertFails(get(ref(deviceDb('B'),'pairing/mailboxes/pair/A')));
  assert.equal((await get(ref(deviceDb('B'),'config/B'))).child('pair').exists(),false);
});
test('payload size, schema, timestamp and extra fields are enforced',async()=>{
  await paired();
  for(const mutate of [p=>p['pairing/mailboxes/pair/A'].content.pixelsPacked='ff'.repeat(2048),p=>p['pairing/mailboxes/pair/A'].content.secret='x',p=>p['pairing/mailboxes/pair/A'].meta.schemaVersion=2,p=>{p['pairing/mailboxes/pair/A'].meta.sentAt=1;p['config/B/incoming'].sentAt=1;}]){
    const p=publication();mutate(p);await assertFails(update(ref(deviceDb('A')),p));
  }
  const p=publication();p['pairing/mailboxes/pair/A'].content={type:'ANIMATION',encoding:'DELTA_SPARSE_PACKED_V1',basePixelsPacked:'00ff0000',frameDeltasPacked:['00000000'],frameDurationsMs:[50,5000],frameCount:2,loop:true};
  await assertSucceeds(update(ref(deviceDb('A')),p));
});
test('Firestore ownership and device claims cannot be forged; partner assets stay private',async()=>{
  const fs=uid=>env.authenticatedContext(uid,{email:`${uid}@example.com`}).firestore();
  const dfs=id=>env.authenticatedContext(`auth-${id}`,{twinGlowDeviceId:id}).firestore();
  await assertSucceeds(setDoc(doc(dfs('A'),'devices/A'),{fwVersion:'2',configVersion:0,hw:{bme680:false}}));
  await assertSucceeds(setDoc(doc(dfs('A'),'users/alice/devices/A'),{role:'OWNER'}));
  await assertFails(setDoc(doc(dfs('A'),'users/eve/devices/A'),{role:'OWNER'}));
  await assertFails(setDoc(doc(fs('eve'),'deviceAccess/A'),bindings.A));
  await assertSucceeds(setDoc(doc(fs('alice'),'assets/image'),{ownerUid:'alice',isDefault:false,type:'IMAGE',pixelsPacked:'00ff0000'}));
  await assertSucceeds(getDoc(doc(dfs('A'),'assets/image')));
  await assertFails(getDoc(doc(dfs('B'),'assets/image')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'assets/image')));
  await assertFails(updateDoc(doc(fs('alice'),'assets/image'),{isDefault:true}));
  await assertFails(updateDoc(doc(dfs('A'),'devices/A'),{configVersion:9}));
});

test('publication serialized by production firmware is accepted and decoded by RTDB',async()=>{
  await paired();
  const payload=JSON.parse(readFileSync(join(tmpdir(),'twinglow-firmware-publication.json'),'utf8'));
  await assertSucceeds(update(ref(deviceDb('A')),payload));
  const mailbox=(await get(ref(deviceDb('B'),'pairing/mailboxes/pair/A'))).val();
  assert.equal(mailbox.content.frameDeltasPacked[0],'000000001100ff00');
  assert.equal(typeof mailbox.meta.sentAt,'number');
  assert.equal(mailbox.meta.eventId,(await get(ref(deviceDb('B'),'config/B/incoming/eventId'))).val());
});

test('production asset collection queries obey canonical and default ownership',async()=>{
  await env.withSecurityRulesDisabled(async c=>{
    await setDoc(doc(c.firestore(),'assets/mine'),{ownerUid:'alice',isDefault:false});
    await setDoc(doc(c.firestore(),'assets/theirs'),{ownerUid:'bob',isDefault:false});
    await setDoc(doc(c.firestore(),'assets/legacy'),{userId:'alice',isDefault:false});
    await setDoc(doc(c.firestore(),'assets/default'),{isDefault:true});
  });
  const fs=env.authenticatedContext('alice',{email:'alice@example.com'}).firestore();
  const mine=await assertSucceeds(getDocs(fsQuery(collection(fs,'assets'),where('ownerUid','==','alice'),where('isDefault','==',false))));
  assert.deepEqual(mine.docs.map(d=>d.id),['mine']);
  const defaults=await assertSucceeds(getDocs(fsQuery(collection(fs,'assets'),where('isDefault','==',true))));
  assert.deepEqual(defaults.docs.map(d=>d.id),['default']);
  await assertFails(getDocs(fsQuery(collection(fs,'assets'),where('userId','==','alice'),where('isDefault','==',false))));
  await assertFails(getDocs(fsQuery(collection(fs,'assets'),where('ownerUid','==','bob'),where('isDefault','==',false))));
});

test('verified legacy ownership migration preserves content and enables canonical queries',async()=>{
  assert.throws(()=>verifiedLegacyAssetPatch({ownerUid:'bob'},'alice'),/mismatch/);
  assert.throws(()=>verifiedLegacyAssetPatch({userId:'bob'},'alice'),/mismatch/);
  assert.throws(()=>verifiedLegacyAssetPatch({userId:'alice',isDefault:true},'alice'),/Default/);
  await env.withSecurityRulesDisabled(async c=>{
    const ref=doc(c.firestore(),'assets/old-image');
    const data={userId:'alice',isDefault:false,type:'IMAGE',encoding:'SPARSE_I16_RGB888',pixels:[{index:0,color:16711680}]};
    await setDoc(ref,data);await updateDoc(ref,verifiedLegacyAssetPatch(data,'alice'));
  });
  const fs=env.authenticatedContext('alice',{email:'alice@example.com'}).firestore();
  const result=await assertSucceeds(getDocs(fsQuery(collection(fs,'assets'),where('ownerUid','==','alice'),where('isDefault','==',false))));
  assert.equal(result.docs[0].data().pixels[0].color,16711680);
});

const fsHuman=uid=>env.authenticatedContext(uid,{email:`${uid}@example.com`}).firestore();
for (const [uid, device] of [['alice','A'], ['bob','B']]) test(`owner ${uid} creates private screen types with transactional playlist appends`,async()=>{
  await sharingReady();await publishAlbum();
  const fs=fsHuman(uid),counter=doc(fs,`playlistState/${device}`),deviceRef=doc(fs,`devices/${device}`);
  const initial=(await getDoc(counter)).data().nextOrder;
  const initialConfig=(await getDoc(deviceRef)).data().configVersion;
  const types=['animation','image','clock','sensor','game'];
  for (const [i,type] of types.entries()) {
    const screen=doc(fs,`devices/${device}/screens/new_${type}`);
    const poolType=type==='animation'||type==='image';
    assert.equal((await getDoc(screen)).exists(),false);
    await assertSucceeds(runTransaction(fs,async tx=>{
      const state=await tx.get(counter),existing=await tx.get(screen);
      assert.equal(existing.exists(),false);
      tx.update(counter,{nextOrder:state.data().nextOrder+1});
      tx.update(deviceRef,{configVersion:increment(1)});
      tx.set(screen,{type,name:`${type} screen`,enabled:true,isShared:false,order:state.data().nextOrder,assetId:poolType?'selected_asset':null,config:null,previewData:null,createdAt:new Date(),...(poolType?{defaultAssetId:'selected_asset',availableAssetIds:['selected_asset'],allowManualSwitch:true}:{})});
    }));
    assert.equal((await getDoc(screen)).data().order,initial+i);
    assert.equal((await getDoc(counter)).data().nextOrder,initial+i+1);
    assert.equal((await getDoc(deviceRef)).data().configVersion,initialConfig+i+1);
  }
});
test('private screen creation denies partner, stranger, firmware and anonymous clients without partial playlist changes',async()=>{
  await sharingReady();await publishAlbum();
  for (const fs of [fsHuman('bob'),fsHuman('eve'),fsDevice('A'),env.unauthenticatedContext().firestore()]) {
    const batch=writeBatch(fs);
    batch.set(doc(fs,'devices/A/screens/unauthorized'),{type:'animation',order:4,enabled:true,isShared:false});
    batch.update(doc(fs,'playlistState/A'),{nextOrder:5});
    batch.update(doc(fs,'devices/A'),{configVersion:increment(1)});
    await assertFails(batch.commit());
    // Also test the screen write alone so other batch permissions cannot mask it.
    await assertFails(setDoc(doc(fs,'devices/A/screens/unauthorized'),{type:'animation',order:4,enabled:true,isShared:false}));
  }
  const fs=fsHuman('alice');
  assert.equal((await getDoc(doc(fs,'devices/A/screens/unauthorized'))).exists(),false);
  assert.equal((await getDoc(doc(fs,'playlistState/A'))).data().nextOrder,4);
  assert.equal((await getDoc(doc(fs,'devices/A'))).data().configVersion,1);
});
const fsDevice=id=>env.authenticatedContext(`auth-${id}`,{twinGlowDeviceId:id}).firestore();
const sharingGrant={schemaVersion:1,userA:'alice',userB:'bob',deviceA:'A',deviceB:'B',acceptedA:true,acceptedB:false,state:'PENDING',contentVersion:0};
const album={schemaVersion:2,name:'Five images',type:'IMAGE',availableAssetIds:['a0','a1','a2','a3','a4'],defaultAssetId:'a0',allowManualSwitch:true,config:{},contentVersion:0,pairId:'pair',createdBy:'alice',state:'STAGING',screenRefs:{A:'source',B:'shared'}};
async function sharingReady(){
  await setDoc(doc(fsHuman('alice'),'playlistState/A'),{nextOrder:4,pairId:'pair'});
  await setDoc(doc(fsHuman('bob'),'playlistState/B'),{nextOrder:1,pairId:'pair'});
  await setDoc(doc(fsHuman('alice'),'sharingPairs/pair'),sharingGrant);
  await updateDoc(doc(fsHuman('bob'),'sharingPairs/pair'),{acceptedB:true,state:'ACTIVE'});
  await setDoc(doc(fsHuman('alice'),'devices/A'),{configVersion:0});
  await setDoc(doc(fsHuman('bob'),'devices/B'),{configVersion:0});
  await setDoc(doc(fsHuman('alice'),'devices/A/screens/source'),{type:'image',order:3,enabled:true});
  await setDoc(doc(fsHuman('bob'),'devices/B/screens/clock'),{type:'clock',order:0,enabled:true});
  for(const id of album.availableAssetIds) await setDoc(doc(fsHuman('alice'),`assets/${id}`),{ownerUid:'alice',isDefault:false,type:'IMAGE',encoding:'SPARSE_PACKED_V1',pixelsPacked:'00ff0000'});
}
async function publishAlbum(){
  const fs=fsHuman('alice');
  await setDoc(doc(fs,'sharedScreens/album'),album);
  const batch=writeBatch(fs);
  for(const id of album.availableAssetIds) batch.update(doc(fs,`assets/${id}`),{sharedScreenIds:['album'],sharingPairId:'pair',sharingMutationScreenId:'album'});
  batch.update(doc(fs,'sharedScreens/album'),{state:'ACTIVE',contentVersion:1});
  batch.update(doc(fs,'sharingPairs/pair'),{contentVersion:1,mutationKind:'SCREEN',mutationId:'album'});
  batch.set(doc(fs,'devices/A/screens/source'),{sharedScreenId:'album',order:3,enabled:true,durationMs:10000});
  batch.set(doc(fs,'devices/B/screens/shared'),{sharedScreenId:'album',order:1,enabled:true,durationMs:10000});
  batch.update(doc(fs,'playlistState/B'),{nextOrder:2,lastSharedScreenId:'album'});
  batch.update(doc(fs,'devices/A'),{configVersion:increment(1)});
  await batch.commit();
}
test('Firestore sharing requires bilateral consent and cannot forge partner acceptance or device binding',async()=>{
  const a=fsHuman('alice');
  await assertSucceeds(setDoc(doc(a,'sharingPairs/pair'),sharingGrant));
  await assertFails(updateDoc(doc(a,'sharingPairs/pair'),{acceptedB:true,state:'ACTIVE'}));
  await assertFails(setDoc(doc(fsHuman('eve'),'sharingPairs/forged'),{...sharingGrant,userA:'eve'}));
  await assertFails(setDoc(doc(a,'sharedScreens/album'),album));
  await assertSucceeds(updateDoc(doc(fsHuman('bob'),'sharingPairs/pair'),{acceptedB:true,state:'ACTIVE'}));
  await assertFails(updateDoc(doc(fsDevice('A'),'sharingPairs/pair'),{contentVersion:1}));
});
test('full album publication creates narrow references and both devices can fetch original assets',async()=>{
  await sharingReady(); await assertSucceeds(publishAlbum());
  for(const id of album.availableAssetIds){
    await assertSucceeds(getDoc(doc(fsHuman('bob'),`assets/${id}`)));
    await assertSucceeds(getDoc(doc(fsDevice('B'),`assets/${id}`)));
    await assertSucceeds(getDoc(doc(fsDevice('A'),`assets/${id}`)));
    await assertFails(getDoc(doc(fsHuman('eve'),`assets/${id}`)));
    await assertFails(getDoc(doc(fsDevice('C'),`assets/${id}`)));
  }
  await assertFails(getDoc(doc(fsHuman('alice'),'devices/B/screens/clock')));
  await assertFails(updateDoc(doc(fsHuman('alice'),'devices/B/screens/shared'),{order:0}));
  await assertFails(updateDoc(doc(fsHuman('alice'),'devices/B'),{brightness:1}));
  await assertSucceeds(updateDoc(doc(fsHuman('bob'),'devices/B/screens/shared'),{order:7,enabled:false}));
  assert.equal((await getDoc(doc(fsHuman('alice'),'devices/A/screens/source'))).data().order,3);
});
test('shared asset edits require version notification and cannot change ownership or permissions',async()=>{
  await sharingReady(); await publishAlbum(); const fs=fsHuman('bob');
  await assertFails(updateDoc(doc(fs,'assets/a0'),{pixelsPacked:'00ffffff'}));
  const batch=writeBatch(fs);batch.update(doc(fs,'assets/a0'),{pixelsPacked:'00ffffff',revision:1});batch.update(doc(fs,'sharingPairs/pair'),{contentVersion:2,mutationKind:'ASSET',mutationId:'a0'});
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(fs,'assets/a0'),{ownerUid:'bob'}));
  await assertFails(updateDoc(doc(fs,'assets/a0'),{sharedScreenIds:['other']}));
  await assertFails(updateDoc(doc(fs,'sharedScreens/album'),{pairId:'other',contentVersion:2}));
});
test('revocation restores the creators private reference and removes partner access atomically',async()=>{
  await sharingReady();await publishAlbum();const fs=fsHuman('bob'),batch=writeBatch(fs);
  for(const id of album.availableAssetIds) batch.update(doc(fs,`assets/${id}`),{sharedScreenIds:[],sharingPairId:deleteField(),sharingMutationScreenId:'album'});
  batch.update(doc(fs,'sharedScreens/album'),{state:'REVOKED',contentVersion:2});batch.update(doc(fs,'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'album'});
  batch.update(doc(fs,'devices/A/screens/source'),{sharedScreenId:deleteField(),name:album.name,type:'image',isShared:false,availableAssetIds:album.availableAssetIds,defaultAssetId:'a0',assetId:'a0',allowManualSwitch:true,config:{}});
  batch.delete(doc(fs,'devices/B/screens/shared'));
  await assertSucceeds(batch.commit());
  await assertFails(getDoc(doc(fsHuman('bob'),'assets/a0')));await assertFails(getDoc(doc(fsDevice('B'),'assets/a0')));
  await assertSucceeds(getDoc(doc(fsHuman('alice'),'assets/a0')));
  await assertSucceeds(updateDoc(doc(fs,'sharingPairs/pair'),{state:'REVOKED'}));
  await assertFails(updateDoc(doc(fsHuman('alice'),'sharingPairs/pair'),{state:'ACTIVE'}));
});

test('shared animation asset stays whole and can be edited in the reverse direction',async()=>{
  await sharingReady();await publishAlbum();const fs=fsHuman('bob');
  const animation={ownerUid:'bob',isDefault:false,type:'ANIMATION',encoding:'DELTA_SPARSE_PACKED_V1',basePixelsPacked:'00ff0000',frameDeltasPacked:['00000000'],frameDurationsMs:[100,200],frameCount:2,loop:true};
  await setDoc(doc(fs,'assets/anim'),animation);
  const batch=writeBatch(fs);
  batch.update(doc(fs,'assets/anim'),{sharedScreenIds:['album'],sharingPairId:'pair',sharingMutationScreenId:'album'});
  for(const id of album.availableAssetIds)batch.update(doc(fs,`assets/${id}`),{sharedScreenIds:[],sharingPairId:deleteField(),sharingMutationScreenId:'album'});
  batch.update(doc(fs,'sharedScreens/album'),{type:'ANIMATION',availableAssetIds:['anim'],defaultAssetId:'anim',contentVersion:2});
  batch.update(doc(fs,'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'album'});await assertSucceeds(batch.commit());
  assert.deepEqual((await getDoc(doc(fsDevice('A'),'assets/anim'))).data().frameDurationsMs,[100,200]);
  const reverseFs=fsHuman('alice'),reverse=writeBatch(reverseFs);reverse.update(doc(reverseFs,'assets/anim'),{frameDurationsMs:[250,400],revision:1});reverse.update(doc(reverseFs,'sharingPairs/pair'),{contentVersion:3,mutationKind:'ASSET',mutationId:'anim'});await assertSucceeds(reverse.commit());
});
test('restoration can retain partner content only as an exact private copy for the creator',async()=>{
  await sharingReady();await publishAlbum();const bob=fsHuman('bob'),alice=fsHuman('alice');
  await setDoc(doc(bob,'assets/b'),{ownerUid:'bob',isDefault:false,type:'IMAGE',pixelsPacked:'00ffffff'});
  const add=writeBatch(bob);add.update(doc(bob,'assets/b'),{sharedScreenIds:['album'],sharingPairId:'pair',sharingMutationScreenId:'album'});add.update(doc(bob,'sharedScreens/album'),{availableAssetIds:[...album.availableAssetIds,'b'],contentVersion:2});add.update(doc(bob,'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'album'});await assertSucceeds(add.commit());
  await assertFails(setDoc(doc(bob,'assets/retained_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),{ownerUid:'alice',isDefault:false,type:'IMAGE',pixelsPacked:'00ffffff',retainedFrom:'b',retainedScreenId:'album'}));
  await assertSucceeds(updateDoc(doc(bob,'sharingPairs/pair'),{state:'CLOSING'}));
  const stop=writeBatch(bob),ids=[...album.availableAssetIds,'retained_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'];
  stop.set(doc(bob,'assets/retained_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),{ownerUid:'alice',isDefault:false,type:'IMAGE',pixelsPacked:'00ffffff',retainedFrom:'b',retainedScreenId:'album'});
  for(const id of [...album.availableAssetIds,'b'])stop.update(doc(bob,`assets/${id}`),{sharedScreenIds:[],sharingPairId:deleteField(),sharingMutationScreenId:'album'});
  stop.update(doc(bob,'sharedScreens/album'),{state:'REVOKED',availableAssetIds:ids,contentVersion:3});stop.update(doc(bob,'sharingPairs/pair'),{contentVersion:3,mutationKind:'SCREEN',mutationId:'album'});
  stop.update(doc(bob,'devices/A/screens/source'),{sharedScreenId:deleteField(),name:album.name,type:'image',isShared:false,availableAssetIds:ids,defaultAssetId:'a0',assetId:'a0',allowManualSwitch:true,config:{}});stop.delete(doc(bob,'devices/B/screens/shared'));await assertSucceeds(stop.commit());
  await assertSucceeds(getDoc(doc(alice,'assets/retained_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')));await assertFails(getDoc(doc(bob,'assets/retained_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')));
});

test('notification counters cannot be bumped without a shared content mutation',async()=>{
  await sharingReady();await publishAlbum();
  await assertFails(updateDoc(doc(fsHuman('bob'),'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'album'}));
  await assertFails(updateDoc(doc(fsHuman('bob'),'sharingPairs/pair'),{contentVersion:2,mutationKind:'ASSET',mutationId:'a0'}));
});

test('closing prevents publication and editing while allowing staged cleanup and eventual revocation',async()=>{
  await sharingReady();await publishAlbum();const alice=fsHuman('alice'),bob=fsHuman('bob');
  await setDoc(doc(alice,'sharedScreens/stage'),{...album,screenRefs:{A:'other',B:'other'}});
  await assertSucceeds(updateDoc(doc(bob,'sharingPairs/pair'),{state:'CLOSING'}));
  await assertFails(setDoc(doc(alice,'sharedScreens/newstage'),album));
  await assertFails(updateDoc(doc(alice,'sharingPairs/pair'),{state:'ACTIVE'}));
  await assertFails(getDoc(doc(fsDevice('B'),'assets/a0')));
  await assertSucceeds(getDoc(doc(bob,'assets/a0'))); // cleanup access only
  const edit=writeBatch(alice);edit.update(doc(alice,'sharedScreens/album'),{name:'race',contentVersion:2});edit.update(doc(alice,'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'album'});await assertFails(edit.commit());
  const assetEdit=writeBatch(bob);assetEdit.update(doc(bob,'assets/a0'),{pixelsPacked:'00ffffff',revision:1});assetEdit.update(doc(bob,'sharingPairs/pair'),{contentVersion:2,mutationKind:'ASSET',mutationId:'a0'});await assertFails(assetEdit.commit());
  const finalize=writeBatch(alice);finalize.update(doc(alice,'sharedScreens/stage'),{state:'ACTIVE',contentVersion:1});finalize.update(doc(alice,'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'stage'});await assertFails(finalize.commit());
  const cleanup=writeBatch(bob);cleanup.update(doc(bob,'sharedScreens/stage'),{state:'REVOKED',contentVersion:1});cleanup.update(doc(bob,'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'stage'});await assertSucceeds(cleanup.commit());
});

test('human template-copy transaction can read a missing ID without exposing existing private assets',async()=>{
  const alice=fsHuman('alice'),bob=fsHuman('bob'),id='copy_'+ 'f'.repeat(64);
  await assertSucceeds(getDoc(doc(alice,`assets/${id}`)));
  await assertSucceeds(setDoc(doc(alice,`assets/${id}`),{ownerUid:'alice',isDefault:false,type:'IMAGE',pixelsPacked:'00ff0000'}));
  await assertFails(getDoc(doc(bob,`assets/${id}`)));
  await assertFails(getDoc(doc(fsDevice('B'),'assets/missing-copy')));
});

test('unpair can tombstone an absent grant before delayed consent creation or acceptance',async()=>{
  const alice=fsHuman('alice'),bob=fsHuman('bob');
  await assertSucceeds(setDoc(doc(bob,'sharingPairs/pair'),{...sharingGrant,acceptedA:false,acceptedB:true,state:'CLOSING'}));
  await assertFails(setDoc(doc(alice,'sharingPairs/pair'),sharingGrant));
  await assertFails(updateDoc(doc(alice,'sharingPairs/pair'),{acceptedA:true,state:'ACTIVE'}));
  await assertSucceeds(updateDoc(doc(bob,'sharingPairs/pair'),{state:'REVOKED'}));
});

for(const size of [10,11]) test(`atomic retention of ${size} partner assets respects the Firestore access-call budget`,async()=>{
  await sharingReady();await publishAlbum();const bob=fsHuman('bob');
  const originals=Array.from({length:size},(_,i)=>`foreign${i}`);
  const body={ownerUid:'bob',isDefault:false,type:'IMAGE',pixelsPacked:'00ffffff'};
  for(const id of originals)await setDoc(doc(bob,`assets/${id}`),body);
  const replace=writeBatch(bob);
  for(const id of album.availableAssetIds)replace.update(doc(bob,`assets/${id}`),{sharedScreenIds:[],sharingPairId:deleteField(),sharingMutationScreenId:'album'});
  for(const id of originals)replace.update(doc(bob,`assets/${id}`),{sharedScreenIds:['album'],sharingPairId:'pair',sharingMutationScreenId:'album'});
  replace.update(doc(bob,'sharedScreens/album'),{availableAssetIds:originals,defaultAssetId:originals[0],contentVersion:2});replace.update(doc(bob,'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'album'});
  if(size>10){await assertFails(replace.commit());return;}
  await replace.commit();
  await env.withSecurityRulesDisabled(async c=>{
    for(const id of originals){
      await setDoc(doc(c.firestore(),`sharedScreens/prior_${id}`),{...album,state:'ACTIVE',availableAssetIds:[id],defaultAssetId:id});
      await updateDoc(doc(c.firestore(),`assets/${id}`),{sharedScreenIds:[`prior_${id}`,'album']});
    }
  });
  await updateDoc(doc(bob,'sharingPairs/pair'),{state:'CLOSING'});
  const retained=originals.map(id=>'retained_'+createHash('sha256').update(JSON.stringify(['album',id])).digest('hex'));
  const creator=fsHuman('alice'),stop=writeBatch(creator);
  originals.forEach((id,i)=>{
    stop.set(doc(creator,`assets/${retained[i]}`),{...body,ownerUid:'alice',retainedFrom:id,retainedScreenId:'album'});
    stop.update(doc(creator,`assets/${id}`),{sharedScreenIds:[`prior_${id}`],sharingPairId:'pair',sharingMutationScreenId:'album'});
  });
  stop.update(doc(creator,'sharedScreens/album'),{state:'REVOKED',availableAssetIds:retained,defaultAssetId:retained[0],contentVersion:3});stop.update(doc(creator,'sharingPairs/pair'),{contentVersion:3,mutationKind:'SCREEN',mutationId:'album'});
  stop.update(doc(creator,'devices/A/screens/source'),{sharedScreenId:deleteField(),name:album.name,type:'image',isShared:false,availableAssetIds:retained,defaultAssetId:retained[0],assetId:retained[0],allowManualSwitch:true,config:{}});stop.delete(doc(creator,'devices/B/screens/shared'));
  await assertSucceeds(stop.commit());
});

test('ten distinct-source foreign assets can be published and replaced within rule-access limits',async()=>{
  await sharingReady();await publishAlbum();const alice=fsHuman('alice');
  const sets=[Array.from({length:10},(_,i)=>`left${i}`),Array.from({length:10},(_,i)=>`right${i}`)];
  await env.withSecurityRulesDisabled(async c=>{
    for(const ids of sets)for(const id of ids){
      await setDoc(doc(c.firestore(),`sharedScreens/prior_${id}`),{...album,createdBy:'bob',state:'ACTIVE',availableAssetIds:[id],defaultAssetId:id});
      await setDoc(doc(c.firestore(),`assets/${id}`),{ownerUid:'bob',isDefault:false,type:'IMAGE',pixelsPacked:'00ffffff',sharedScreenIds:[`prior_${id}`],sharingPairId:'pair',sharingMutationScreenId:`prior_${id}`});
    }
  });
  for(const id of sets[0])await assertSucceeds(getDoc(doc(alice,`assets/${id}`)));
  await setDoc(doc(alice,'devices/A/screens/another'),{type:'image',order:4,enabled:true});
  const stage={...album,availableAssetIds:sets[0],defaultAssetId:sets[0][0],screenRefs:{A:'another',B:'incoming'}};
  await setDoc(doc(alice,'sharedScreens/new'),stage);
  const publish=writeBatch(alice);
  for(const id of sets[0])publish.update(doc(alice,`assets/${id}`),{sharedScreenIds:[`prior_${id}`,'new'],sharingMutationScreenId:'new'});
  publish.update(doc(alice,'sharedScreens/new'),{state:'ACTIVE',contentVersion:1});publish.update(doc(alice,'sharingPairs/pair'),{contentVersion:2,mutationKind:'SCREEN',mutationId:'new'});
  publish.set(doc(alice,'devices/A/screens/another'),{sharedScreenId:'new',order:4,enabled:true,durationMs:10000});publish.set(doc(alice,'devices/B/screens/incoming'),{sharedScreenId:'new',order:2,enabled:true,durationMs:10000});publish.update(doc(alice,'playlistState/B'),{nextOrder:3,lastSharedScreenId:'new'});publish.update(doc(alice,'devices/A'),{configVersion:increment(1)});
  await assertSucceeds(publish.commit());
  const replace=writeBatch(alice);
  for(const id of sets[0])replace.update(doc(alice,`assets/${id}`),{sharedScreenIds:[`prior_${id}`],sharingMutationScreenId:'new'});
  for(const id of sets[1])replace.update(doc(alice,`assets/${id}`),{sharedScreenIds:[`prior_${id}`,'new'],sharingMutationScreenId:'new'});
  replace.update(doc(alice,'sharedScreens/new'),{availableAssetIds:sets[1],defaultAssetId:sets[1][0],contentVersion:2});replace.update(doc(alice,'sharingPairs/pair'),{contentVersion:3,mutationKind:'SCREEN',mutationId:'new'});
  await assertSucceeds(replace.commit());
});

for(const templates of [0,4])test(`production migration transaction with creator userB long IDs templates=${templates}`,async()=>{
  const uid='Mafae7L0dxMvgxfVxjxmv0q1hbP2',peer='LHylA5snHuWPOXCJQYGlV9TYJg53',device='tg_f4ec6bb0ef83',partner='tg_a398a36269f7',pairId='-P3GXKqounihuSfvsWgM',local='screen_1788191873393';
  const sid=`ss_${pairId}_${device}_${local}`,remote=`shared_${sid}`;
  const ids=['asset_1788191864475','asset_1790946111492','asset_1790946148384','asset_1790976054854','asset_1790946209700'];
  const copied=ids.map((id,i)=>i==0||templates==0?id:'copy_'+createHash('sha256').update(JSON.stringify([sid,id])).digest('hex'));
  const fs=fsHuman(uid);
  await env.withSecurityRulesDisabled(async c=>{
    await setDoc(doc(c.firestore(),`deviceAccess/${device}`),{authUid:'auth-own',ownerUid:uid,enabled:true});
    await setDoc(doc(c.firestore(),`deviceAccess/${partner}`),{authUid:'auth-peer',ownerUid:peer,enabled:true});
    await setDoc(doc(c.firestore(),`sharingPairs/${pairId}`),{schemaVersion:1,userA:peer,userB:uid,deviceA:partner,deviceB:device,acceptedA:true,acceptedB:true,state:'ACTIVE',contentVersion:0});
    await setDoc(doc(c.firestore(),`playlistState/${device}`),{nextOrder:4,pairId});await setDoc(doc(c.firestore(),`playlistState/${partner}`),{nextOrder:1,pairId});
    await setDoc(doc(c.firestore(),`devices/${device}`),{configVersion:1});
    await setDoc(doc(c.firestore(),`devices/${device}/screens/${local}`),{order:0,enabled:true,type:'image',config:null,defaultAssetId:ids[0],availableAssetIds:ids,legacyMetadata:{version:7,note:'preserved until successful conversion'}});
    for(let i=0;i<ids.length;i++){
      await setDoc(doc(c.firestore(),`assets/${ids[i]}`),{ownerUid:uid,isDefault:i>0&&templates>0,type:'IMAGE',pixelsPacked:'00ff0000'});
      if(i>0&&templates>0)await setDoc(doc(c.firestore(),`assets/${copied[i]}`),{ownerUid:uid,isDefault:false,type:'IMAGE',pixelsPacked:'00ff0000'});
    }
  });
  const meta={...album,pairId,createdBy:uid,availableAssetIds:ids,defaultAssetId:ids[0],screenRefs:{[device]:local,[partner]:remote}};
  await setDoc(doc(fs,`sharedScreens/${sid}`),meta);
  await assertSucceeds(runTransaction(fs,async tx=>{
    await tx.get(doc(fs,`sharedScreens/${sid}`));await tx.get(doc(fs,`sharingPairs/${pairId}`));
    const source=await tx.get(doc(fs,`devices/${device}/screens/${local}`));await tx.get(doc(fs,`playlistState/${partner}`));
    for(const id of [...new Set([...ids,...copied])])await tx.get(doc(fs,`assets/${id}`));
    for(const id of copied)tx.update(doc(fs,`assets/${id}`),{sharedScreenIds:[sid],sharingPairId:pairId,sharingMutationScreenId:sid});
    tx.update(doc(fs,`sharedScreens/${sid}`),{availableAssetIds:copied,state:'ACTIVE',contentVersion:1});
    tx.update(doc(fs,`sharingPairs/${pairId}`),{contentVersion:1,mutationKind:'SCREEN',mutationId:sid});
    const reference={sharedScreenId:sid,order:0,enabled:true,durationMs:10000};
    for(const key of Object.keys(source.data()))if(!(key in reference))reference[key]=deleteField();
    tx.update(doc(fs,`devices/${device}/screens/${local}`),reference);
    tx.set(doc(fs,`devices/${partner}/screens/${remote}`),{sharedScreenId:sid,order:1,enabled:true,durationMs:10000});
    tx.update(doc(fs,`playlistState/${partner}`),{nextOrder:2,lastSharedScreenId:sid});tx.update(doc(fs,`devices/${device}`),{configVersion:increment(1)});
  }));
  assert.deepEqual((await getDoc(doc(fs,`devices/${device}/screens/${local}`))).data(),{sharedScreenId:sid,order:0,enabled:true,durationMs:10000});
  for(const id of copied)await assertSucceeds(getDoc(doc(fsHuman(peer),`assets/${id}`)));
});
