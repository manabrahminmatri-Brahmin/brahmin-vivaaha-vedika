// 🔥 SCHEMA MIGRATION - Transform messy data to clean normalized structure
// Run this in Firebase Console → Firestore → Database → Console
// Then run: migrateToCleanSchema()

async function migrateToCleanSchema() {
  console.log('🔥 Starting schema migration to clean structure...');
  
  try {
    const db = firebase.firestore();
    const batchSize = 10; // Small batches for complex transformations
    const usersSnapshot = await db.collection('users').get();
    const totalUsers = usersSnapshot.size;
    
    console.log(`📊 Migrating ${totalUsers} users to clean schema...`);
    
    let migratedCount = 0;
    let skippedCount = 0;
    let errorCount = 0;
    
    for (let i = 0; i < totalUsers; i += batchSize) {
      const batch = db.batch();
      const batchUsers = usersSnapshot.docs.slice(i, i + batchSize);
      
      console.log(`🔄 Processing batch ${Math.floor(i/batchSize) + 1}/${Math.ceil(totalUsers/batchSize)}`);
      
      for (const userDoc of batchUsers) {
        const userId = userDoc.id;
        const data = userDoc.data();
        
        console.log(`\n🔧 Migrating user: ${userId}`);
        
        // Build the new clean structure
        const newStructure = {};
        const fieldsToDelete = [];
        
        // 🔑 1. ROOT LEVEL (CORE FIELDS ONLY)
        
        // Fix auth_uid to match document ID
        newStructure.auth_uid = userId;
        
        // Keep profile_id if exists
        if (data.profile_id) {
          newStructure.profile_id = data.profile_id;
        }
        
        // Core status fields
        newStructure.is_online = data.is_online || false;
        newStructure.last_active = normalizeTimestamp(data.last_active);
        newStructure.created_at = normalizeTimestamp(data.created_at);
        newStructure.updated_at = firebase.firestore.FieldValue.serverTimestamp();
        
        newStructure.is_deleted = data.is_deleted || false;
        newStructure.is_verified = data.is_verified || true;
        newStructure.is_profile_complete = data.is_profile_complete || true;
        
        // Photo fields (consolidate)
        const photoUrls = [
          data.photo_url, data.photoUrl, 
          data.profile_picture, data.profilePicture
        ].filter(url => url && url !== '');
        
        if (photoUrls.length > 0) {
          newStructure.photo_url = photoUrls[0];
        }
        
        // Photo privacy (consolidate)
        const privacyFields = [data.is_photo_private, data.isPhotoPrivate];
        newStructure.is_photo_private = privacyFields.find(p => p !== undefined) || false;
        newStructure.photo_privacy = newStructure.is_photo_private ? 'private' : 'public';
        
        // Mark old photo fields for deletion
        fieldsToDelete.push('photo_url', 'photoUrl', 'profile_picture', 'profilePicture', 
                          'is_photo_private', 'isPhotoPrivate');
        
        // 👤 2. PROFILE OBJECT (SINGLE SOURCE OF TRUTH)
        const profile = {};
        
        // Basic info
        profile.first_name = getValue(data, ['first_name', 'firstName']) || '';
        profile.last_name = getValue(data, ['last_name', 'lastName']) || '';
        profile.gender = data.gender || '';
        
        // Date of birth and age
        const dob = getValue(data, ['date_of_birth', 'dateOfBirth']);
        if (dob) {
          profile.date_of_birth = dob;
          // Calculate age
          try {
            const dobDate = new Date(dob);
            const today = new Date();
            let age = today.getFullYear() - dobDate.getFullYear();
            const monthDiff = today.getMonth() - dobDate.getMonth();
            if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < dobDate.getDate())) {
              age--;
            }
            profile.age = age;
          } catch (e) {
            console.log(`  ⚠️ Could not calculate age for ${dob}`);
          }
        }
        
        // Physical attributes
        profile.height_cm = data.height || null;
        profile.body_type = data.body_type || '';
        profile.complexion = data.complexion || '';
        
        // Marital info
        profile.marital_status = data.marital_status || '';
        profile.manglik_status = data.manglik_status || '';
        
        // Education and occupation
        profile.education = data.education || '';
        profile.education_status = data.education_status || 'completed';
        profile.occupation = data.occupation || '';
        profile.company_name = data.company_name || '';
        profile.income_range = data.income_range || '';
        
        // Location
        profile.city = data.city || '';
        profile.state = data.state || '';
        profile.country = data.country || 'India';
        
        // About sections
        profile.about_me = data.about_me || '';
        profile.about_family = data.about_family || data.family_background || '';
        
        // Family object
        profile.family = {
          type: data.family_type || '',
          status: data.family_status || data.family_income || '',
          values: data.family_values || ''
        };
        
        // Parents object
        profile.parents = {
          father: {
            name: data.father_name || '',
            occupation: data.father_occupation || ''
          },
          mother: {
            name: data.mother_name || '',
            occupation: data.mother_occupation || ''
          }
        };
        
        // Siblings object
        profile.siblings = {
          brothers: parseInt(data.brothers) || 0,
          brothers_married: parseInt(data.married_brothers) || 0,
          sisters: parseInt(data.sisters) || 0,
          sisters_married: parseInt(data.married_sisters) || 0
        };
        
        // Religion object
        profile.religion = {
          sect: data.religion || '',
          sub_sect: data.sub_caste || '',
          gothram: data.gothram || ''
        };
        
        // Astrology object
        profile.astro = {
          rasi: data.raasi || data.rasi || '',
          nakshatra: data.star || data.nakshatra || '',
          pada: data.pada || ''
        };
        
        // Habits object
        profile.habits = {
          food: data.diet || '',
          drinking: data.drinking || '',
          smoking: data.smoking || ''
        };
        
        // Arrays
        profile.languages = data.languages || [];
        profile.hobbies = data.hobbies || [];
        
        // Preferences
        profile.partner_preferences = data.partner_preferences || '';
        
        // Profile completion
        profile.profile_completion_percentage = 100; // Assume complete for existing users
        
        // Mark root-level profile fields for deletion
        const rootProfileFields = [
          'first_name', 'firstName', 'last_name', 'lastName', 'date_of_birth', 'dateOfBirth',
          'height', 'body_type', 'complexion', 'marital_status', 'manglik_status',
          'education', 'education_status', 'occupation', 'company_name', 'income_range',
          'city', 'state', 'country', 'about_me', 'family_background',
          'family_type', 'family_status', 'family_income', 'family_values',
          'father_name', 'father_occupation', 'mother_name', 'mother_occupation',
          'brothers', 'married_brothers', 'sisters', 'married_sisters',
          'religion', 'sub_caste', 'gothram', 'raasi', 'rasi', 'star', 'nakshatra', 'pada',
          'diet', 'drinking', 'smoking', 'languages', 'hobbies', 'partner_preferences'
        ];
        fieldsToDelete.push(...rootProfileFields);
        
        newStructure.profile = profile;
        
        // 💳 3. MEMBERSHIP (SINGLE SOURCE)
        if (data.membership_json) {
          newStructure.membership = data.membership_json;
        } else if (data.membership_tier || data.membership_status) {
          // Create membership object from separate fields
          newStructure.membership = {
            tier: data.membership_tier || 'free',
            status: data.membership_status || 'inactive',
            start_date: normalizeTimestamp(data.membership_start_date),
            expiry_date: normalizeTimestamp(data.membership_expires_at || data.membership_expiry_date)
          };
        }
        
        // Mark old membership fields for deletion
        fieldsToDelete.push('membership_json', 'membership_tier', 'membership_status',
                          'membership_start_date', 'membership_expires_at', 'membership_expiry_date');
        
        // 🔔 4. FCM (CLEAN STRUCTURE)
        if (data.fcm_token) {
          newStructure.fcm = {
            token: data.fcm_token,
            platform: data.platform || 'web',
            updated_at: firebase.firestore.FieldValue.serverTimestamp()
          };
          fieldsToDelete.push('fcm_token', 'platform');
        }
        
        // ❤️ 5. REMOVE RELATION ARRAYS (should be separate collections)
        fieldsToDelete.push('liked_users', 'liked_by', 'interests_sent', 'interests_received');
        
        // 🔐 6. CLEAN IDENTITY FIELDS
        fieldsToDelete.push('firebase_uid', 'id', 'authId');
        
        // Apply the migration
        if (Object.keys(newStructure).length > 0) {
          batch.update(userDoc.ref, newStructure);
          console.log(`  ✅ Building new structure with ${Object.keys(newStructure).length} top-level fields`);
        }
        
        // Delete old fields (only if they exist)
        const validDeletions = fieldsToDelete.filter(field => data[field] !== undefined);
        if (validDeletions.length > 0) {
          const deleteObj = {};
          validDeletions.forEach(field => {
            deleteObj[field] = firebase.firestore.FieldValue.delete();
          });
          batch.update(userDoc.ref, deleteObj);
          console.log(`  🗑️ Deleting ${validDeletions.length} old fields`);
        }
        
        migratedCount++;
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
    
    console.log('\n🎉 MIGRATION SUMMARY:');
    console.log(`✅ Migrated: ${migratedCount} users`);
    console.log(`⏭️  Skipped: ${skippedCount} users`);
    console.log(`❌ Errors: ${errorCount} batches`);
    console.log(`📊 Total processed: ${totalUsers} users`);
    
    // Verify migration
    console.log('\n🔍 VERIFYING MIGRATION:');
    await verifyMigration();
    
  } catch (error) {
    console.error('💥 Migration failed:', error);
  }
}

// Helper function to get value from multiple possible field names
function getValue(data, fieldNames) {
  for (const fieldName of fieldNames) {
    if (data[fieldName] !== undefined && data[fieldName] !== null) {
      return data[fieldName];
    }
  }
  return null;
}

// Helper function to normalize timestamps
function normalizeTimestamp(value) {
  if (!value) return null;
  
  if (typeof value === 'string') {
    try {
      return new Date(value);
    } catch (e) {
      return null;
    }
  }
  
  if (value && typeof value.toDate === 'function') {
    return value.toDate();
  }
  
  return value;
}

// Verification function
async function verifyMigration() {
  console.log('🔍 Verifying migration results...');
  
  try {
    const db = firebase.firestore();
    const users = await db.collection('users').limit(3).get();
    
    users.forEach(doc => {
      const userId = doc.id;
      const data = doc.data();
      
      console.log(`\n👤 User: ${userId}`);
      
      // Check root structure
      console.log(`  ✅ auth_uid: ${data.auth_uid === userId ? '✅' : '❌'}`);
      console.log(`  ✅ profile_id: ${data.profile_id ? '✅' : '❌'}`);
      console.log(`  ✅ profile object: ${data.profile ? '✅' : '❌'}`);
      console.log(`  ✅ membership object: ${data.membership ? '✅' : '❌'}`);
      console.log(`  ✅ fcm object: ${data.fcm ? '✅' : 'ℹ️'}`);
      
      // Check for old fields (should be deleted)
      const oldFields = ['firebase_uid', 'id', 'firstName', 'isPhotoPrivate', 'membership_tier'];
      const existingOldFields = oldFields.filter(field => data[field] !== undefined);
      
      if (existingOldFields.length > 0) {
        console.log(`  ❌ Old fields still exist: ${existingOldFields.join(', ')}`);
      } else {
        console.log(`  ✅ No old fields remaining`);
      }
      
      // Check profile structure
      if (data.profile) {
        const profile = data.profile;
        console.log(`  ✅ profile.first_name: ${profile.first_name ? '✅' : '❌'}`);
        console.log(`  ✅ profile.family: ${profile.family ? '✅' : '❌'}`);
        console.log(`  ✅ profile.astro: ${profile.astro ? '✅' : '❌'}`);
      }
      
    });
    
  } catch (error) {
    console.error('❌ Verification failed:', error);
  }
}

// Single user migration for testing
async function migrateSingleUser(userId) {
  console.log(`🔧 Migrating single user: ${userId}`);
  
  try {
    const db = firebase.firestore();
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      console.error(`❌ User ${userId} not found`);
      return;
    }
    
    // For single user testing, just show the current structure
    const data = userDoc.data();
    console.log('\n📋 CURRENT STRUCTURE:');
    console.log(JSON.stringify(data, null, 2));
    
    console.log('\n🔧 Run migrateToCleanSchema() to migrate all users');
    
  } catch (error) {
    console.error(`❌ Failed to migrate ${userId}:`, error);
  }
}

console.log('🚀 Schema Migration Script Loaded!');
console.log('📝 Available functions:');
console.log('  migrateToCleanSchema() - Migrate all users to clean schema (RECOMMENDED)');
console.log('  migrateSingleUser(userId) - Test single user structure');
console.log('  verifyMigration() - Verify migration results');
console.log('\n🔥 USAGE: migrateToCleanSchema()');
console.log('\n⚠️  WARNING: This will permanently transform your data structure!');
console.log('    Make sure you have backups before running.');
