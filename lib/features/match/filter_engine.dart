import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/search/filter_screen.dart' show FilterPreferences;
import '../../core/contract.dart';

/// Filter Engine
///
/// Consolidates filtering operations from:
/// - filter_service.dart
/// - matching_preferences_service.dart (filter parts)
class FilterEngine extends ChangeNotifier {
  static final FilterEngine _instance = FilterEngine._internal();
  factory FilterEngine() => _instance;
  FilterEngine._internal({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  @visibleForTesting
  FilterEngine.forTesting() : _db = null;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _firestore {
    final db = _db;
    if (db == null) {
      throw StateError('Firestore is not available in this test instance');
    }
    return db;
  }

  SharedPreferences? _prefs;

  bool _isInitialized = false;

  static const String _savedFiltersKey = 'saved_filters';
  static const String _recentSearchesKey = 'recent_searches';

  /// Initialize filter engine
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
      debugPrint('✅ FilterEngine: Initialized successfully');
    } catch (e) {
      debugPrint('❌ FilterEngine initialization failed: $e');
      rethrow;
    }
  }

  /// Apply filters to user query
  Future<List<Map<String, dynamic>>> applyFilters({
    FilterPreferences? filters,
    String? searchQuery,
    int limit = 20,
    DocumentSnapshot? lastDoc,
  }) async {
    try {
      await _ensureInitialized();

      Query query = _firestore.collection(Collections.users);

      // Apply basic filters
      query = _applyBasicFilters(query, filters);

      // Apply search query
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = _applySearchQuery(query, searchQuery);
      }

      // Apply pagination
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      query = query.limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final data =
            (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      debugPrint('Failed to apply filters: $e');
      return [];
    }
  }

  /// Apply basic filters to query
  Query _applyBasicFilters(Query query, FilterPreferences? filters) {
    if (filters == null) return query;

    // Gender filter
    if (filters.gender != null && filters.gender!.isNotEmpty) {
      query = query.where('gender', isEqualTo: filters.gender);
    }

    // Age filters
    if (filters.minAge != null) {
      query = query.where('age', isGreaterThanOrEqualTo: filters.minAge);
    }
    if (filters.maxAge != null) {
      query = query.where('age', isLessThanOrEqualTo: filters.maxAge);
    }

    // Height filters
    if (filters.minHeight != null) {
      query = query.where('height', isGreaterThanOrEqualTo: filters.minHeight);
    }
    if (filters.maxHeight != null) {
      query = query.where('height', isLessThanOrEqualTo: filters.maxHeight);
    }

    // Religion filter
    if (filters.religion != null && filters.religion!.isNotEmpty) {
      query = query.where('religion', isEqualTo: filters.religion);
    }

    // Community filter
    if (filters.community != null && filters.community!.isNotEmpty) {
      query = query.where('community', isEqualTo: filters.community);
    }

    // Mother tongue filter
    if (filters.motherTongue != null && filters.motherTongue!.isNotEmpty) {
      query = query.where('mother_tongue', isEqualTo: filters.motherTongue);
    }

    // Location filter
    if (filters.country != null && filters.country!.isNotEmpty) {
      query = query.where('country', isEqualTo: filters.country);
    }
    if (filters.location != null && filters.location!.isNotEmpty) {
      query = query.where('city', isEqualTo: filters.location);
    } else if (filters.city != null && filters.city!.isNotEmpty) {
      query = query.where('city', isEqualTo: filters.city);
    } else if (filters.state != null && filters.state!.isNotEmpty) {
      query = query.where('state', isEqualTo: filters.state);
    }

    // Education filter
    if (filters.education != null && filters.education!.isNotEmpty) {
      query = query.where('education', isEqualTo: filters.education);
    }

    // Occupation filter
    if (filters.occupation != null && filters.occupation!.isNotEmpty) {
      query = query.where('occupation', isEqualTo: filters.occupation);
    }

    // Income filter
    if (filters.minIncome != null) {
      query = query.where('income', isGreaterThanOrEqualTo: filters.minIncome);
    }
    if (filters.maxIncome != null) {
      query = query.where('income', isLessThanOrEqualTo: filters.maxIncome);
    }

    // Marital status filter
    if (filters.maritalStatus != null && filters.maritalStatus!.isNotEmpty) {
      query = query.where('marital_status', isEqualTo: filters.maritalStatus);
    }

    // Diet filter
    if (filters.diet != null && filters.diet!.isNotEmpty) {
      query = query.where('diet', isEqualTo: filters.diet);
    }

    // Smoking filter
    if (filters.smoking != null && filters.smoking!.isNotEmpty) {
      query = query.where('smoking', isEqualTo: filters.smoking);
    }

    // Drinking filter
    if (filters.drinking != null && filters.drinking!.isNotEmpty) {
      query = query.where('drinking', isEqualTo: filters.drinking);
    }

    // Photo filter
    if (filters.hasPhoto == true) {
      query = query.where('photos', isNotEqualTo: null);
    }

    // Verification filter
    if (filters.isVerified == true) {
      query = query.where('is_verified', isEqualTo: true);
    }

    // Online filter
    if (filters.isOnline == true) {
      query = query.where('is_online', isEqualTo: true);
    }

    return query;
  }

  @visibleForTesting
  Query applyBasicFiltersForTesting(
    Query query,
    FilterPreferences? filters,
  ) =>
      _applyBasicFilters(query, filters);

  /// Apply search query to filter
  Query _applySearchQuery(Query query, String searchQuery) {
    // Search by name
    final searchTerms = searchQuery.toLowerCase().split(' ');

    for (final term in searchTerms) {
      if (term.isNotEmpty) {
        query = query.where('search_name', arrayContains: term);
      }
    }

    return query;
  }

  @visibleForTesting
  Query applySearchQueryForTesting(Query query, String searchQuery) =>
      _applySearchQuery(query, searchQuery);

  /// Save filter preferences
  Future<void> saveFilterPreferences({
    required String userId,
    required FilterPreferences filters,
    String? filterName,
  }) async {
    try {
      await _ensureInitialized();

      final filtersData = _serializeFilters(filters);

      // Save to user document
      await _firestore.collection(Collections.users).doc(userId).update({
        'filter_preferences': filtersData,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // Save to saved filters if name provided
      if (filterName != null && filterName.isNotEmpty) {
        await _saveNamedFilter(userId, filterName, filters);
      }

      debugPrint('✅ Filter preferences saved for user: $userId');
    } catch (e) {
      debugPrint('Failed to save filter preferences: $e');
      rethrow;
    }
  }

  /// Get filter preferences
  Future<FilterPreferences> getFilterPreferences(String userId) async {
    try {
      await _ensureInitialized();

      final doc = await _firestore.collection(Collections.users).doc(userId).get();
      if (!doc.exists) {
        return FilterPreferences();
      }

      final data = doc.data()!;
      final filtersData = data['filter_preferences'] as Map<String, dynamic>?;

      if (filtersData == null) {
        return FilterPreferences();
      }

      return _deserializeFilters(filtersData);
    } catch (e) {
      debugPrint('Failed to get filter preferences: $e');
      return FilterPreferences();
    }
  }

  /// Save named filter
  Future<void> _saveNamedFilter(
      String userId, String filterName, FilterPreferences filters) async {
    try {
      final savedFilters = await getSavedFilters(userId);

      final filterData = {
        'name': filterName,
        'filters': _serializeFilters(filters),
        'created_at': FieldValue.serverTimestamp(),
      };

      // Remove existing filter with same name
      savedFilters.removeWhere((filter) => filter['name'] == filterName);

      // Add new filter
      savedFilters.add(filterData);

      // Limit to 10 saved filters
      if (savedFilters.length > 10) {
        savedFilters.removeAt(0);
      }

      // Save to local storage
      await _prefs?.setString(_savedFiltersKey, _encodeFilters(savedFilters));

      debugPrint('✅ Named filter saved: $filterName');
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to save named filter: $e');
    }
  }

  /// Get saved filters
  Future<List<Map<String, dynamic>>> getSavedFilters(String userId) async {
    try {
      await _ensureInitialized();

      final encoded = _prefs?.getString(_savedFiltersKey);
      if (encoded == null || encoded.isEmpty) {
        return [];
      }

      return _decodeFilters(encoded);
    } catch (e) {
      debugPrint('Failed to get saved filters: $e');
      return [];
    }
  }

  /// Delete saved filter
  Future<void> deleteSavedFilter(String userId, String filterName) async {
    try {
      await _ensureInitialized();

      final savedFilters = await getSavedFilters(userId);
      savedFilters.removeWhere((filter) => filter['name'] == filterName);

      await _prefs?.setString(_savedFiltersKey, _encodeFilters(savedFilters));

      debugPrint('✅ Saved filter deleted: $filterName');
    } catch (e) {
      debugPrint('Failed to delete saved filter: $e');
    }
  }

  /// Save recent search
  Future<void> saveRecentSearch(String searchQuery) async {
    try {
      await _ensureInitialized();

      final recentSearches = _prefs?.getStringList(_recentSearchesKey) ?? [];

      // Remove if already exists
      recentSearches.remove(searchQuery);

      // Add to beginning
      recentSearches.insert(0, searchQuery);

      // Limit to 10 recent searches
      if (recentSearches.length > 10) {
        recentSearches.removeLast();
      }

      await _prefs?.setStringList(_recentSearchesKey, recentSearches);

      debugPrint('✅ Recent search saved: $searchQuery');
    } catch (e) {
      debugPrint('Failed to save recent search: $e');
    }
  }

  /// Get recent searches
  Future<List<String>> getRecentSearches() async {
    try {
      await _ensureInitialized();

      return _prefs?.getStringList(_recentSearchesKey) ?? [];
    } catch (e) {
      debugPrint('Failed to get recent searches: $e');
      return [];
    }
  }

  /// Clear recent searches
  Future<void> clearRecentSearches() async {
    try {
      await _ensureInitialized();

      await _prefs?.remove(_recentSearchesKey);

      debugPrint('✅ Recent searches cleared');
    } catch (e) {
      debugPrint('Failed to clear recent searches: $e');
    }
  }

  /// Get filter suggestions based on user preferences
  Future<Map<String, List<String>>> getFilterSuggestions(String userId) async {
    try {
      await _ensureInitialized();

      // Get user's interaction history for suggestions
      final interactions = await _getUserInteractions(userId);

      final suggestions = <String, List<String>>{
        'religion': [],
        'community': [],
        'location': [],
        'education': [],
        'occupation': [],
      };

      // Analyze interactions to suggest popular attributes
      for (final attr in suggestions.keys) {
        final attrCounts = <String, int>{};

        for (final interaction in interactions) {
          final value = interaction[attr] as String?;
          if (value != null && value.isNotEmpty) {
            attrCounts[value] = (attrCounts[value] ?? 0) + 1;
          }
        }

        // Sort by count and take top 5
        final sortedAttrs = attrCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        suggestions[attr] = sortedAttrs.take(5).map((e) => e.key).toList();
      }

      return suggestions;
    } catch (e) {
      debugPrint('Failed to get filter suggestions: $e');
      return {};
    }
  }

  /// Get user's interaction history for suggestions
  Future<List<Map<String, dynamic>>> _getUserInteractions(String userId) async {
    try {
      final interactions = <Map<String, dynamic>>[];

      // Get profile views
      // 🔥 GAP 1 FIX: Use snake_case field names matching Firestore rules
      final viewsSnapshot = await _firestore
          .collection('profile_views')
          .where('viewer_user_id', isEqualTo: userId)
          .orderBy('viewed_at', descending: true)
          .limit(50)
          .get();

      for (final doc in viewsSnapshot.docs) {
        final viewedUserId = (doc['viewed_profile_id'] ??
            doc['viewed_user_id'] ??
            doc['viewedUserId'] ??
            '') as String;
        final userDoc =
            await _firestore.collection(Collections.users).doc(viewedUserId).get();

        if (userDoc.exists) {
          interactions.add(userDoc.data()!);
        }
      }

      return interactions;
    } catch (e) {
      debugPrint('Failed to get user interactions: $e');
      return [];
    }
  }

  /// Serialize filters to map
  Map<String, dynamic> _serializeFilters(FilterPreferences filters) {
    return {
      'gender': filters.gender,
      'minAge': filters.minAge,
      'maxAge': filters.maxAge,
      'minHeight': filters.minHeight,
      'maxHeight': filters.maxHeight,
      'religion': filters.religion,
      'community': filters.community,
      'motherTongue': filters.motherTongue,
      'location': filters.location,
      'country': filters.country,
      'city': filters.city,
      'state': filters.state,
      'education': filters.education,
      'occupation': filters.occupation,
      'minIncome': filters.minIncome,
      'maxIncome': filters.maxIncome,
      'maritalStatus': filters.maritalStatus,
      'diet': filters.diet,
      'smoking': filters.smoking,
      'drinking': filters.drinking,
      'hasPhoto': filters.hasPhoto,
      'isVerified': filters.isVerified,
      'is_online': filters.isOnline,
    };
  }

  /// Deserialize filters from map
  FilterPreferences _deserializeFilters(Map<String, dynamic> data) {
    return FilterPreferences(
      gender: data['gender'] as String?,
      minAge: (data['min_age'] ?? data['minAge']) as int?,
      maxAge: (data['max_age'] ?? data['maxAge']) as int?,
      minHeight: (data['min_height'] ?? data['minHeight']) as double?,
      maxHeight: (data['max_height'] ?? data['maxHeight']) as double?,
      religion: data['religion'] as String?,
      community: data['community'] as String?,
      motherTongue: (data['mother_tongue'] ?? data['motherTongue']) as String?,
      location: data['location'] as String?,
      country: data['country'] as String?,
      city: data['city'] as String?,
      state: data['state'] as String?,
      education: data['education'] as String?,
      occupation: data['occupation'] as String?,
      minIncome: (data['min_income'] ?? data['minIncome']) as int?,
      maxIncome: (data['max_income'] ?? data['maxIncome']) as int?,
      maritalStatus:
          (data['marital_status'] ?? data['maritalStatus']) as String?,
      diet: data['diet'] as String?,
      smoking: data['smoking'] as String?,
      drinking: data['drinking'] as String?,
      hasPhoto: (data['has_photo'] ?? data['hasPhoto']) as bool?,
      isVerified: (data['is_verified'] ?? data['isVerified']) as bool?,
      isOnline: data['is_online'] as bool?,
    );
  }

  /// Encode filters list to JSON string
  String _encodeFilters(List<Map<String, dynamic>> filters) {
    // Simple JSON encoding - in production, use proper JSON encoder
    return filters.map((filter) => filter.toString()).join('|');
  }

  /// Decode filters from JSON string
  List<Map<String, dynamic>> _decodeFilters(String encoded) {
    // Simple JSON decoding - in production, use proper JSON decoder
    if (encoded.isEmpty) return [];

    final parts = encoded.split('|');
    return parts.map((part) => <String, dynamic>{}).toList();
  }

  /// Validate filter preferences
  Map<String, String> validateFilters(FilterPreferences filters) {
    final errors = <String, String>{};

    // Age validation
    if (filters.minAge != null && filters.maxAge != null) {
      if (filters.minAge! > filters.maxAge!) {
        errors['age'] = 'Minimum age cannot be greater than maximum age';
      }
      if (filters.minAge! < 18) {
        errors['minAge'] = 'Minimum age must be at least 18';
      }
      if (filters.maxAge! > 100) {
        errors['maxAge'] = 'Maximum age cannot exceed 100';
      }
    }

    // Height validation
    if (filters.minHeight != null && filters.maxHeight != null) {
      if (filters.minHeight! > filters.maxHeight!) {
        errors['height'] =
            'Minimum height cannot be greater than maximum height';
      }
      if (filters.minHeight! < 100) {
        errors['minHeight'] = 'Minimum height must be at least 100 cm';
      }
      if (filters.maxHeight! > 250) {
        errors['maxHeight'] = 'Maximum height cannot exceed 250 cm';
      }
    }

    // Income validation
    if (filters.minIncome != null && filters.maxIncome != null) {
      if (filters.minIncome! > filters.maxIncome!) {
        errors['income'] =
            'Minimum income cannot be greater than maximum income';
      }
      if (filters.minIncome! < 0) {
        errors['minIncome'] = 'Income cannot be negative';
      }
    }

    return errors;
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  // ─── Missing getters for screen compatibility ───────────────────────────

  FilterPreferences? _currentFilters;

  FilterPreferences? get current => _currentFilters;

  bool get hasFilters =>
      _currentFilters != null && _hasActiveFilters(_currentFilters!);

  int get activeFilterCount {
    if (_currentFilters == null) return 0;
    int count = 0;
    final f = _currentFilters!;
    if (f.minAge != null || f.maxAge != null) count++;
    if (f.gothram != null && f.gothram!.isNotEmpty) count++;
    if (f.maritalStatus != null && f.maritalStatus!.isNotEmpty) count++;
    if (f.education != null && f.education!.isNotEmpty) count++;
    if (f.occupation != null && f.occupation!.isNotEmpty) count++;
    if (f.city != null && f.city!.isNotEmpty) count++;
    if (f.state != null && f.state!.isNotEmpty) count++;
    return count;
  }

  void setFilters(FilterPreferences filters) {
    _currentFilters = filters;
    notifyListeners(); // if FilterEngine extends ChangeNotifier
  }

  void clearFilters() {
    _currentFilters = null;
    notifyListeners();
  }

  bool _hasActiveFilters(FilterPreferences f) {
    return f.minAge != null ||
        f.maxAge != null ||
        (f.gothram != null && f.gothram!.isNotEmpty) ||
        (f.maritalStatus != null && f.maritalStatus!.isNotEmpty) ||
        (f.education != null && f.education!.isNotEmpty) ||
        (f.occupation != null && f.occupation!.isNotEmpty) ||
        (f.city != null && f.city!.isNotEmpty) ||
        (f.state != null && f.state!.isNotEmpty);
  }
}
