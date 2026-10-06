// The manifest is administrator-confirmed ownership, not inferred from public
// historical fields. Refuse conflicts instead of transferring an existing asset.
export function verifiedLegacyAssetPatch(data,ownerUid){
  if(typeof ownerUid!=='string'||!ownerUid)throw Error('Invalid manifest owner UID');
  if(data.isDefault===true)throw Error('Default assets cannot become private assets');
  if(data.ownerUid && data.ownerUid!==ownerUid)throw Error('Canonical asset owner mismatch');
  if(!data.ownerUid && data.userId!==ownerUid)throw Error('Legacy asset owner mismatch; repair the manifest/source first');
  return {ownerUid,isDefault:false};
}
