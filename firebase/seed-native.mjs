import { initializeApp, deleteApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, GoogleAuthProvider, signInWithCredential } from 'firebase/auth';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc } from 'firebase/firestore';

const projectId = 'demo-ftcteamhub';
const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!host || !process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Start both local Firebase emulators first.');

const environment = await initializeTestEnvironment({ projectId });
try {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'workspaces/native-fixture'), { name: 'Wild Circuits simulator', number: 36611 });
    for (const name of ['native-sender', 'native-scout']) {
      const app = initializeApp({ projectId, apiKey: 'demo-emulator-key' }, name);
      try {
        const auth = getAuth(app);
        connectAuthEmulator(auth, 'http://' + host, { disableWarnings: true });
        const credential = GoogleAuthProvider.credential(JSON.stringify({
          sub: name, email: name + '@example.test', email_verified: true, name
        }));
        const { user } = await signInWithCredential(auth, credential);
        await setDoc(doc(db, 'workspaces/native-fixture/members', user.uid), {
          name, role: 'member', active: true, joinedAt: serverTimestamp()
        });
      } finally {
        await deleteApp(app);
      }
    }
  });
} finally {
  await environment.cleanup();
}
