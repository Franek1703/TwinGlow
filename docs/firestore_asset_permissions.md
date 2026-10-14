# Firestore asset permissions

The canonical rules are in `firebase/firestore.rules`; deploy from `firebase/`
with an explicit project and `--only firestore:rules`.

Existing Default assets form a collaborative library: any signed-in human app
account can edit their name, tags and image/animation content. Device accounts
can read defaults but cannot write them. Clients cannot create or delete defaults,
change their owner or type, convert them to private assets, or change sharing ACLs.

Default saves use the app's packed 16×16 encodings, increment `revision` by one
(missing historical revisions start at zero), and clear obsolete pixel fields.
Animations retain the codec limits: 2–16 frames, 50–5000 ms per frame, at most
2048 packed characters per frame/delta and 8192 total. Concurrent editors must
reopen an asset after a revision conflict.

Private assets remain owner-managed. Partners can edit explicitly shared assets
with the existing atomic sharing-pair version notification. Sharing a Default
creates an independent private copy; later library edits do not overwrite that
copy. Device notifications continue to cover the editing user's own devices.

Verify with `npm test` in `firebase/` and the Flutter asset/editor, shared-content,
playlist and device tests. The rule tests exercise both successful app writes
and rejected identity/ACL changes through authenticated client SDKs.
