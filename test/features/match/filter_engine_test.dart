import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:brahmin_vivaaha_vedika/features/match/filter_engine.dart';
import 'package:brahmin_vivaaha_vedika/screens/search/filter_screen.dart';

class MockUserQuery extends Mock implements Query<Map<String, dynamic>> {
  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return super.noSuchMethod(
      Invocation.method(
        #where,
        [field],
        {
          if (isEqualTo != null) #isEqualTo: isEqualTo,
          if (isNotEqualTo != null) #isNotEqualTo: isNotEqualTo,
          if (isLessThan != null) #isLessThan: isLessThan,
          if (isLessThanOrEqualTo != null)
            #isLessThanOrEqualTo: isLessThanOrEqualTo,
          if (isGreaterThan != null) #isGreaterThan: isGreaterThan,
          if (isGreaterThanOrEqualTo != null)
            #isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
          if (arrayContains != null) #arrayContains: arrayContains,
          if (arrayContainsAny != null) #arrayContainsAny: arrayContainsAny,
          if (whereIn != null) #whereIn: whereIn,
          if (whereNotIn != null) #whereNotIn: whereNotIn,
          if (isNull != null) #isNull: isNull,
        },
      ),
      returnValue: this,
      returnValueForMissingStub: this,
    ) as Query<Map<String, dynamic>>;
  }
}

void main() {
  group('FilterEngine', () {
    late FilterEngine engine;
    late MockUserQuery query;

    setUp(() {
      engine = FilterEngine.forTesting();
      query = MockUserQuery();
    });

    test('returns original query when filters are null', () {
      final result = engine.applyBasicFiltersForTesting(query, null);

      expect(result, same(query));
      verifyZeroInteractions(query);
    });

    test('applies demographic and status filters to Firestore query', () {
      const filters = FilterPreferences(
        gender: 'female',
        minAge: 23,
        maxAge: 30,
        religion: 'Hindu',
        city: 'Hyderabad',
        hasPhoto: true,
        isVerified: true,
        isOnline: true,
      );

      final result = engine.applyBasicFiltersForTesting(query, filters);

      expect(result, same(query));
      verify(query.where('gender', isEqualTo: 'female')).called(1);
      verify(query.where('age', isGreaterThanOrEqualTo: 23)).called(1);
      verify(query.where('age', isLessThanOrEqualTo: 30)).called(1);
      verify(query.where('religion', isEqualTo: 'Hindu')).called(1);
      verify(query.where('city', isEqualTo: 'Hyderabad')).called(1);
      verify(query.where('photos', isNotEqualTo: null)).called(1);
      verify(query.where('is_verified', isEqualTo: true)).called(1);
      verify(query.where('is_online', isEqualTo: true)).called(1);
    });

    test('prefers location over city and state filters', () {
      const filters = FilterPreferences(
        location: 'Bengaluru',
        city: 'Hyderabad',
        state: 'Telangana',
      );

      engine.applyBasicFiltersForTesting(query, filters);

      verify(query.where('city', isEqualTo: 'Bengaluru')).called(1);
      verifyNever(query.where('city', isEqualTo: 'Hyderabad'));
      verifyNever(query.where('state', isEqualTo: 'Telangana'));
    });

    test('applies non-empty search terms with arrayContains', () {
      final result = engine.applySearchQueryForTesting(query, 'rama  rao');

      expect(result, same(query));
      verify(query.where('search_name', arrayContains: 'rama')).called(1);
      verify(query.where('search_name', arrayContains: 'rao')).called(1);
    });
  });
}
