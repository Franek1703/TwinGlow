import {before,after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {verifiedLegacyAssetPatch} from '../legacy-asset-migration.mjs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {ref,set,get,update,serverTimestamp,query,orderByChild,equalTo,limitToFirst} from 'firebase/database';
import {doc,setDoc,getDoc,updateDoc,collection,getDocs,query as fsQuery,where} from 'firebase/firestore';

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
