import '../models/user.dart';
import '../models/gender.dart';
import 'profile_field_mapping.dart';
import 'package:flutter/foundation.dart';

/// Profile field verification utility
/// Verifies that all profile fields are properly mapped between camelCase and snake_case
class ProfileFieldVerification {
  
  /// Verify all UserProfile fields have proper mappings
  static void verifyAllFieldMappings() {
    debugPrint('🔍 Verifying profile field mappings...');
    
    // Get all field names from UserProfile.toJson()
    final userProfile = UserProfile(
      firstName: 'Test',
      lastName: 'User',
      // Add minimal required fields for testing
      gender: Gender.male,
      dateOfBirth: DateTime.now(),
      // ... other fields with test data
    );
    
    final profileJson = userProfile.toJson();
    debugPrint('📋 Total profile fields: ${profileJson.length}');
    
    // Check each field for proper camelCase to snake_case mapping
    int mappedFields = 0;
    int unmappedFields = 0;
    
    profileJson.forEach((camelCaseKey, value) {
      final snakeCaseKey = ProfileFieldMapping.toSnakeCase(camelCaseKey);
      final backToCamelCase = ProfileFieldMapping.toCamelCase(snakeCaseKey);
      
      if (snakeCaseKey != camelCaseKey && backToCamelCase == camelCaseKey) {
        mappedFields++;
        debugPrint('✅ $camelCaseKey → $snakeCaseKey → $backToCamelCase');
      } else if (snakeCaseKey == camelCaseKey) {
        debugPrint('ℹ️  $camelCaseKey (no conversion needed)');
        mappedFields++;
      } else {
        unmappedFields++;
        debugPrint('❌ $camelCaseKey → $snakeCaseKey → $backToCamelCase (MISMATCH!)');
      }
    });
    
    debugPrint('📊 Mapping Summary:');
    debugPrint('   - Mapped fields: $mappedFields');
    debugPrint('   - Unmapped fields: $unmappedFields');
    debugPrint('   - Success rate: ${((mappedFields / profileJson.length) * 100).toStringAsFixed(1)}%');
    
    if (unmappedFields > 0) {
      debugPrint('⚠️  WARNING: $unmappedFields fields are not properly mapped!');
    } else {
      debugPrint('✅ All fields are properly mapped!');
    }
  }
  
  /// Test conversion of sample profile data
  static void testProfileDataConversion() {
    debugPrint('🧪 Testing profile data conversion...');
    
    // Sample profile data in camelCase
    final camelCaseProfile = {
      'first_name': 'John',
      'last_name': 'Doe',
      'date_of_birth': '1990-01-01T00:00:00.000Z',
      'placeOfBirth': 'Mumbai',
      'education': 'Engineering',
      'occupation': 'Software Developer',
      'incomeRange': '10-15 Lakhs',
      'maritalStatus': 'Never Married',
      'familyType': 'Joint Family',
      'partnerAgeMin': 25,
      'partnerAgeMax': 30,
      'profilePicture': 'https://example.com/photo.jpg',
      'isPhotoPrivate': false,
    };
    
    debugPrint('📤 Original camelCase data:');
    camelCaseProfile.forEach((key, value) => debugPrint('   $key: $value'));
    
    // Convert to snake_case for database
    final snakeCaseProfile = ProfileFieldMapping.convertProfileToSnakeCase(camelCaseProfile);
    debugPrint('\n📥 Converted snake_case data:');
    snakeCaseProfile.forEach((key, value) => debugPrint('   $key: $value'));
    
    // Convert back to camelCase for app
    final backToCamelCase = ProfileFieldMapping.convertProfileToCamelCase(snakeCaseProfile);
    debugPrint('\n🔄 Back to camelCase:');
    backToCamelCase.forEach((key, value) => debugPrint('   $key: $value'));
    
    // Verify round-trip conversion
    bool isRoundTripSuccessful = true;
    camelCaseProfile.forEach((key, value) {
      if (backToCamelCase[key] != value) {
        isRoundTripSuccessful = false;
        debugPrint('❌ Round-trip failed for $key: $value → ${backToCamelCase[key]}');
      }
    });
    
    if (isRoundTripSuccessful) {
      debugPrint('✅ Round-trip conversion successful!');
    } else {
      debugPrint('❌ Round-trip conversion failed!');
    }
  }
  
  /// Generate SQL examples for database operations
  static void generateSqlExamples() {
    debugPrint('\n🗄️  SQL Examples for Database Operations:');
    
    final userId = '2f0da0dc-ed8e-4057-8834-f21ead3a755f';
    
    // Example 1: Update single field
    debugPrint('\n-- Example 1: Update single field');
    debugPrint('SELECT update_profile_field(');
    debugPrint("    '$userId'::UUID,");
    debugPrint("    'first_name',");
    debugPrint("    'John Doe'");
    debugPrint(');');
    
    // Example 2: Update multiple fields
    debugPrint('\n-- Example 2: Update multiple fields');
    debugPrint('SELECT update_profile_fields(');
    debugPrint("    '$userId'::UUID,");
    debugPrint("    '{");
    debugPrint('        "first_name": "John",');
    debugPrint('        "last_name": "Doe",');
    debugPrint('        "city": "Mumbai",');
    debugPrint('        "occupation": "Software Developer"');
    debugPrint("    }'::JSONB");
    debugPrint(');');
    
    // Example 3: Direct SQL update
    debugPrint('\n-- Example 3: Direct SQL update');
    debugPrint('UPDATE users');
    debugPrint('SET profile = jsonb_set(');
    debugPrint('    profile,');
    debugPrint("    '{first_name}',");
    debugPrint("    '\"John Doe\"'::jsonb");
    debugPrint('),');
    debugPrint('updated_at = NOW()');
    debugPrint("WHERE id = '$userId'::UUID;");
    
    // Example 4: Update multiple fields directly
    debugPrint('\n-- Example 4: Update multiple fields directly');
    debugPrint('UPDATE users');
    debugPrint('SET profile = profile || ');
    debugPrint("    '{");
    debugPrint('        "first_name": "John",');
    debugPrint('        "last_name": "Doe",');
    debugPrint('        "city": "Mumbai",');
    debugPrint('        "occupation": "Software Developer"');
    debugPrint("    }'::jsonb,");
    debugPrint('    updated_at = NOW()');
    debugPrint("WHERE id = '$userId'::UUID;");
  }
  
  /// Run all verification tests
  static void runAllTests() {
    debugPrint('🚀 Starting comprehensive profile field verification...\n');
    
    verifyAllFieldMappings();
    debugPrint('\n${'='*50}');
    
    testProfileDataConversion();
    debugPrint('\n${'='*50}');
    
    generateSqlExamples();
    
    debugPrint('\n✅ Profile field verification complete!');
  }
}
