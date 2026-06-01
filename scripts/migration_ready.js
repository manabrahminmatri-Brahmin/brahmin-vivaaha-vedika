async function migrateToCleanSchema() {
  console.log('🔥 Starting schema migration...');

  try {
    // 🔥 Try different ways to access Firestore in Firebase Console
    let db, FieldValue;
    
    try {
      db = firebase.firestore();
      FieldValue = firebase.firestore.FieldValue;
    } catch (e) {
      try {
        db = Firestore.getInstance();
        FieldValue = Firestore.FieldValue;
      } catch (e2) {
        try {
          db = window.firestore;
          FieldValue = window.firestore.FieldValue;
        } catch (e3) {
          throw new Error('Could not access Firestore. Check console for available globals.');
        }
      }
    }

    const batchSize = 10;

    // 🔥 TEST FIRST (IMPORTANT)
    const usersSnapshot = await db.collection('users').limit(1).get();

    console.log(`📊 Found ${usersSnapshot.size} users`);

    let batch = db.batch();

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const data = userDoc.data();

      console.log(`🔧 Migrating user: ${userId}`);

      const newStructure = {};
      const deleteObj = {};

      // ✅ ROOT
      newStructure.auth_uid = userId;
      newStructure.profile_id = data.profile_id || null;
      newStructure.is_online = data.is_online || false;
      newStructure.updated_at = FieldValue.serverTimestamp();

      // ✅ PHOTO
      const photo = data.photo_url || data.photoUrl || data.profile_picture || data.profilePicture;
      if (photo) newStructure.photo_url = photo;

      const isPrivate = data.is_photo_private ?? data.isPhotoPrivate ?? false;
      newStructure.is_photo_private = isPrivate;
      newStructure.photo_privacy = isPrivate ? 'private' : 'public';

      // ✅ PROFILE
      newStructure.profile = {
        first_name: data.first_name || data.firstName || '',
        last_name: data.last_name || data.lastName || '',
        gender: data.gender || '',
        city: data.city || '',
        state: data.state || '',
        country: data.country || 'India'
      };

      // ❌ DELETE OLD FIELDS
      [
        'firstName',
        'lastName',
        'photoUrl',
        'profilePicture',
        'isPhotoPrivate',
        'firebase_uid',
        'id',
        'authId'
      ].forEach(field => {
        if (data[field] !== undefined) {
          deleteObj[field] = FieldValue.delete();
        }
      });

      // ✅ MERGE UPDATE + DELETE (IMPORTANT FIX)
      batch.update(userDoc.ref, {
        ...newStructure,
        ...deleteObj
      });
    }

    await batch.commit();

    console.log('✅ Migration complete (TEST MODE)');
    console.log('👉 Verify this user before running full migration');

    // 🔥 Debug function to check what's available
    function debugFirebaseConsole() {
      console.log('🔍 Checking available Firebase globals...');
      console.log('firebase:', typeof firebase);
      console.log('Firestore:', typeof Firestore);
      console.log('window.firestore:', typeof window.firestore);
      console.log('window.firebase:', typeof window.firebase);
      
      if (typeof firebase !== 'undefined') {
        console.log('firebase.firestore:', typeof firebase.firestore);
        console.log('firebase.apps:', firebase.apps);
      }
    console.log('🚀 Schema Migration Script Loaded!');
    console.log('📝 Run: migrateToCleanSchema() to start migration');
    console.log('⚠️  This will permanently transform your data structure!');

  } catch (error) {
    console.error('💥 Migration failed:', error);
  }
}
}