// 🔥 DATA AUDIT - Check current state of your data before cleanup
// Run this in Firebase Console → Firestore → Database → Console
// Then run: auditData()

async function auditData() {
  console.log('🔍 Starting comprehensive data audit...');
  
  try {
    const db = firebase.firestore();
    const usersSnapshot = await db.collection('users').limit(10).get();
    
    console.log(`📊 Auditing ${usersSnapshot.size} users...\n`);
    
    let issues = {
      duplicateFields: 0,
      rootProfileFields: 0,
      identityConfusion: 0,
      camelCaseFields: 0,
      dateInconsistency: 0,
      membershipDuplication: 0
    };
    
    usersSnapshot.forEach(doc => {
      const userId = doc.id;
      const data = doc.data();
      
      console.log(`👤 User: ${userId}`);
      
      // 🔴 1. CHECK DUPLICATE FIELDS
      console.log('  📋 Duplicate Fields Check:');
      
      // Photo fields
      const photoFields = ['photo_url', 'photoUrl', 'profile_picture', 'profilePicture'];
      const existingPhotoFields = photoFields.filter(f => data[f] !== undefined);
      if (existingPhotoFields.length > 1) {
        console.log(`    ❌ Photo fields: ${existingPhotoFields.join(', ')}`);
        issues.duplicateFields++;
      } else if (existingPhotoFields.length === 1) {
        console.log(`    ✅ Photo field: ${existingPhotoFields[0]}`);
      }
      
      // Privacy fields
      const privacyFields = ['is_photo_private', 'isPhotoPrivate'];
      const existingPrivacyFields = privacyFields.filter(f => data[f] !== undefined);
      if (existingPrivacyFields.length > 1) {
        console.log(`    ❌ Privacy fields: ${existingPrivacyFields.join(', ')}`);
        issues.duplicateFields++;
      } else if (existingPrivacyFields.length === 1) {
        console.log(`    ✅ Privacy field: ${existingPrivacyFields[0]}`);
      }
      
      // 🔴 2. CHECK ROOT vs PROFILE DUPLICATION
      console.log('  📋 Root vs Profile Check:');
      
      const rootProfileFields = ['first_name', 'last_name', 'city', 'education', 'occupation'];
      const existingRootFields = rootProfileFields.filter(f => data[f] !== undefined);
      const hasProfileObject = data.profile && typeof data.profile === 'object';
      
      if (existingRootFields.length > 0 && hasProfileObject) {
        console.log(`    ❌ Root fields exist with profile object: ${existingRootFields.join(', ')}`);
        issues.rootProfileFields++;
      } else if (existingRootFields.length > 0) {
        console.log(`    ⚠️ Root fields only (no profile object): ${existingRootFields.join(', ')}`);
      } else if (hasProfileObject) {
        console.log(`    ✅ Profile object only`);
      } else {
        console.log(`    ❌ Neither root fields nor profile object`);
      }
      
      // 🔴 3. CHECK IDENTITY CONFUSION
      console.log('  📋 Identity Fields Check:');
      
      const identityFields = ['auth_uid', 'firebase_uid', 'id', 'profile_id'];
      const existingIdentityFields = identityFields.filter(f => data[f] !== undefined);
      
      console.log(`    📝 Identity fields: ${existingIdentityFields.join(', ')}`);
      
      if (data.firebase_uid !== undefined) {
        console.log(`    ❌ firebase_uid exists (should be removed)`);
        issues.identityConfusion++;
      }
      
      if (data.id !== undefined && data.id !== userId) {
        console.log(`    ❌ id field conflicts with document ID`);
        issues.identityConfusion++;
      }
      
      if (data.auth_uid && data.auth_uid !== userId) {
        console.log(`    ❌ auth_uid mismatch: ${data.auth_uid} ≠ ${userId}`);
        issues.identityConfusion++;
      } else if (data.auth_uid === userId) {
        console.log(`    ✅ auth_uid matches document ID`);
      }
      
      // 🔴 4. CHECK CAMEL CASE
      console.log('  📋 CamelCase Check:');
      
      const camelCaseFields = ['isPhotoPrivate', 'profilePicture', 'photoUrl', 'firebaseUid'];
      const existingCamelCase = camelCaseFields.filter(f => data[f] !== undefined);
      
      if (existingCamelCase.length > 0) {
        console.log(`    ❌ CamelCase fields: ${existingCamelCase.join(', ')}`);
        issues.camelCaseFields++;
      } else {
        console.log(`    ✅ No camelCase fields`);
      }
      
      // 🔴 5. CHECK DATE INCONSISTENCY
      console.log('  📋 Date Format Check:');
      
      if (data.last_active !== undefined) {
        if (typeof data.last_active === 'string') {
          console.log(`    ❌ last_active is string: ${data.last_active}`);
          issues.dateInconsistency++;
        } else if (data.last_active && typeof data.last_active.toDate === 'function') {
          console.log(`    ✅ last_active is timestamp`);
        } else {
          console.log(`    ⚠️ last_active unknown type: ${typeof data.last_active}`);
        }
      }
      
      // 🔴 6. CHECK MEMBERSHIP DUPLICATION
      console.log('  📋 Membership Data Check:');
      
      const membershipFields = ['membership_json', 'membership_tier', 'membership_status', 'membership_expires_at', 'membership_expiry_date'];
      const existingMembershipFields = membershipFields.filter(f => data[f] !== undefined);
      
      if (existingMembershipFields.length > 1) {
        console.log(`    ❌ Multiple membership fields: ${existingMembershipFields.join(', ')}`);
        issues.membershipDuplication++;
      } else if (data.membership_json) {
        console.log(`    ✅ membership_json only`);
      } else if (existingMembershipFields.length === 1) {
        console.log(`    ⚠️ Single non-json membership field: ${existingMembershipFields[0]}`);
      } else {
        console.log(`    ℹ️ No membership data`);
      }
      
      console.log(''); // Empty line for readability
    });
    
    // Summary
    console.log('🎯 AUDIT SUMMARY:');
    console.log(`❌ Duplicate fields: ${issues.duplicateFields} users`);
    console.log(`❌ Root/Profile duplication: ${issues.rootProfileFields} users`);
    console.log(`❌ Identity confusion: ${issues.identityConfusion} users`);
    console.log(`❌ CamelCase fields: ${issues.camelCaseFields} users`);
    console.log(`❌ Date inconsistency: ${issues.dateInconsistency} users`);
    console.log(`❌ Membership duplication: ${issues.membershipDuplication} users`);
    
    const totalIssues = Object.values(issues).reduce((sum, count) => sum + count, 0);
    console.log(`\n📊 TOTAL ISSUES FOUND: ${totalIssues}`);
    
    if (totalIssues > 0) {
      console.log('\n🚨 RECOMMENDATION: Run comprehensiveCleanup() to fix all issues');
    } else {
      console.log('\n✅ No issues found! Data is clean.');
    }
    
  } catch (error) {
    console.error('💥 Audit failed:', error);
  }
}

// Quick check for specific user
async function auditSingleUser(userId) {
  console.log(`🔍 Auditing single user: ${userId}`);
  
  try {
    const db = firebase.firestore();
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      console.error(`❌ User ${userId} not found`);
      return;
    }
    
    const data = userDoc.data();
    
    console.log('\n📋 FULL DATA STRUCTURE:');
    console.log(JSON.stringify(data, null, 2));
    
    console.log('\n🔍 ISSUE ANALYSIS:');
    
    // Check for all issues
    const issues = [];
    
    if (data.firebase_uid) issues.push('firebase_uid exists');
    if (data.id && data.id !== userId) issues.push('id conflicts with doc ID');
    if (data.auth_uid && data.auth_uid !== userId) issues.push('auth_uid mismatch');
    
    const photoFields = ['photo_url', 'photoUrl', 'profile_picture', 'profilePicture'].filter(f => data[f]);
    if (photoFields.length > 1) issues.push(`multiple photo fields: ${photoFields.join(', ')}`);
    
    const privacyFields = ['is_photo_private', 'isPhotoPrivate'].filter(f => data[f]);
    if (privacyFields.length > 1) issues.push(`multiple privacy fields: ${privacyFields.join(', ')}`);
    
    const rootFields = ['first_name', 'last_name', 'city'].filter(f => data[f]);
    if (rootFields.length > 0 && data.profile) issues.push(`root fields with profile object: ${rootFields.join(', ')}`);
    
    if (data.last_active && typeof data.last_active === 'string') issues.push('last_active is string');
    
    const membershipFields = ['membership_tier', 'membership_status', 'membership_expires_at'].filter(f => data[f]);
    if (membershipFields.length > 0 && data.membership_json) issues.push(`membership duplication: ${membershipFields.join(', ')}`);
    
    if (issues.length > 0) {
      console.log('\n❌ ISSUES FOUND:');
      issues.forEach(issue => console.log(`  - ${issue}`));
    } else {
      console.log('\n✅ No issues found!');
    }
    
  } catch (error) {
    console.error(`❌ Audit failed for ${userId}:`, error);
  }
}

console.log('🚀 Data Audit Script Loaded!');
console.log('📝 Available functions:');
console.log('  auditData() - Audit first 10 users');
console.log('  auditSingleUser(userId) - Audit specific user');
console.log('\n🔥 USAGE: auditData()');
