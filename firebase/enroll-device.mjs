// Administrative enrollment; never run by the app or firmware.
// Defaults to dry-run. Requires administrator ADC and an explicit owner mapping.
import {initializeApp,applicationDefault} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getDatabase} from 'firebase-admin/database';
import {getFirestore} from 'firebase-admin/firestore';
import {randomBytes} from 'node:crypto';
import {writeFileSync,existsSync} from 'node:fs';

const args=process.argv.slice(2);
const option=name=>{const i=args.indexOf(name);return i<0?null:args[i+1];};
const projectId=option('--project'),databaseURL=option('--database-url'),deviceId=option('--device'),ownerUid=option('--owner'),output=option('--credential-output');
const apply=args.includes('--apply');
if(!projectId||!databaseURL||!deviceId||!ownerUid||!(/^[A-Za-z0-9_-]{1,95}$/).test(deviceId))throw Error('Usage: node enroll-device.mjs --project PROJECT --database-url URL --device ID --owner UID [--apply --credential-output /absolute/private/DeviceCredentials.h]');
if(apply&&(!output||existsSync(output)))throw Error('A new private credential output path is required; existing files are never overwritten.');
initializeApp({credential:applicationDefault(),projectId,databaseURL});
const auth=getAuth(),db=getDatabase(),fs=getFirestore();
await auth.getUser(ownerUid); // Owner must exist; public device metadata is not proof of ownership.
const ref=db.ref(`deviceAccess/${deviceId}`),binding=(await ref.get()).val();
const firestoreBinding=(await fs.doc(`deviceAccess/${deviceId}`).get()).data();
if(binding&&binding.ownerUid!==ownerUid||firestoreBinding&&firestoreBinding.ownerUid!==ownerUid)throw Error('Owner mismatch; resolve ownership administratively before enrollment.');
if(binding&&firestoreBinding&&binding.authUid!==firestoreBinding.authUid)throw Error('Registry mismatch; repair it before enrollment.');
console.log(JSON.stringify({projectId,deviceId,ownerUid,action:binding?'rotate-device-credential':'enroll-device',apply},null,2));
if(!apply)process.exit(0);
const password=randomBytes(30).toString('base64url');
let account;
if(binding||firestoreBinding){
  account=await auth.getUser((binding||firestoreBinding).authUid);
  if(account.customClaims?.twinGlowDeviceId!==deviceId||!account.email)throw Error('Existing Auth account is not a matching device identity.');
  await auth.updateUser(account.uid,{password,disabled:false});
}else{
  account=await auth.createUser({email:`twinglow-${randomBytes(16).toString('hex')}@devices.twinglow.invalid`,password,emailVerified:true});
  await auth.setCustomUserClaims(account.uid,{twinGlowDeviceId:deviceId});
}
const record={authUid:account.uid,ownerUid,enabled:true};
// Either registry missing denies that service. Rerunning repairs an interrupted enrollment.
await fs.doc(`deviceAccess/${deviceId}`).set(record);
await ref.set(record);
writeFileSync(output,`#pragma once\n#define FIREBASE_DEVICE_EMAIL ${JSON.stringify(account.email)}\n#define FIREBASE_DEVICE_PASSWORD ${JSON.stringify(password)}\n`,{mode:0o600,flag:'wx'});
console.log('Enrollment complete; credentials written privately. Install only on the enrolled device.');
