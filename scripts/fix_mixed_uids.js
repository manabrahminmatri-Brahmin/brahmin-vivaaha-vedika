/**
 * CRITICAL DATA MIGRATION: Fix Mixed UID Types in Firestore
 * 
 * Problem: Database contains mixed ID types:
 *   - from_user_id: "AUTH_UID_A" (correct) or "DOC_ID_A" (wrong)
 *   - to_user_id: "AUTH_UID_B" (correct) or "DOC_ID_B" (wrong)
 * 
 * This causes:
 *   - Wrong UI display ("A instead of B")
 *   - Ghost notifications (wrong user receives interest)
 *   - Query mismatches (interests not showing up)
 * 
 * Solution: Convert ALL from_user_id and to_user_id to Firebase Auth UIDs
 * 
 * Run: node scripts/fix_mixed_uids.js
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
      return { auth_uid: userId, found: true };
    }

    // Try to get the user document
    const userDoc = await db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      const authUid = userDoc.data().auth_uid;
      if (authUid && isAuthUid(authUid)) {
        return { auth_uid: authUid, found: true, source: 'auth_uid field' };
      }
      // If no auth_uid, check if the document ID is an Auth UID
      if (isAuthUid(userDoc.id)) {
        return { auth_uid: userDoc.id, found: true, source: 'doc id' };
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
        return { auth_uid: authUid, found: true, source: 'auth_uid query' };
      }
    }

    return { auth_uid: null, found: false };
  } catch (e) {
    console.error(`Error getting Auth UID for ${userId}:`, e);
    return { auth_uid: null, found: false, error: e.message };
  }
};

const fixInterestsCollection = async () => {
  console.log('🔍 Scanning interests collection for mixed UIDs...\n');
  
  const interestsRef = db.collection('interests');
  const snapshot = await interestsRef.get();
  
  let stats = {
    total: 0,
    correct: 0,
    needsFix: 0,
    fixed: 0,
    failed: 0,
    fromUidWrong: 0,
    toUidWrong: 0
  };

  const batch = db.batch();
  let batchCount = 0;
  const BATCH_SIZE = 400; // Firestore batch limit is 500

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
    
    stats.needsFix++;
    if (!fromCorrect) stats.fromUidWrong++;
    if (!toCorrect) stats.toUidWrong++;
    
    console.log(`⚠️ Document ${docId}:`);
    console.log(`  from_user_id: ${fromUid} ${fromCorrect ? '✅' : '❌'}`);
    console.log(`  to_user_id: ${toUid} ${toCorrect ? '✅' : '❌'}`);
    
    // Get correct Auth UIDs
    const fromResult = await getAuthUidFromUserDoc(fromUid);
    const toResult = await getAuthUidFromUserDoc(toUid);
    
    if (!fromResult.found || !toResult.found) {
      console.log(`  ❌ FAILED: Could not resolve UIDs`);
      console.log(`     from: ${fromResult.found ? '✅' : '❌'} ${fromResult.source || ''}`);
      console.log(`     to: ${toResult.found ? '✅' : '❌'} ${toResult.source || ''}`);
      stats.failed++;
      continue;
    }
    
    const newFromUid = fromResult.authUid;
    const newToUid = toResult.authUid;
    const newDocId = `${newFromUid}_${newToUid}`;
    
    console.log(`  🔧 Fixing:`);
    console.log(`    ${fromUid} → ${newFromUid}`);
    console.log(`    ${toUid} → ${newToUid}`);
    console.log(`    doc id: ${docId} → ${newDocId}`);
    
    // Delete old document and create new one with correct IDs
    batch.delete(doc.ref);
    
    const newData = {
      ...data,
      from_user_id: newFromUid,
      to_user_id: newToUid,
      _fixed: true,
      _fixed_at: admin.firestore.FieldValue.serverTimestamp(),
      _original_from_uid: fromUid,
      _original_to_uid: toUid
    };
    
    batch.set(db.collection('interests').doc(newDocId), newData);
    batchCount += 2; // delete + create
    
    stats.fixed++;
    
    // Commit batch when it reaches the limit
    if (batchCount >= BATCH_SIZE) {
      console.log(`\n💾 Committing batch of ${batchCount} operations...`);
      await batch.commit();
      console.log('✅ Batch committed\n');
      batchCount = 0;
    }
  }
  
  // Commit remaining operations
  if (batchCount > 0) {
    console.log(`\n💾 Committing final batch of ${batchCount} operations...`);
    await batch.commit();
    console.log('✅ Final batch committed\n');
  }
  
  console.log('\n📊 SUMMARY:');
  console.log(`Total documents scanned: ${stats.total}`);
  console.log(`Already correct: ${stats.correct}`);
  console.log(`Needed fixing: ${stats.needsFix}`);
  console.log(`  - from_user_id wrong: ${stats.fromUidWrong}`);
  console.log(`  - to_user_id wrong: ${stats.toUidWrong}`);
  console.log(`Successfully fixed: ${stats.fixed}`);
  console.log(`Failed to fix: ${stats.failed}`);
  
  if (stats.failed > 0) {
    console.log('\n⚠️ Some documents could not be fixed. Manual intervention needed.');
    process.exit(1);
  } else {
    console.log('\n✅ All documents fixed successfully!');
    process.exit(0);
  }
};

// Run the migration
fixInterestsCollection().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
