// 🔥 CRITICAL FIX: Run this in Firebase Console → Firestore → Database → Console
// This script fixes auth_uid mismatch for all users

// Copy and paste this entire script into the Firebase Console browser console
// Then run: fixAllAuthUid()

async function fixAllAuthUid() {
  console.log('🔥 Starting auth_uid mismatch fix...');
  
  try {
    const db = firebase.firestore();
    const batchSize = 50;
    
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    const totalUsers = usersSnapshot.size;
    console.log(`📊 Found ${totalUsers} users to process`);
    
    let fixedCount = 0;
    let skippedCount = 0;
    let errorCount = 0;
    
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
          'updated_at': firebase.firestore.FieldValue.serverTimestamp()
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
    
    // Verify a few random users
    console.log('\n🔍 VERIFICATION - Checking random users:');
    const verifyCount = Math.min(5, usersSnapshot.size);
    for (let i = 0; i < verifyCount; i++) {
      const randomIndex = Math.floor(Math.random() * usersSnapshot.size);
      const userDoc = usersSnapshot.docs[randomIndex];
      const userId = userDoc.id;
      const userData = userDoc.data();
      
      console.log(`👤 User ${userId}: auth_uid = "${userData.auth_uid}" ${userData.auth_uid === userId ? '✅' : '❌'}`);
    }
    
  } catch (error) {
    console.error('💥 Fatal error during auth_uid fix:', error);
  }
}

// Also provide a single user fix function
async function fixSingleAuthUid(userId) {
  console.log(`🔧 Fixing auth_uid for user: ${userId}`);
  
  try {
    const db = firebase.firestore();
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      console.error(`❌ User ${userId} not found`);
      return;
    }
    
    const userData = userDoc.data();
    const currentAuthUid = userData.auth_uid;
    
    if (currentAuthUid === userId) {
      console.log(`⏭️  User ${userId} already has correct auth_uid`);
      return;
    }
    
    await db.collection('users').doc(userId).update({
      'auth_uid': userId,
      'updated_at': firebase.firestore.FieldValue.serverTimestamp()
    });
    
    console.log(`✅ Fixed ${userId}: auth_uid "${currentAuthUid}" → "${userId}"`);
    
  } catch (error) {
    console.error(`❌ Failed to fix ${userId}:`, error);
  }
}

console.log('🚀 Auth UID Fix Script Loaded!');
console.log('📝 Available functions:');
console.log('  fixAllAuthUid() - Fix all users');
console.log('  fixSingleAuthUid(userId) - Fix single user');
console.log('\n🔥 USAGE: fixAllAuthUid()');
