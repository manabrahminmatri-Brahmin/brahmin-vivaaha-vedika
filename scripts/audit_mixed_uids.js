/**
 * AUDIT SCRIPT: Detect Mixed UID Types in Firestore (Read-Only)
 * 
 * This script scans the interests collection and reports:
 *   - How many documents have correct Auth UIDs
 *   - How many have mixed/wrong IDs
 *   - Which specific documents need fixing
 * 
 * Run: node scripts/audit_mixed_uids.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json'); // Download from Firebase Console

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const isAuthUid = (id) => {
  return id && id.length === 28 && /^[a-zA-Z0-9_-]+$/.test(id);
};

const getAuthUidFromUserDoc = async (userId) => {
  try {
    // If it's already an Auth UID, return it
    if (isAuthUid(userId)) {
      return { authUid: userId, found: true };
    }

    // Try to get the user document
    const userDoc = await db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      const authUid = userDoc.data().auth_uid;
      if (authUid && isAuthUid(authUid)) {
        return { authUid, found: true };
      }
    }

    // Try querying by auth_uid field
    const snapshot = await db.collection('users')
      .where('auth_uid', '==', userId)
      .limit(1)
      .get();
    if (!snapshot.empty) {
      const authUid = snapshot.docs[0].data().auth_uid;
      if (authUid && isAuthUid(authUid)) {
        return { authUid, found: true };
      }
    }

    return { authUid: null, found: false };
  } catch (e) {
    return { authUid: null, found: false, error: e.message };
  }
};

const auditInterestsCollection = async () => {
  console.log('🔍 AUDIT: Scanning interests collection for mixed UIDs...\n');
  
  const interestsRef = db.collection('interests');
  const snapshot = await interestsRef.get();
  
  let stats = {
    total: 0,
    correct: 0,
    fromUidWrong: 0,
    toUidWrong: 0,
    bothWrong: 0,
    fromResolvable: 0,
    toResolvable: 0,
    fromUnresolvable: 0,
    toUnresolvable: 0
  };

  const problems = [];

  for (const doc of snapshot.docs) {
    stats.total++;
    const data = doc.data();
    const docId = doc.id;
    
    const fromUid = data.from_user_id;
    const toUid = data.to_user_id;
    
    const fromCorrect = isAuthUid(fromUid);
    const toCorrect = isAuthUid(toUid);
    
    if (fromCorrect && toCorrect) {
      stats.correct++;
      continue;
    }
    
    // Check resolvability
    const fromResult = !fromCorrect ? await getAuthUidFromUserDoc(fromUid) : { found: true };
    const toResult = !toCorrect ? await getAuthUidFromUserDoc(toUid) : { found: true };
    
    if (!fromCorrect) {
      if (fromResult.found) stats.fromResolvable++;
      else stats.fromUnresolvable++;
    }
    
    if (!toCorrect) {
      if (toResult.found) stats.toResolvable++;
      else stats.toUnresolvable++;
    }
    
    if (!fromCorrect && !toCorrect) stats.bothWrong++;
    if (!fromCorrect) stats.fromUidWrong++;
    if (!toCorrect) stats.toUidWrong++;
    
    problems.push({
      docId,
      fromUid,
      toUid,
      fromCorrect,
      toCorrect,
      fromResolvable: fromResult.found,
      toResolvable: toResult.found,
      status: data.status,
      createdAt: data.created_at
    });
  }
  
  // Print detailed problems
  if (problems.length > 0) {
    console.log('📋 PROBLEMATIC DOCUMENTS:\n');
    problems.forEach((p, i) => {
      console.log(`${i + 1}. Document: ${p.docId}`);
      console.log(`   from_user_id: ${p.fromUid} ${p.fromCorrect ? '✅' : '❌'} ${!p.fromCorrect ? (p.fromResolvable ? '(fixable)' : '❌❌ unresolvable') : ''}`);
      console.log(`   to_user_id: ${p.toUid} ${p.toCorrect ? '✅' : '❌'} ${!p.toCorrect ? (p.toResolvable ? '(fixable)' : '❌❌ unresolvable') : ''}`);
      console.log(`   status: ${p.status}, created: ${p.createdAt}`);
      console.log('');
    });
  }
  
  console.log('\n📊 AUDIT SUMMARY:');
  console.log(`Total documents scanned: ${stats.total}`);
  console.log(`Already correct: ${stats.correct} (${((stats.correct/stats.total)*100).toFixed(1)}%)`);
  console.log(`Need fixing: ${problems.length} (${((problems.length/stats.total)*100).toFixed(1)}%)`);
  console.log('');
  console.log('Breakdown:');
  console.log(`  from_user_id wrong: ${stats.fromUidWrong}`);
  console.log(`    - Resolvable: ${stats.fromResolvable}`);
  console.log(`    - Unresolvable: ${stats.fromUnresolvable}`);
  console.log(`  to_user_id wrong: ${stats.toUidWrong}`);
  console.log(`    - Resolvable: ${stats.toResolvable}`);
  console.log(`    - Unresolvable: ${stats.toUnresolvable}`);
  console.log(`  Both wrong: ${stats.bothWrong}`);
  
  if (stats.fromUnresolvable > 0 || stats.toUnresolvable > 0) {
    console.log('\n⚠️ WARNING: Some UIDs are unresolvable!');
    console.log('   These documents may need manual intervention.');
  }
  
  console.log('\n✅ Audit complete!');
  process.exit(0);
};

// Run the audit
auditInterestsCollection().catch(err => {
  console.error('Audit failed:', err);
  process.exit(1);
});
