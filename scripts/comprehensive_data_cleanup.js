// 🔥 COMPREHENSIVE DATA CLEANUP - Fix ALL schema inconsistencies
// Run this in Firebase Console → Firestore → Database → Console
// Then run: comprehensiveCleanup()

async function comprehensiveCleanup() {
  console.log('🔥 Starting comprehensive data cleanup...');
  
  try {
    const db = firebase.firestore();
    const batchSize = 20; // Smaller batches for complex updates
    
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
        const data = userDoc.data();
        
        console.log(`\n🔧 Processing user: ${userId}`);
        
        // Build cleaned data object
        const cleanedData = {};
        const fieldsToDelete = [];
        
        // 🔴 1. FIX IDENTITY FIELDS
        // Keep: auth_uid, profile_id
        // Remove: firebase_uid, id
        
        if (data.auth_uid && data.auth_uid !== userId) {
          cleanedData.auth_uid = userId; // Fix auth_uid to match document ID
          console.log(`  📝 Fix auth_uid: ${data.auth_uid} → ${userId}`);
        }
        
        if (data.profile_id) {
          cleanedData.profile_id = data.profile_id;
        }
        
        fieldsToDelete.push('firebase_uid', 'id');
        
        // 🔴 2. CONSOLIDATE PROFILE DATA
        // Move all root-level fields into profile object
        const profile = {};
        
        // Fields to move to profile object
        const profileFields = [
          'first_name', 'last_name', 'date_of_birth', 'gender', 'city', 
          'state', 'country', 'education', 'occupation', 'about_me',
          'family_background', 'mother_tongue', 'family_values', 
          'family_status', 'family_type', 'family_income', 'father_occupation',
          'mother_occupation', 'brothers', 'sisters', 'married_brothers',
          'married_sisters', 'height', 'weight', 'complexion', 'body_type',
          'physical_status', 'diet', 'smoking', 'drinking', 'religion',
          'caste', 'sub_caste', 'star', 'raasi', 'horoscope_match'
        ];
        
        profileFields.forEach(field => {
          if (data[field] !== undefined) {
            profile[field] = data[field];
            fieldsToDelete.push(field);
          }
        });
        
        // Handle photo fields (consolidate to photo_url)
        const photoFields = ['profile_picture', 'profilePicture', 'photo_url', 'photoUrl'];
        photoFields.forEach(field => {
          if (data[field] !== undefined && data[field] !== null && data[field] !== '') {
            profile.photo_url = data[field];
            fieldsToDelete.push(field);
          }
        });
        
        // Handle photo privacy (consolidate to is_photo_private)
        const privacyFields = ['is_photo_private', 'isPhotoPrivate'];
        privacyFields.forEach(field => {
          if (data[field] !== undefined) {
            profile.is_photo_private = data[field];
            fieldsToDelete.push(field);
          }
        });
        
        if (Object.keys(profile).length > 0) {
          cleanedData.profile = profile;
          console.log(`  📝 Built profile object with ${Object.keys(profile).length} fields`);
        }
        
        // 🔴 3. CONSOLIDATE MEMBERSHIP DATA
        // Keep only membership_json, remove others
        if (data.membership_json) {
          cleanedData.membership_json = data.membership_json;
          fieldsToDelete.push('membership_tier', 'membership_status', 
                            'membership_start_date', 'membership_expires_at', 
                            'membership_expiry_date');
        }
        
        // 🔴 4. FIX DATE FORMATS
        // Convert string dates to timestamps
        if (data.last_active && typeof data.last_active === 'string') {
          try {
            cleanedData.last_active = new Date(data.last_active);
            console.log(`  📝 Fixed last_active date format`);
          } catch (e) {
            console.log(`  ⚠️ Could not parse last_active date: ${data.last_active}`);
          }
        }
        
        // Keep existing timestamp fields
        ['created_at', 'updated_at'].forEach(field => {
          if (data[field] !== undefined) {
            cleanedData[field] = data[field];
          }
        });
        
        // 🔴 5. KEEP ESSENTIAL FIELDS
        const keepFields = [
          'is_online', 'status', 'is_deleted', 'is_admin', 'is_premium',
          'likes_sent', 'likes_received', 'interests_sent', 'interests_received',
          'liked_users', 'liked_by', 'mobile_number', 'email'
        ];
        
        keepFields.forEach(field => {
          if (data[field] !== undefined) {
            cleanedData[field] = data[field];
          }
        });
        
        // Apply updates and deletions
        if (Object.keys(cleanedData).length > 0) {
          batch.update(userDoc.ref, cleanedData);
          console.log(`  ✅ Updating ${Object.keys(cleanedData).length} fields`);
        }
        
        if (fieldsToDelete.length > 0) {
          // Remove undefined/null fields from deletion list
          const validDeletions = fieldsToDelete.filter(field => data[field] !== undefined);
          if (validDeletions.length > 0) {
            const deleteObj = {};
            validDeletions.forEach(field => {
              deleteObj[field] = firebase.firestore.FieldValue.delete();
            });
            batch.update(userDoc.ref, deleteObj);
            console.log(`  🗑️ Deleting ${validDeletions.length} fields: ${validDeletions.join(', ')}`);
          }
        }
        
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
    
    console.log('\n🎉 COMPREHENSIVE CLEANUP SUMMARY:');
    console.log(`✅ Fixed: ${fixedCount} users`);
    console.log(`⏭️  Skipped: ${skippedCount} users`);
    console.log(`❌ Errors: ${errorCount} batches`);
    console.log(`📊 Total processed: ${totalUsers} users`);
    
    // Verify cleanup
    console.log('\n🔍 VERIFICATION - Checking first 3 users:');
    await verifyCleanup();
    
  } catch (error) {
    console.error('💥 Fatal error during cleanup:', error);
  }
}

// Verification function
async function verifyCleanup() {
  console.log('🔍 Verifying cleanup results...');
  
  try {
    const db = firebase.firestore();
    const users = await db.collection('users').limit(3).get();
    
    users.forEach(doc => {
      const userId = doc.id;
      const data = doc.data();
      
      console.log(`\n👤 User: ${userId}`);
      console.log(`  ✅ auth_uid: ${data.auth_uid} ${data.auth_uid === userId ? '✅' : '❌'}`);
      console.log(`  ✅ profile_id: ${data.profile_id ? '✅' : '❌'}`);
      console.log(`  ✅ profile object: ${data.profile ? '✅' : '❌'}`);
      console.log(`  ❌ firebase_uid: ${data.firebase_uid ? 'STILL EXISTS ❌' : '✅'}`);
      console.log(`  ❌ id field: ${data.id ? 'STILL EXISTS ❌' : '✅'}`);
      console.log(`  ✅ membership_json: ${data.membership_json ? '✅' : '❌'}`);
      console.log(`  ❌ membership_tier: ${data.membership_tier ? 'STILL EXISTS ❌' : '✅'}`);
      
      // Check for camelCase fields
      const camelCaseFields = ['isPhotoPrivate', 'profilePicture', 'photoUrl'];
      camelCaseFields.forEach(field => {
        if (data[field] !== undefined) {
          console.log(`  ❌ ${field}: STILL EXISTS (camelCase) ❌`);
        }
      });
      
      // Check for root-level profile fields
      const rootProfileFields = ['first_name', 'last_name', 'city', 'education'];
      rootProfileFields.forEach(field => {
        if (data[field] !== undefined) {
          console.log(`  ❌ ${field}: STILL EXISTS (should be in profile object) ❌`);
        }
      });
    });
    
  } catch (error) {
    console.error('❌ Verification failed:', error);
  }
}

// Single user cleanup for testing
async function cleanupSingleUser(userId) {
  console.log(`🔧 Cleaning up single user: ${userId}`);
  
  try {
    const db = firebase.firestore();
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      console.error(`❌ User ${userId} not found`);
      return;
    }
    
    const data = userDoc.data();
    const cleanedData = {};
    const fieldsToDelete = [];
    
    // Apply same cleanup logic as comprehensiveCleanup
    // (This is a simplified version for single user testing)
    
    // Fix auth_uid
    if (data.auth_uid && data.auth_uid !== userId) {
      cleanedData.auth_uid = userId;
    }
    
    // Delete bad fields
    fieldsToDelete.push('firebase_uid', 'id', 'isPhotoPrivate', 'profilePicture');
    
    // Apply changes
    const userRef = db.collection('users').doc(userId);
    if (Object.keys(cleanedData).length > 0) {
      await userRef.update(cleanedData);
    }
    
    if (fieldsToDelete.length > 0) {
      const deleteObj = {};
      fieldsToDelete.forEach(field => {
        if (data[field] !== undefined) {
          deleteObj[field] = firebase.firestore.FieldValue.delete();
        }
      });
      await userRef.update(deleteObj);
    }
    
    console.log(`✅ User ${userId} cleaned up successfully`);
    
  } catch (error) {
    console.error(`❌ Failed to cleanup ${userId}:`, error);
  }
}

console.log('🚀 Comprehensive Data Cleanup Script Loaded!');
console.log('📝 Available functions:');
console.log('  comprehensiveCleanup() - Fix all users (RECOMMENDED)');
console.log('  cleanupSingleUser(userId) - Fix single user (for testing)');
console.log('  verifyCleanup() - Verify cleanup results');
console.log('\n🔥 USAGE: comprehensiveCleanup()');
