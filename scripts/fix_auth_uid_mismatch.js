// 🔥 CRITICAL FIX: Update all users to have auth_uid == documentId
// This fixes the permission-denied errors caused by auth_uid mismatch

const admin = require('firebase-admin');
const serviceAccount = require('../service-account-key.json');

// Initialize Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'manabrahminmatri-de0ad'
});

const db = admin.firestore();
const batchSize = 100; // Process users in batches

async function fixAuthUidMismatch() {
  console.log('🔥 Starting auth_uid mismatch fix...');
  
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    const totalUsers = usersSnapshot.size;
    console.log(`📊 Found ${totalUsers} users to process`);
    
    let fixedCount = 0;
    let errorCount = 0;
    let skippedCount = 0;
    
    // Process in batches
    for (let i = 0; i < totalUsers; i += batchSize) {
      const batch = db.batch();
      const batchUsers = usersSnapshot.docs.slice(i, i + batchSize);
      
      console.log(`🔄 Processing batch ${Math.floor(i/batchSize) + 1}/${Math.ceil(totalUsers/batchSize)} (${batchUsers.length} users)`);
      
      for (const userDoc of batchUsers) {
        const userId = userDoc.id;
        const userData = userDoc.data();
        const currentAuthUid = userData.auth_uid;
        
        // Skip if auth_uid already matches document ID
        if (currentAuthUid === userId) {
          console.log(`⏭️  Skipping ${userId} - auth_uid already matches`);
          skippedCount++;
          continue;
        }
        
        // Update auth_uid to match document ID (Firebase Auth UID)
        console.log(`🔧 Fixing ${userId}: auth_uid "${currentAuthUid}" → "${userId}"`);
        
        const userRef = db.collection('users').doc(userId);
        batch.update(userRef, {
          'auth_uid': userId,
          'updated_at': admin.firestore.FieldValue.serverTimestamp()
        });
        
        fixedCount++;
      }
      
      // Commit batch
      try {
        await batch.commit();
        console.log(`✅ Batch ${Math.floor(i/batchSize) + 1} committed successfully`);
      } catch (error) {
        console.error(`❌ Batch ${Math.floor(i/batchSize) + 1} failed:`, error);
        errorCount++;
      }
    }
    
    console.log('\n🎉 AUTH_UID FIX SUMMARY:');
    console.log(`✅ Fixed: ${fixedCount} users`);
    console.log(`⏭️  Skipped: ${skippedCount} users (already correct)`);
    console.log(`❌ Errors: ${errorCount} batches`);
    console.log(`📊 Total processed: ${totalUsers} users`);
    
  } catch (error) {
    console.error('💥 Fatal error during auth_uid fix:', error);
  } finally {
    process.exit(0);
  }
}

// Run the fix
fixAuthUidMismatch();
