// 🔥 FULL MIGRATION - Apply aggressive cleanup to ALL users
// Run this in Firebase Console browser console

async function fullMigration() {
  console.log('🔥 Starting FULL migration for ALL users...');
  
  try {
    // Get the modules
    const firestoreModule = window['module$third_party$javascript$firebase$dist$firebase_firestore_pipelines'];
    const db = firestoreModule.getFirestore();
    const collection = firestoreModule.collection;
    const doc = firestoreModule.doc;
    const getDocs = firestoreModule.getDocs;
    const updateDoc = firestoreModule.updateDoc;
    const deleteField = firestoreModule.deleteField;
    const serverTimestamp = firestoreModule.serverTimestamp;
    
    // Get ALL users
    const usersSnapshot = await getDocs(collection(db, 'users'));
    const totalUsers = usersSnapshot.size;
    
    console.log(`📊 Found ${totalUsers} users to migrate`);
    
    let migratedCount = 0;
    let errorCount = 0;
    
    // Process in batches of 10 to avoid timeouts
    const batchSize = 10;
    
    for (let i = 0; i < totalUsers; i += batchSize) {
      const batchUsers = usersSnapshot.docs.slice(i, i + batchSize);
      console.log(`🔄 Processing batch ${Math.floor(i/batchSize) + 1}/${Math.ceil(totalUsers/batchSize)} (${batchUsers.length} users)`);
      
      // Process each user in batch
      for (const userDoc of batchUsers) {
        const userId = userDoc.id;
        const data = userDoc.data();
        
        try {
          // Build the clean structure
          const cleanData = {};
          const deleteOps = {};
          
          // ✅ KEEP ONLY CLEAN STRUCTURE
          cleanData.auth_uid = userId;
          cleanData.profile_id = data.profile_id || null;
          cleanData.is_online = data.is_online || false;
          cleanData.is_deleted = data.is_deleted || false;
          cleanData.is_verified = data.is_verified || true;
          cleanData.is_profile_complete = data.is_profile_complete || false;
          cleanData.status = data.status || 'active';
          cleanData.updated_at = serverTimestamp();
          
          // Photo fields (consolidate)
          const photoUrls = [data.photo_url, data.photoUrl, data.profile_picture, data.profilePicture].filter(url => url && url !== '');
          if (photoUrls.length > 0) cleanData.photo_url = photoUrls[0];
          
          const isPrivate = data.is_photo_private ?? data.isPhotoPrivate ?? false;
          cleanData.is_photo_private = isPrivate;
          cleanData.photo_privacy = isPrivate ? 'private' : 'public';
          
          // Profile object (consolidate ALL personal data)
          const profile = {};
          
          // Basic info
          profile.first_name = data.first_name || data.firstName || '';
          profile.last_name = data.last_name || data.lastName || '';
          profile.gender = data.gender || '';
          profile.date_of_birth = data.date_of_birth || '';
          
          // Physical
          profile.height_cm = data.height || '';
          profile.body_type = data.body_type || '';
          profile.complexion = data.complexion || '';
          profile.physical_status = data.physical_status || '';
          
          // Location
          profile.city = data.city || '';
          profile.state = data.state || '';
          profile.country = data.country || 'India';
          
          // Education/Occupation
          profile.education = data.education || '';
          profile.education_status = data.education_status || '';
          profile.occupation = data.occupation || '';
          profile.company_name = data.company_name || '';
          profile.income_range = data.income_range || '';
          
          // Family
          profile.family_type = data.family_type || '';
          profile.family_status = data.family_status || '';
          profile.family_values = data.family_values || '';
          profile.father_name = data.father_name || '';
          profile.father_occupation = data.father_occupation || '';
          profile.mother_name = data.mother_name || '';
          profile.mother_occupation = data.mother_occupation || '';
          profile.brothers = parseInt(data.brothers) || 0;
          profile.brothers_married = parseInt(data.brothers_married) || 0;
          profile.sisters = parseInt(data.sisters) || 0;
          profile.sisters_married = parseInt(data.sisters_married) || 0;
          
          // Religion/Astrology
          profile.religion = data.religion || '';
          profile.sect = data.sect || '';
          profile.sub_sect = data.sub_sect || '';
          profile.gothram = data.gothram || '';
          profile.rasi = data.rasi || '';
          profile.nakshatra = data.nakshatra || '';
          profile.pada = data.pada || '';
          
          // Habits
          profile.food_habit = data.food_habit || data.diet || '';
          profile.drinking_habit = data.drinking_habit || data.drinking || '';
          profile.smoking_habit = data.smoking_habit || data.smoking || '';
          
          // Arrays
          profile.languages = data.languages || [];
          profile.hobbies = data.hobbies || [];
          
          // About
          profile.about_me = data.about_me || '';
          profile.partner_preferences = data.partner_preferences || '';
          
          cleanData.profile = profile;
          
          // Membership (keep only json)
          if (data.membership_json) {
            cleanData.membership = data.membership_json;
          }
          
          // ❌ DELETE ALL OLD FIELDS
          const oldFields = [
            'firstName', 'lastName', 'photoUrl', 'profilePicture', 'isPhotoPrivate',
            'firebase_uid', 'id', 'authId', 'first_name', 'last_name', 'date_of_birth', 
            'gender', 'height', 'body_type', 'complexion', 'physical_status', 'city', 'state', 
            'country', 'education', 'education_status', 'occupation', 'company_name', 
            'income_range', 'family_type', 'family_status', 'family_values', 'father_name', 
            'father_occupation', 'mother_name', 'mother_occupation', 'brothers', 'brothers_married', 
            'sisters', 'sisters_married', 'religion', 'sect', 'sub_sect', 'gothram', 'rasi', 
            'nakshatra', 'pada', 'food_habit', 'diet', 'drinking_habit', 'drinking', 'smoking_habit', 
            'smoking', 'languages', 'hobbies', 'about_me', 'partner_preferences', 'profile_picture', 
            'photo_provider', 'photo_last_updated', 'profile_picture_public_id', 'membership_tier', 
            'membership_status', 'membership_start_date', 'membership_expiry_date', 'membership_expires_at',
            'liked_users', 'liked_by', 'interests_sent', 'interests_received', 'profile_completion_percentage',
            'education_location_city', 'education_location_country', 'native_place_country', 'native_place_state',
            'native_place_city', 'place_of_birth', 'place_of_birth_country', 'place_of_birth_state',
            'family_origin_country', 'family_origin_state', 'family_origin_city', 'fcm_platform', 'fcm_token',
            'fcm_token_invalidated_at', 'fcm_token_updated_at', 'last_active', 'last_login_at', 'mpin_hash',
            'mpin_verified', 'migrated_from_doc_id', 'migrated_to_uid', 'migrated_at', 'is_migrated', 'is_premium',
            'is_profile_locked', 'is_email_verified', 'privacy_show_online_status', 'privacy_show_last_seen',
            'photo_privacy_updated_at', 'data_refresh_flag', 'star_confirmed', 'known_reference', 'mother_surname',
            'specialization', 'employment_type', 'time_of_birth', 'about_family', 'partner_expectations',
            'profile_created_by', 'mother_note', 'father_note', 'mobile_number', 'email'
          ];
          
          // Build delete operations
          oldFields.forEach(field => {
            if (data[field] !== undefined) {
              deleteOps[field] = deleteField();
            }
          });
          
          // Apply both updates and deletions
          const userRef = doc(db, 'users', userId);
          await updateDoc(userRef, {
            ...cleanData,
            ...deleteOps
          });
          
          migratedCount++;
          console.log(`  ✅ Migrated: ${userId}`);
          
        } catch (error) {
          errorCount++;
          console.error(`  ❌ Failed to migrate ${userId}:`, error);
        }
      }
      
      // Small delay between batches
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    console.log('\n🎉 FULL MIGRATION COMPLETE!');
    console.log(`✅ Successfully migrated: ${migratedCount} users`);
    console.log(`❌ Failed: ${errorCount} users`);
    console.log(`📊 Total processed: ${totalUsers} users`);
    
    console.log('\n🔍 FINAL VERIFICATION - Checking first 3 users:');
    await verifyFirstUsers();
    
  } catch (error) {
    console.error('💥 Full migration failed:', error);
  }
}

async function verifyFirstUsers() {
  try {
    const firestoreModule = window['module$third_party$javascript$firebase$dist$firebase_firestore_pipelines'];
    const db = firestoreModule.getFirestore();
    const collection = firestoreModule.collection;
    const doc = firestoreModule.doc;
    const getDocs = firestoreModule.getDocs;
    const limit = firestoreModule.limit;
    const query = firestoreModule.query;
    
    const usersSnapshot = await getDocs(query(collection(db, 'users'), limit(3)));
    
    usersSnapshot.forEach(userDoc => {
      const userId = userDoc.id;
      const data = userDoc.data();
      
      console.log(`\n👤 User: ${userId}`);
      console.log(`  ✅ auth_uid: ${data.auth_uid === userId ? '✅' : '❌'}`);
      console.log(`  ✅ profile object: ${data.profile ? '✅' : '❌'}`);
      console.log(`  ✅ membership only: ${data.membership ? '✅' : '❌'} ${data.membership_tier ? '❌ old tier exists' : ''}`);
      
      const oldFields = ['firstName', 'profilePicture', 'firebase_uid', 'liked_users'];
      const existingOldFields = oldFields.filter(field => data[field] !== undefined);
      
      if (existingOldFields.length > 0) {
        console.log(`  ❌ Old fields still exist: ${existingOldFields.join(', ')}`);
      } else {
        console.log(`  ✅ Clean structure!`);
      }
    });
    
  } catch (error) {
    console.error('❌ Verification failed:', error);
  }
}

console.log('🚀 Full Migration Script Loaded!');
console.log('📝 Run: fullMigration()');
console.log('⚠️  This will migrate ALL users to clean schema!');
console.log('⚠️  This process may take several minutes for large datasets');
