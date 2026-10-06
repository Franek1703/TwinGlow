import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
for(const [command,args,cwd] of [
  ['python3',['tools/firebaseclient-patch/test.py'],fileURLToPath(new URL('..',import.meta.url))],
  ['bash',['tools/native-pairing/test.sh'],fileURLToPath(new URL('..',import.meta.url))],
  [process.execPath,['--test','test/pairing.test.mjs'],fileURLToPath(new URL('.',import.meta.url))],
  ['flutter',['test','test/pairing_emulator_test.dart'],fileURLToPath(new URL('../twin_glow',import.meta.url))],
]) {
  const result=spawnSync(command,args,{cwd,stdio:'inherit',env:process.env});
  if(result.error)throw result.error;
  if(result.status!==0)process.exit(result.status??1);
}
