import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { assertFails, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp } from 'firebase/app';
import { connectAuthEmulator, GoogleAuthProvider, getAuth, signInWithCredential } from 'firebase/auth';
import { collection, connectFirestoreEmulator, disableNetwork, doc, enableNetwork, getDoc, getDocs, getFirestore, onSnapshot,
  query, orderBy, limit, serverTimestamp, setDoc, updateDoc, writeBatch } from 'firebase/firestore';

const google = (email) => ({ email, name: email.split('@')[0], email_verified: true, firebase: { sign_in_provider: 'google.com' } });
const id = () => randomUUID().toUpperCase();
const team = 'wild-circuits-sim';
const otherTeam = 'other-workspace';
const memberPath = (teamID, uid) => 'workspaces/' + teamID + '/members/' + uid;
const membershipPath = (uid) => 'workspaceUsers/' + uid + '/memberships/' + team;
const invitationPath = (address) => 'workspaces/' + team + '/invites/' + address;
const taskPath = (key) => 'workspaces/' + team + '/records/task:' + key;
const messagePath = (key) => 'workspaces/' + team + '/messages/' + key;
const announcementPath = (key) => 'workspaces/' + team + '/announcements/' + key;

let environment;
let leader;
let scout;
let outsider;
let viewer;

function observed(target, predicate) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      unsubscribe();
      reject(new Error('Timed out waiting for a server snapshot'));
    }, 100000);
    const unsubscribe = onSnapshot(target, { includeMetadataChanges: true }, (value) => {
      if (!value.metadata.fromCache && !value.metadata.hasPendingWrites && predicate(value)) {
        clearTimeout(timeout);
        unsubscribe();
        resolve(value);
      }
    }, (error) => {
      clearTimeout(timeout);
      unsubscribe();
      reject(error);
    });
  });
}

function record({ key, actor, kind, fields, revision = id(), prior = '', author = actor }) {
  return { kind, key, author, actor, revision, prior, deleted: false,
    updatedAt: serverTimestamp(), data: fields };
}

async function inviteAndJoin(email, uid, role, db) {
  const path = invitationPath(email);
  await setDoc(doc(leader, path), { role, active: true, invitedBy: 'mentor', invitedAt: serverTimestamp() });
  const invitation = await getDoc(doc(db, path));
  assert.equal(invitation.data().role, role);
  const batch = writeBatch(db);
  batch.set(doc(db, memberPath(team, uid)), { name: uid, role, active: true, joinedAt: serverTimestamp() });
  batch.set(doc(db, membershipPath(uid)), { joinedAt: serverTimestamp() });
  batch.update(doc(db, path), { active: false, acceptedBy: uid });
  await batch.commit();
}

before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-ftcteamhub' });
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'workspaces', team), { name: 'Wild Circuits', number: 36611 });
    await setDoc(doc(db, 'workspaces', otherTeam), { name: 'Other team', number: 12345 });
    await setDoc(doc(db, memberPath(team, 'mentor')), { name: 'Mentor', active: true, role: 'admin', joinedAt: serverTimestamp() });
    await setDoc(doc(db, memberPath(otherTeam, 'outsider')), { name: 'Outsider', active: true, role: 'member', joinedAt: serverTimestamp() });
  });
  leader = environment.authenticatedContext('mentor', google('mentor@example.test')).firestore();
  scout = environment.authenticatedContext('scout', google('scout@example.test')).firestore();
  outsider = environment.authenticatedContext('outsider', google('outsider@example.test')).firestore();
  viewer = environment.authenticatedContext('viewer', google('viewer@example.test')).firestore();
});

after(async () => { if (environment) await environment.cleanup(); });

async function googleSession(name, email) {
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
  assert.ok(authHost && firestoreHost, 'Run this test with both Firebase emulators');
  const app = initializeApp({ projectId: 'demo-ftcteamhub', apiKey: 'demo-emulator-key' }, name);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://' + authHost, { disableWarnings: true });
  const credential = GoogleAuthProvider.credential(JSON.stringify({
    sub: name, email, email_verified: true, name
  }));
  const result = await signInWithCredential(auth, credential);
  const token = await result.user.getIdTokenResult();
  assert.equal(token.signInProvider, 'google.com');
  assert.equal(token.claims.email_verified, true);
  const db = getFirestore(app);
  const [host, port] = firestoreHost.split(':');
  connectFirestoreEmulator(db, host, Number(port));
  return { app, db, uid: result.user.uid };
}

test('isolated Google identities accept email invitations without client-side privilege changes', async () => {
  await assertFails(getDoc(doc(scout, 'workspaces', team)));
  await assertFails(getDocs(collection(outsider, 'workspaces', team, 'records')));
  await assertFails(setDoc(doc(outsider, memberPath(team, 'outsider')), {
    name: 'Outsider', role: 'admin', active: true, joinedAt: serverTimestamp()
  }));
  await assertFails(setDoc(doc(scout, membershipPath('scout')), { joinedAt: serverTimestamp() }));
  await inviteAndJoin('scout@example.test', 'scout', 'scout', scout);
  await inviteAndJoin('viewer@example.test', 'viewer', 'viewer', viewer);
  assert.equal((await getDoc(doc(scout, 'workspaces', team))).data().number, 36611);
  assert.equal((await getDoc(doc(scout, membershipPath('scout')))).exists(), true);
  await assertFails(getDoc(doc(scout, 'workspaces', otherTeam)));
  await assertFails(getDoc(doc(outsider, invitationPath('scout@example.test'))));
  await assertFails(updateDoc(doc(scout, memberPath(team, 'scout')), { role: 'admin' }));
});

test('two Auth emulator sessions receive chat and tasks live and replay an offline update', async (context) => {
  const sender = await googleSession('Sender', 'sender@example.test');
  const scoutSession = await googleSession('Scout', 'second-scout@example.test');
  context.after(async () => { await Promise.all([deleteApp(sender.app), deleteApp(scoutSession.app)]); });
  const teamPath = 'workspaces/' + team;
  await environment.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    await setDoc(doc(db, memberPath(team, sender.uid)),
      { name: 'Sender', active: true, role: 'mentor', joinedAt: serverTimestamp() });
    await setDoc(doc(db, memberPath(team, scoutSession.uid)),
      { name: 'Scout', active: true, role: 'scout', joinedAt: serverTimestamp() });
  });
  const chatID = id();
  const inbox = query(collection(scoutSession.db, teamPath, 'messages'), orderBy('createdAt', 'desc'), limit(40));
  const received = observed(inbox, (snap) => snap.docs.some((item) => item.id === chatID));
  await setDoc(doc(sender.db, messagePath(chatID)), { text: 'Meet in the pit for Q14.', sender: sender.uid, createdAt: serverTimestamp() });
  const inboxSnapshot = await received;
  assert.equal(inboxSnapshot.docs[0].data().sender, sender.uid);
  assert.ok(inboxSnapshot.docs[0].data().createdAt.toMillis() > 0);
  await assertFails(setDoc(doc(scout, messagePath(chatID)), { text: 'Different message', sender: 'scout', createdAt: serverTimestamp() }));
  await assertFails(setDoc(doc(scout, messagePath(id())), { text: 'Wrong identity', sender: 'mentor', createdAt: serverTimestamp() }));
  await assertFails(setDoc(doc(viewer, messagePath(id())), { text: 'Read only', sender: 'viewer', createdAt: serverTimestamp() }));
  await assertFails(setDoc(doc(scout, announcementPath(id())), { text: 'Not a coordinator', sender: 'scout', createdAt: serverTimestamp() }));
  await setDoc(doc(leader, announcementPath(id())), { text: 'Move to queue 2', sender: 'mentor', createdAt: serverTimestamp() });

  const key = id();
  const first = record({ kind: 'task', key, actor: sender.uid,
    fields: { id: key, title: 'Check the drivetrain', assignedToID: scoutSession.uid, status: 'todo', priority: 'medium' } });
  const created = observed(doc(scoutSession.db, taskPath(key)), (snapshot) => snapshot.exists());
  await setDoc(doc(sender.db, taskPath(key)), first);
  assert.equal((await created).data().data.status, 'todo');

  const second = record({ kind: 'task', key, actor: scoutSession.uid, prior: first.revision,
    fields: { ...first.data, status: 'inProgress' } });
  const updated = observed(doc(sender.db, taskPath(key)), (snapshot) => snapshot.data()?.revision === second.revision);
  await setDoc(doc(scoutSession.db, taskPath(key)), second);
  assert.equal((await updated).data().data.status, 'inProgress');
  await assertFails(setDoc(doc(sender.db, taskPath(key)), record({ kind: 'task', key, actor: sender.uid,
    prior: first.revision, fields: { ...first.data, status: 'blocked' } })));

  await disableNetwork(scoutSession.db);
  const last = record({ kind: 'task', key, actor: scoutSession.uid, prior: second.revision, fields: { ...first.data, status: 'done' } });
  const finished = observed(doc(sender.db, taskPath(key)), (snapshot) => snapshot.data()?.revision === last.revision);
  const queued = setDoc(doc(scoutSession.db, taskPath(key)), last);
  assert.equal((await getDoc(doc(leader, taskPath(key)))).data().data.status, 'inProgress');
  await enableNetwork(scoutSession.db);
  await queued;
  assert.equal((await finished).data().data.status, 'done');
  await assertFails(getDoc(doc(outsider, taskPath(key))));
});

test('scouting keys, votes and revocation remain enforced', async () => {
  const matchKey = '2026:USNJSOM3:13';
  const key = matchKey + ':12345:scout';
  const fields = { identity: key, matchKey, eventCode: 'USNJSOM3', team: 12345, matchLabel: 'Q13',
    author: 'scout', season: 2026, providerID: 13, schemaVersion: 1, submittedAt: Date.now(), autoHiveTips: 2 };
  const report = record({ kind: 'matchReport', key, actor: 'scout', fields });
  const reportRef = doc(scout, 'workspaces', team, 'records', 'matchReport:' + key);
  await setDoc(reportRef, report);
  await assertFails(setDoc(reportRef, { ...report, revision: id() }));
  await assertFails(setDoc(reportRef, record({ kind: 'matchReport', key, actor: 'scout',
    prior: report.revision, fields: { ...fields, autoHiveTips: -1 } })));

  const ideaID = id();
  await setDoc(doc(leader, 'workspaces', team, 'records', 'idea:' + ideaID), record({
    kind: 'idea', key: ideaID, actor: 'mentor', fields: { id: ideaID, authorID: 'mentor', title: 'Practice starts', body: '', upvotes: 0 }
  }));
  const vote = { ideaID, uid: 'scout', active: true, updatedAt: serverTimestamp() };
  const votePath = 'workspaces/' + team + '/votes/' + ideaID;
  await setDoc(doc(scout, votePath + ':scout'), vote);
  await assertFails(setDoc(doc(scout, votePath + ':mentor'), { ...vote, uid: 'mentor' }));
  await setDoc(doc(scout, votePath + ':scout'), { ...vote, active: false });

  await updateDoc(doc(leader, memberPath(team, 'scout')), { active: false });
  await assertFails(getDocs(collection(scout, 'workspaces', team, 'records')));
  await assertFails(setDoc(doc(scout, messagePath(id())), { text: 'Revoked', sender: 'scout', createdAt: serverTimestamp() }));
});

test('inventory changes require an atomic, attributed quantity history', async () => {
  const key = id();
  const ref = doc(leader, 'workspaces', team, 'records', 'inventory:' + key);
  const fields = { id: key, name: 'M3 locknuts', status: 'ok', quantity: 12, lowStockThreshold: 4 };
  const first = record({ kind: 'inventory', key, actor: 'mentor', fields });
  await assertFails(setDoc(ref, first));
  async function applyStockChange(value, before, after) {
    const batch = writeBatch(leader);
    batch.set(ref, value);
    batch.set(doc(ref, 'stockChanges', value.revision),
      { actor: 'mentor', before, after, createdAt: serverTimestamp() });
    await batch.commit();
  }
  await applyStockChange(first, 0, 12);
  const second = record({ kind: 'inventory', key, actor: 'mentor', prior: first.revision, fields: { ...fields, quantity: 8 } });
  await assertFails(applyStockChange(second, 0, 8));
  await applyStockChange(second, 12, 8);
  const history = await getDocs(collection(ref, 'stockChanges'));
  assert.equal(history.size, 2);
  assert.equal((await getDoc(doc(leader, ref.path + '/stockChanges/' + second.revision))).data().before, 12);
  await assertFails(getDocs(collection(outsider, ref.path, 'stockChanges')));
});
