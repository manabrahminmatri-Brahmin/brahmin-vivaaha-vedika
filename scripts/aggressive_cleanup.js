// 🔥 AGGRESSIVE CLEANUP - Remove all old fields properly
// Run this in Firebase Console browser console

async function aggressiveCleanup(userId) {
  console.log(`🔧 Starting aggressive cleanup for user: ${userId}`);
  
  try {
    // Get the modules
    const firestoreModule = window['module$third_party$javascript$firebase$dist$firebase_firestore_pipelines'];
    const db = firestoreModule.getFirestore();
    const collection = firestoreModule.collection;
    const doc = firestoreModule.doc;
    const getDoc = firestoreModule.getDoc;
    const updateDoc = firestoreModule.updateDoc;
    const deleteField = firestoreModule.deleteField;
    const serverTimestamp = firestoreModule.serverTimestamp;
    
    // Get current user document
    const userRef = doc(db, 'users', userId);
    const userDoc = await getDoc(userRef);
    
    if (!userDoc.exists()) {
      console.log(`❌ User ${userId} not found`);
      return;
    }
    
    const data = userDoc.data();
    
    // Build the clean structure
    const cleanData = {};
    const fieldsToDelete = [];
    
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
      // CamelCase fields
      'firstName', 'lastName', 'photoUrl', 'profilePicture', 'isPhotoPrivate',
      'firebase_uid', 'id', 'authId',
      
      // Root-level profile fields (moved to profile object)
      'first_name', 'last_name', 'date_of_birth', 'gender', 'height', 'body_type', 
      'complexion', 'physical_status', 'city', 'state', 'country', 'education', 
      'education_status', 'occupation', 'company_name', 'income_range', 'family_type',
      'family_status', 'family_values', 'father_name', 'father_occupation', 'mother_name',
      'mother_occupation', 'brothers', 'brothers_married', 'sisters', 'sisters_married',
      'religion', 'sect', 'sub_sect', 'gothram', 'rasi', 'nakshatra', 'pada',
      'food_habit', 'diet', 'drinking_habit', 'drinking', 'smoking_habit', 'smoking',
      'languages', 'hobbies', 'about_me', 'partner_preferences',
      
      // Photo duplicates
      'profile_picture', 'photo_provider', 'photo_last_updated', 'profile_picture_public_id',
      
      // Membership duplicates
      'membership_tier', 'membership_status', 'membership_start_date', 'membership_expiry_date',
      'membership_expires_at',
      
      // Relation arrays (should be separate collections)
      'liked_users', 'liked_by', 'interests_sent', 'interests_received',
      
      // Other old fields
      'profile_completion_percentage', 'education_location_city', 'education_location_country',
      'native_place_country', 'native_place_state', 'native_place_city', 'place_of_birth',
      'place_of_birth_country', 'place_of_birth_state', 'family_origin_country', 
      'family_origin_state', 'family_origin_city', 'fcm_platform', 'fcm_token', 
      'fcm_token_invalidated_at', 'fcm_token_updated_at', 'last_active', 'last_login_at',
      'mpin_hash', 'mpin_verified', 'migrated_from_doc_id', 'migrated_to_uid', 
      'migrated_at', 'is_migrated', 'is_premium', 'is_profile_locked', 'is_email_verified',
      'privacy_show_online_status', 'privacy_show_last_seen', 'photo_privacy_updated_at',
      'data_refresh_flag', 'star_confirmed', 'known_reference', 'mother_surname',
      'specialization', 'employment_type', 'time_of_birth', 'about_family', 'partner_expectations',
      'profile_created_by', 'mother_note', 'father_note', 'mobile_number', 'email'
    ];
    
    // Build delete operations
    const deleteOps = {};
    oldFields.forEach(field => {
      if (data[field] !== undefined) {
        deleteOps[field] = deleteField();
      }
    });
    
    console.log(`📊 Keeping ${Object.keys(cleanData).length} clean fields`);
    console.log(`🗑️ Deleting ${Object.keys(deleteOps).length} old fields`);
    
    // Apply both updates and deletions
    await updateDoc(userRef, {
      ...cleanData,
      ...deleteOps
    });
    
    console.log('✅ Aggressive cleanup completed!');
    
    // Verify the cleanup
    const afterDoc = await getDoc(userRef);
    const afterData = afterDoc.data();
    
    console.log('\n🔍 AFTER CLEANUP VERIFICATION:');
    console.log(`✅ auth_uid: ${afterData.auth_uid === userId ? '✅' : '❌'}`);
    console.log(`✅ profile object: ${afterData.profile ? '✅' : '❌'}`);
    console.log(`✅ photo_url: ${afterData.photo_url ? '✅' : '❌'}`);
    
    const remainingOldFields = oldFields.filter(field => afterData[field] !== undefined);
    if (remainingOldFields.length > 0) {
      console.log(`❌ Still has old fields: ${remainingOldFields.join(', ')}`);
    } else {
      console.log(`✅ All old fields deleted successfully!`);
    }
    
  } catch (error) {
    console.error('❌ Aggressive cleanup failed:', error);
  }
}

console.log('🔥 Aggressive Cleanup Script Loaded!');
console.log('📝 Run: aggressiveCleanup("5l3d75kwnvTaLMwEWWe1")');
console.log('⚠️  This will aggressively delete all old fields!');
