// RTDB has no functions. Generate repeated predicates so the authorization
// invariants have one reviewable definition; commit the generated rules too.
import {writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const val = (base, field) => `${base}.child('${field}').val()`;
const nr = depth => 'newData' + '.parent()'.repeat(depth);
const pair = (base, id) => `${base}.child('pairing/pairs').child(${id})`;
const slot = (base, uid) => `${base}.child('pairing/users').child(${uid})`;
const config = (base, id) => `${base}.child('config').child(${id})`;
const access = id => `root.child('deviceAccess').child(${id})`;
// token is a map, not a RuleDataSnapshot.
const user = "auth != null && auth.token.twinGlowDeviceId == null";
const device = id => `(auth != null && auth.token.twinGlowDeviceId == ${id} && ${val(access(id),'authUid')} == auth.uid && ${val(access(id),'enabled')} == true)`;
const owner = id => `(${user} && ${val(access(id),'ownerUid')} == auth.uid && ${val(access(id),'enabled')} == true)`;
const member = p => `(${user} && (${val(p,'userA')} == auth.uid || ${val(p,'userB')} == auth.uid))`;
const peer = (p, id) => `(${val(p,'deviceA')} == ${id} ? ${val(p,'deviceB')} : ${val(p,'deviceA')})`;
const active = p => `(${val(p,'state')} == 'ACTIVE')`;
const ended = p => `(${val(p,'state')} == 'ENDED')`;
const pairDevice = (p,id) => `(${val(p,'deviceA')} == ${id} || ${val(p,'deviceB')} == ${id})`;
const key = {'.validate': "newData.isString() && newData.val().length > 0 && newData.val().length <= 95 && !newData.val().matches(/[.#$\\[\\]\\/]/)"};
const text = max => ({'.validate': `newData.isString() && newData.val().length <= ${max}`});
const integer = (min,max) => ({'.validate': `newData.isNumber() && newData.val() % 1 == 0 && newData.val() >= ${min} && newData.val() <= ${max}`});
const closed = fields => ({...fields, '$other': {'.validate': false}});
const pendingAt = (base, f, t) => `${base}.child('pairing/pending').child(${f}).child(${t})`;
const invite = (base,id) => `${base}.child('pairing/invites').child(${id})`;
const iOld = invite('root',val('newData','inviteId'));
const createPair = `${user} && !data.exists() && newData.exists() && ${val(iOld,'status')} == 'pending' && ${val(iOld,'toUid')} == auth.uid && ${val(iOld,'createdAt')} + 604800000 > now`;
const endPair = `${member('data')} && ${active('data')} && ${ended('newData')}`;
const immutable = fields => fields.map(f=>`${val('newData',f)} == ${val('data',f)}`).join(' && ');
const pairMembers = ['userA','userB','deviceA','deviceB','userAEmail','userBEmail','inviteId','createdAt','schemaVersion'];
const pairedReader = p => `(${member(p)} || (${device(val(p,'deviceA'))}) || (${device(val(p,'deviceB'))}))`;
const pairShape = `newData.hasChildren(['schemaVersion','userA','userB','deviceA','deviceB','userAEmail','userBEmail','inviteId','state','createdAt'])`;
const newInv = invite(nr(3),val('newData','inviteId'));
const activation = `${val('newData','schemaVersion')} == 1
  && ${val('newData','userA')} == ${val(iOld,'fromUid')}
  && ${val('newData','userB')} == ${val(iOld,'toUid')}
  && ${val('newData','deviceA')} == ${val(iOld,'fromDeviceId')}
  && ${val('newData','userAEmail')} == ${val(iOld,'fromEmail')}
  && ${val('newData','userBEmail')} == ${val(iOld,'toEmail')}
  && ${val(access(val('newData','deviceB')),'ownerUid')} == auth.uid
  && ${val(access(val('newData','deviceB')),'enabled')} == true
  && ${val(access(val('newData','deviceA')),'ownerUid')} == ${val('newData','userA')}
  && ${val(access(val('newData','deviceA')),'enabled')} == true
  && ${val('newData','userA')} != ${val('newData','userB')}
  && ${val('newData','deviceA')} != ${val('newData','deviceB')}
  && ${val('newData','createdAt')} == now
  && !${slot('root',val('newData','userA'))}.exists()
  && !${slot('root',val('newData','userB'))}.exists()
  && !${config('root',val('newData','deviceA'))}.child('pair').exists()
  && !${config('root',val('newData','deviceB'))}.child('pair').exists()
  && ${slot(nr(3),val('newData','userA'))}.val() == $pairId
  && ${slot(nr(3),val('newData','userB'))}.val() == $pairId
  && ${val(config(nr(3),val('newData','deviceA')),'pair/pairId')} == $pairId
  && ${val(config(nr(3),val('newData','deviceB')),'pair/pairId')} == $pairId
  && ${val(config(nr(3),val('newData','deviceA')),'pair/partnerDeviceId')} == ${val('newData','deviceB')}
  && ${val(config(nr(3),val('newData','deviceB')),'pair/partnerDeviceId')} == ${val('newData','deviceA')}
  && ${val(newInv,'status')} == 'accepted' && ${val(newInv,'pairId')} == $pairId`;
const deactivation = `${immutable(pairMembers)} && ${val('newData','endedAt')} == now
  && ${slot(nr(3),val('data','userA'))}.val() != $pairId
  && ${slot(nr(3),val('data','userB'))}.val() != $pairId
  && ${val(config(nr(3),val('data','deviceA')),'pair/pairId')} != $pairId
  && ${val(config(nr(3),val('data','deviceB')),'pair/pairId')} != $pairId
  && !${nr(3)}.child('pairing/mailboxes').child($pairId).exists()
  && !${nr(3)}.child('pairing/acks').child($pairId).exists()
  && !${config(nr(3),val('data','deviceA'))}.child('incoming').exists()
  && !${config(nr(3),val('data','deviceB'))}.child('incoming').exists()`;
const invF=val('newData','fromUid'), invT=val('newData','toUid');
const invImmutable=['schemaVersion','fromUid','toUid','fromDeviceId','fromEmail','toEmail','createdAt'];
const acceptedPair=pair(nr(3),val('newData','pairId'));
const pendingNew = invite(nr(4), 'newData.val()');
const metaFields=['schemaVersion','eventId','sequence','pairId','senderDeviceId','recipientDeviceId','screenId','assetId','sentAt'];
const metaShape = base => `${base}.hasChildren([${metaFields.map(f=>`'${f}'`).join(',')}])`;
const metaChildren = closed({schemaVersion:{'.validate':'newData.val() == 1'},eventId:key,sequence:integer(1,9007199254740991),pairId:key,senderDeviceId:key,recipientDeviceId:key,screenId:key,assetId:key,sentAt:integer(1,9007199254740991)});
const mailbox= (base,p,id)=>`${base}.child('pairing/mailboxes').child(${p}).child(${id})`;
const mPair=pair('root','$pairId');
const incomingTarget=config(nr(4), val('newData','meta/recipientDeviceId'));
const incomingMatch=metaFields.map(f=>`${val(incomingTarget,`incoming/${f}`)} == ${val('newData',`meta/${f}`)}`).join(' && ');
const incMailbox=mailbox(nr(3),val('newData','pairId'),val('newData','senderDeviceId'));
const incPair=pair('root',val('newData','pairId'));
const currentPair=pair('root',val('data','pairId'));
const clearing = (depth,pid) => `${member(pair('root',pid))} && ${ended(pair(nr(depth),pid))}`;
// A fixed 16-frame ceiling lets rules enforce the total packed size without loops.
const packedLength=`newData.child('basePixelsPacked').val().length` + Array.from({length:15},(_,i)=>` + (newData.child('frameDeltasPacked/${i}').exists() ? newData.child('frameDeltasPacked/${i}').val().length : 0)`).join('');
const packed = max=>({'.validate':`newData.isString() && newData.val().length <= ${max} && newData.val().length % 8 == 0 && newData.val().matches(/^[0-9a-fA-F]*$/)`});
const frameShape=Array.from({length:16},(_,i)=>`(newData.child('frameDurationsMs/${i}').exists() == (newData.child('frameCount').val() > ${i}))`).join(' && ') + ' && '+Array.from({length:15},(_,i)=>`(newData.child('frameDeltasPacked/${i}').exists() == (newData.child('frameCount').val() > ${i+1}))`).join(' && ');
const content = closed({
  '.validate': `(newData.child('type').val() == 'IMAGE' && newData.child('encoding').val() == 'SPARSE_PACKED_V1' && newData.hasChildren(['pixelsPacked']) && !newData.child('basePixelsPacked').exists() && !newData.child('frameDeltasPacked').exists() && !newData.child('frameDurationsMs').exists() && !newData.child('frameCount').exists() && !newData.child('loop').exists()) || (newData.child('type').val() == 'ANIMATION' && newData.child('encoding').val() == 'DELTA_SPARSE_PACKED_V1' && newData.hasChildren(['basePixelsPacked','frameDurationsMs','frameDeltasPacked','frameCount','loop']) && !newData.child('pixelsPacked').exists() && ${frameShape} && (${packedLength}) <= 8192)`,
  type:{'.validate':"newData.val() == 'IMAGE' || newData.val() == 'ANIMATION'"},encoding:text(32),pixelsPacked:packed(2048),basePixelsPacked:packed(2048),
  frameCount:integer(2,16),loop:{'.validate':'newData.val() == true'},
  frameDurationsMs:{'$index':{'.validate':"$index.matches(/^(0|[1-9]|1[0-5])$/) && newData.isNumber() && newData.val() % 1 == 0 && newData.val() >= 50 && newData.val() <= 5000"}},
  frameDeltasPacked:{'$index':{'.validate':`$index.matches(/^(0|[1-9]|1[0-4])$/) && ${packed(2048)['.validate']}`}},
});
const rules={rules:{'.read':false,'.write':false,
  deviceAccess:{'$deviceId':{'.read':`${owner('$deviceId')} || ${device('$deviceId')}`,'.write':false}},
  presence:{'$deviceId':{'.read':`${owner('$deviceId')} || ${device('$deviceId')}`,'.write':device('$deviceId')}},
  telemetry:{'$deviceId':{'.read':`${owner('$deviceId')} || ${device('$deviceId')}`,'.write':device('$deviceId')}},
  commands:{'$deviceId':{'.read':device('$deviceId'),'.write':owner('$deviceId')}},
  config:{'$deviceId':closed({
    '.read':`${owner('$deviceId')} || ${device('$deviceId')}`,
    configVersion:{'.write':owner('$deviceId'),...integer(0,2147483647)},
    pair:closed({
      '.write':`(!data.exists() && newData.exists() && ${user} && ${val(pair(nr(3),val('newData','pairId')),'userB')} == auth.uid && ${active(pair(nr(3),val('newData','pairId')))} && ${pairDevice(pair(nr(3),val('newData','pairId')),'$deviceId')}) || (data.exists() && !newData.exists() && ${clearing(3,val('data','pairId'))})`,
      '.validate':`newData.hasChildren(['pairId','partnerDeviceId']) && ${val('newData','partnerDeviceId')} == ${peer(pair(nr(3),val('newData','pairId')),'$deviceId')}`,
      pairId:key,partnerDeviceId:key}),
    incoming:{
      '.write':`(newData.exists() && ${device(val('newData','senderDeviceId'))} && ${active(incPair)} && ${pairDevice(incPair,'$deviceId')} && ${val('newData','senderDeviceId')} == ${peer(incPair,'$deviceId')}) || (!newData.exists() && ${clearing(3,val(config('root','$deviceId'),'pair/pairId'))})`,
      '.validate':`${metaShape('newData')} && ${val('newData','recipientDeviceId')} == $deviceId && ${metaFields.map(f=>`${val('newData',f)} == ${val(incMailbox,`meta/${f}`)}`).join(' && ')}`,
      ...metaChildren},
  })},
  pairing:{
    directory:{'.indexOn':['email'],'.read':`${user} && query.orderByChild == 'email' && query.equalTo != null && query.limitToFirst == 1`,
      '$uid':closed({'.read':`${user} && auth.uid == $uid`,'.write':`${user} && auth.uid == $uid`,'.validate':"newData.hasChildren(['email']) && newData.child('email').val() == auth.token.email.toLowerCase()",email:text(254),displayName:text(100)})},
    invites:{'.indexOn':['fromUid','toUid'],'.read':`${user} && ((query.orderByChild == 'fromUid' || query.orderByChild == 'toUid') && query.equalTo == auth.uid)`,
      '$inviteId':closed({
        '.read':`${user} && (data.child('fromUid').val() == auth.uid || data.child('toUid').val() == auth.uid)`,
        '.write':`${user} && newData.exists() && ((!data.exists() && ${invF} == auth.uid && ${invT} != auth.uid && ${owner(val('newData','fromDeviceId'))} && ${val('newData','status')} == 'pending') || (data.exists() && ${val('data','status')} == 'pending' && (${val('data','fromUid')} == auth.uid || ${val('data','toUid')} == auth.uid)))`,
        '.validate':`newData.hasChildren(['schemaVersion','fromUid','toUid','fromDeviceId','fromEmail','toEmail','status','createdAt','updatedAt']) && ${val('newData','schemaVersion')} == 1 && ${val('newData','updatedAt')} == now && ((!data.exists() && ${val('newData','createdAt')} == now && ${val('newData','fromEmail')} == auth.token.email.toLowerCase() && ${val('newData','toEmail')} == ${nr(3)}.child('pairing/directory').child(${invT}).child('email').val() && !${slot('root',invF)}.exists() && !${slot('root',invT)}.exists() && ${pendingAt(nr(3),invF,invT)}.val() == $inviteId && !newData.child('pairId').exists()) || (data.exists() && ${immutable(invImmutable)} && !${pendingAt(nr(3),val('data','fromUid'),val('data','toUid'))}.exists() && ((${val('newData','status')} == 'cancelled' && auth.uid == ${val('data','fromUid')}) || (${val('newData','status')} == 'rejected' && auth.uid == ${val('data','toUid')}) || (${val('newData','status')} == 'expired' && ${val('data','createdAt')} + 604800000 <= now) || (${val('newData','status')} == 'accepted' && auth.uid == ${val('data','toUid')} && ${val('data','createdAt')} + 604800000 > now && ${val(acceptedPair,'inviteId')} == $inviteId && ${active(acceptedPair)} && !${pair('root',val('newData','pairId'))}.exists()))))`,
        schemaVersion:integer(1,1),fromUid:key,toUid:key,fromDeviceId:key,fromEmail:text(254),toEmail:text(254),status:text(10),createdAt:integer(1,9007199254740991),updatedAt:integer(1,9007199254740991),pairId:key,
      })},
    pending:{'$fromUid':{'$toUid':{
      '.read':`${user} && (auth.uid == $fromUid || auth.uid == $toUid)`,
      '.write':`${user} && ((!data.exists() && newData.exists() && auth.uid == $fromUid && ${val(pendingNew,'fromUid')} == $fromUid && ${val(pendingNew,'toUid')} == $toUid && ${val(pendingNew,'status')} == 'pending') || (data.exists() && !newData.exists() && (auth.uid == $fromUid || auth.uid == $toUid) && ${val(invite(nr(4),'data.val()'),'status')} != 'pending'))`,
      ...key,
    }}},
    users:{'$uid':{
      '.read':`${user} && auth.uid == $uid`,
      '.write':`${user} && ((!data.exists() && newData.exists() && ${val(pair(nr(3),'newData.val()'),'userB')} == auth.uid && ${active(pair(nr(3),'newData.val()'))} && (${val(pair(nr(3),'newData.val()'),'userA')} == $uid || ${val(pair(nr(3),'newData.val()'),'userB')} == $uid)) || (data.exists() && !newData.exists() && ${clearing(3,'data.val()')}))`,...key,
    }},
    pairs:{'$pairId':closed({
      '.read':pairedReader('data'),'.write':`(${createPair}) || (${endPair})`,
      '.validate':`${pairShape} && ((!data.exists() && ${active('newData')} && ${activation}) || (data.exists() && ${ended('newData')} && ${deactivation}))`,
      schemaVersion:integer(1,1),userA:key,userB:key,deviceA:key,deviceB:key,userAEmail:text(254),userBEmail:text(254),inviteId:key,state:text(6),createdAt:integer(1,9007199254740991),endedAt:integer(1,9007199254740991),
    })},
    mailboxes:{'$pairId':{'.write':`!newData.exists() && ${clearing(3,'$pairId')}`,'$senderDeviceId':closed({
      '.read':`${active(mPair)} && ${pairedReader(mPair)}`,
      '.write':`(newData.exists() && ${device('$senderDeviceId')} && ${active(mPair)} && ${pairDevice(mPair,'$senderDeviceId')}) || (data.exists() && !newData.exists() && ${clearing(4,'$pairId')})`,
      '.validate':`newData.hasChildren(['meta','content']) && ${metaShape("newData.child('meta')")} && ${val('newData','meta/pairId')} == $pairId && ${val('newData','meta/senderDeviceId')} == $senderDeviceId && ${val('newData','meta/recipientDeviceId')} == ${peer(mPair,'$senderDeviceId')} && ${val('newData','meta/sentAt')} == now && (!data.exists() || ${val('newData','meta/sequence')} > ${val('data','meta/sequence')}) && ${incomingMatch}`,
      meta:metaChildren,content,
    })}},
    acks:{'$pairId':{'.write':`!newData.exists() && ${clearing(3,'$pairId')}`,'$receiverDeviceId':closed({
      '.read':`${active(mPair)} && ${pairedReader(mPair)}`,
      '.write':`(newData.exists() && ${device('$receiverDeviceId')} && ${active(mPair)} && ${pairDevice(mPair,'$receiverDeviceId')}) || (data.exists() && !newData.exists() && ${clearing(4,'$pairId')})`,
      '.validate':`newData.hasChildren(['eventId','sequence','status','at']) && ${val('newData','at')} == now && ${val('newData','eventId')} == ${val(config('root','$receiverDeviceId'),'incoming/eventId')} && ${val('newData','sequence')} == ${val(config('root','$receiverDeviceId'),'incoming/sequence')} && (!data.exists() || ${val('newData','sequence')} >= ${val('data','sequence')})`,
      eventId:key,sequence:integer(1,9007199254740991),status:{'.validate':"newData.val() == 'displayed' || newData.val() == 'rejected'"},at:integer(1,9007199254740991),
    })}},
  },
}};
writeFileSync(fileURLToPath(new URL('database.rules.json',import.meta.url)),JSON.stringify(rules,null,2)+'\n');
