async function migrateToCleanSchema() {
  console.log('🔥 Starting schema migration...');

  try {
    // 🔥 Access Firestore in Firebase Console environment
    let db, FieldValue, firestoreModule;
    
    // Try accessing through the Firebase module system in Firebase Console
    try {
      // Found in debug: module$third_party$javascript$firebase$dist$firebase_firestore_pipelines
      firestoreModule = window['module$third_party$javascript$firebase$dist$firebase_firestore_pipelines'];
      const appModule = window['module$third_party$javascript$firebase$dist$firebase_app'];
      
      if (firestoreModule && appModule) {
        console.log('🔥 Found Firebase modules!');
        console.log('Firestore module keys:', Object.keys(firestoreModule));
        console.log('App module keys:', Object.keys(appModule));
        
        // Try different ways to get Firestore instance
        try {
          db = firestoreModule.getFirestore();
          console.log('✅ Got Firestore via getFirestore()');
        } catch (e1) {
          try {
            db = firestoreModule.getFirestore(firebase.apps[0]);
            console.log('✅ Got Firestore via getFirestore(app)');
          } catch (e2) {
            try {
              // Try direct module methods
              const methods = Object.keys(firestoreModule).filter(k => typeof firestoreModule[k] === 'function');
              console.log('Available Firestore methods:', methods);
              
              // Try common patterns
              if (firestoreModule.firestore) {
                db = firestoreModule.firestore();
              } else if (firestoreModule.Firestore) {
                const FirestoreClass = firestoreModule.Firestore;
                db = new FirestoreClass();
              } else {
                throw new Error('Could not find Firestore constructor');
              }
            } catch (e3) {
              throw new Error('All Firestore access methods failed');
            }
          }
        }
        
        // Try to get FieldValue
        FieldValue = firestoreModule.FieldValue || firestoreModule.fieldValue;
      } else {
        throw new Error('Firebase modules not found');
      }
    } catch (e1) {
      try {
        // Try traditional approach
        const app = firebase.apps[0];
        db = app.firestore();
        FieldValue = app.firestore.FieldValue;
      } catch (e2) {
        throw new Error('Could not access Firestore through any method');
      }
    }

    // 🔥 TEST FIRST (IMPORTANT) - Using Firebase v9+ modular API
    const collection = firestoreModule.collection;
    const getDocs = firestoreModule.getDocs;
    const query = firestoreModule.query;
    const limit = firestoreModule.limit;
    const writeBatch = firestoreModule.writeBatch;
    
    const usersQuery = query(collection(db, 'users'), limit(1));
    const usersSnapshot = await getDocs(usersQuery);

    console.log(`📊 Found ${usersSnapshot.size} users`);

    let batch = writeBatch(db);

    // Get needed functions from module
    const doc = firestoreModule.doc;
    const updateDoc = firestoreModule.updateDoc;
    
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
      newStructure.updated_at = firestoreModule.serverTimestamp();

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

      // ✅ MERGE UPDATE + DELETE (IMPORTANT FIX) - Using v9+ API
      const userRef = doc(db, 'users', userId);
      batch.update(userRef, {
        ...newStructure,
        ...deleteObj
      });
    }

    await batch.commit();

    console.log('✅ Migration complete (TEST MODE)');
    console.log('👉 Verify this user before running full migration');

  } catch (error) {
    console.error('💥 Migration failed:', error);
  }
}

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
    if (firebase.apps && firebase.apps.length > 0) {
      const app = firebase.apps[0];
      console.log('app.firestore:', typeof app.firestore);
      console.log('app.firestore?.getFirestore:', typeof app.firestore?.getFirestore);
    }
  }
  
  if (typeof Firestore !== 'undefined') {
    console.log('Firestore.getInstance:', typeof Firestore.getInstance);
    console.log('Firestore.getFirestore:', typeof Firestore.getFirestore);
  }
  
  // Show all available window globals that might contain Firestore
  console.log('🔍 Searching for Firestore in window globals...');
  Object.keys(window).forEach(key => {
    if (key.toLowerCase().includes('fire') || key.toLowerCase().includes('store')) {
      console.log(`${key}:`, typeof window[key]);
    }
  });
}

console.log('🚀 Schema Migration Script Loaded!');
console.log('📝 Run: debugFirebaseConsole() to check environment');
console.log('📝 Run: migrateToCleanSchema() to start migration');
console.log('⚠️  This will permanently transform your data structure!');
