// 🔥 CRITICAL FIX: Cloud Function to update all users with correct auth_uid
// This fixes permission-denied errors caused by auth_uid mismatch

const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

exports.fixAuthUidMismatch = functions.https.onCall(async (data, context) => {
  // Only allow admin users to run this fix
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Authentication required'
    );
  }

  // Check if caller is admin
  const callerUid = context.auth.uid;
  const callerDoc = await admin.firestore().collection('users').doc(callerUid).get();
  
  if (!callerDoc.exists || !callerDoc.data()?.is_admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Admin access required'
    );
  }

  console.log('🔥 Starting auth_uid mismatch fix...');
  
  try {
    const db = admin.firestore();
    const batchSize = 50; // Process users in smaller batches for Cloud Functions
    
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    const totalUsers = usersSnapshot.size;
    console.log(`📊 Found ${totalUsers} users to process`);
    
    let fixedCount = 0;
    let skippedCount = 0;
    const results = [];
    
    // Process in batches
    for (let i = 0; i < totalUsers; i += batchSize) {
      const batch = db.batch();
      const batchUsers = usersSnapshot.docs.slice(i, i + batchSize);
      
      console.log(`🔄 Processing batch ${Math.floor(i/batchSize) + 1}/${Math.ceil(totalUsers/batchSize)}`);
      
      for (const userDoc of batchUsers) {
        const userId = userDoc.id;
        const userData = userDoc.data();
        const currentAuthUid = userData.auth_uid;
        
        // Skip if auth_uid already matches document ID
        if (currentAuthUid === userId) {
          console.log(`⏭️  Skipping ${userId} - already correct`);
          skippedCount++;
          continue;
        }
        
        // Update auth_uid to match document ID (Firebase Auth UID)
        console.log(`🔧 Fixing ${userId}: "${currentAuthUid}" → "${userId}"`);
        
        const userRef = db.collection('users').doc(userId);
        batch.update(userRef, {
          'auth_uid': userId,
          'updated_at': admin.firestore.FieldValue.serverTimestamp()
        });
        
        results.push({
          userId: userId,
          oldAuthUid: currentAuthUid,
          newAuthUid: userId
        });
        
        fixedCount++;
      }
      
      // Commit batch
      await batch.commit();
      console.log(`✅ Batch ${Math.floor(i/batchSize) + 1} committed`);
    }
    
    console.log('\n🎉 AUTH_UID FIX SUMMARY:');
    console.log(`✅ Fixed: ${fixedCount} users`);
    console.log(`⏭️  Skipped: ${skippedCount} users`);
    console.log(`📊 Total processed: ${totalUsers} users`);
    
    return {
      success: true,
      message: `Fixed auth_uid for ${fixedCount} users, skipped ${skippedCount} users`,
      totalUsers: totalUsers,
      fixedCount: fixedCount,
      skippedCount: skippedCount,
      results: results
    };
    
  } catch (error) {
    console.error('💥 Fatal error during auth_uid fix:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to fix auth_uid mismatch: ' + error.message
    );
  }
});
