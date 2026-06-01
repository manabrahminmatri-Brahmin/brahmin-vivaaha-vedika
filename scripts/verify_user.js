// 🔥 VERIFY MIGRATED USER
// Run this in Firebase Console browser console

async function verifyMigratedUser(userId) {
  console.log(`🔍 Verifying migrated user: ${userId}`);
  
  try {
    // Get the modules
    const firestoreModule = window['module$third_party$javascript$firebase$dist$firebase_firestore_pipelines'];
    const db = firestoreModule.getFirestore();
    const collection = firestoreModule.collection;
    const doc = firestoreModule.doc;
    const getDoc = firestoreModule.getDoc;
    
    // Get the user document
    const userRef = doc(db, 'users', userId);
    const userDoc = await getDoc(userRef);
    
    if (!userDoc.exists()) {
      console.log(`❌ User ${userId} not found`);
      return;
    }
    
    const data = userDoc.data();
    
    console.log('\n✅ SHOULD EXIST (Clean Structure):');
    console.log(`  auth_uid: ${data.auth_uid === userId ? '✅' : '❌'} (${data.auth_uid})`);
    console.log(`  profile_id: ${data.profile_id ? '✅' : '❌'} (${data.profile_id})`);
    console.log(`  profile object: ${data.profile ? '✅' : '❌'}`);
    console.log(`  photo_url: ${data.photo_url ? '✅' : '❌'} (${data.photo_url})`);
    console.log(`  is_photo_private: ${data.is_photo_private !== undefined ? '✅' : '❌'} (${data.is_photo_private})`);
    console.log(`  photo_privacy: ${data.photo_privacy ? '✅' : '❌'} (${data.photo_privacy})`);
    
    if (data.profile) {
      console.log('\n👤 Profile Object Contents:');
      console.log(`  first_name: ${data.profile.first_name ? '✅' : '❌'} (${data.profile.first_name})`);
      console.log(`  last_name: ${data.profile.last_name ? '✅' : '❌'} (${data.profile.last_name})`);
      console.log(`  city: ${data.profile.city ? '✅' : '❌'} (${data.profile.city})`);
      console.log(`  gender: ${data.profile.gender ? '✅' : '❌'} (${data.profile.gender})`);
    }
    
    console.log('\n❌ SHOULD NOT EXIST (Old Fields):');
    const oldFields = ['firstName', 'lastName', 'profilePicture', 'photoUrl', 'isPhotoPrivate', 'firebase_uid', 'id', 'authId'];
    oldFields.forEach(field => {
      const exists = data[field] !== undefined;
      console.log(`  ${field}: ${exists ? '❌ STILL EXISTS' : '✅ DELETED'}`);
    });
    
    console.log('\n📊 Full Document Structure:');
    console.log(JSON.stringify(data, null, 2));
    
  } catch (error) {
    console.error('❌ Verification failed:', error);
  }
}

console.log('🔍 User Verification Script Loaded!');
console.log('📝 Run: verifyMigratedUser("5l3d75kwnvTaLMwEWWe1")');
console.log('⚠️  Replace with your actual user ID if different');
