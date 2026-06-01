import 'package:flutter_test/flutter_test.dart';
import 'package:brahmin_vivaaha_vedika/services/pincode_service.dart';

void main() {
  group('PinCodeService.parseResponseBody', () {
    test('parses success response with multiple post offices', () {
      const body = '''
[
  {
    "Status": "Success",
    "PostOffice": [
      {
        "Name": "Benz Circle",
        "District": "Krishna",
        "State": "Andhra Pradesh",
        "Country": "India"
      },
      {
        "Name": "Governorpet",
        "District": "Krishna",
        "State": "Andhra Pradesh",
        "Country": "India"
      }
    ]
  }
]
''';

      final result = PinCodeService.parseResponseBody(body);
      expect(result, isNotNull);
      expect(result!.postOffices.length, 2);
      expect(result.primary.state, 'Andhra Pradesh');
      expect(result.primary.district, 'Krishna');
      expect(result.primary.name, 'Benz Circle');
      expect(result.hasMultipleAreas, isTrue);
      expect(result.areaNames, contains('Benz Circle'));
      expect(result.areaNames, contains('Governorpet'));
    });

    test('returns null when status is not success', () {
      const body = '''
[{"Status": "Error", "Message": "Invalid PIN"}]
''';
      expect(PinCodeService.parseResponseBody(body), isNull);
    });

    test('returns null for empty post office list', () {
      const body = '''
[{"Status": "Success", "PostOffice": []}]
''';
      expect(PinCodeService.parseResponseBody(body), isNull);
    });

    test('uses Circle when State is missing', () {
      const body = '''
[
  {
    "Status": "Success",
    "PostOffice": {
      "Name": "Main SO",
      "District": "Krishna",
      "Circle": "Andhra Pradesh",
      "Region": "Vijayawada"
    }
  }
]
''';
      final result = PinCodeService.parseResponseBody(body);
      expect(result, isNotNull);
      expect(result!.primary.state, 'Andhra Pradesh');
      expect(result.primary.circle, 'Andhra Pradesh');
    });
  });

  group('PinCodeService.parseCloudPayload', () {
    test('parses cloud payload when offices key is used (Firestore cache)', () {
      final result = PinCodeService.parseCloudPayload({
        'success': true,
        'pin': '520010',
        'offices': [
          {
            'name': 'Benz Circle',
            'district': 'Krishna',
            'state': 'Andhra Pradesh',
            'matchedState': 'Andhra Pradesh',
            'country': 'India',
            'region': 'Vijayawada',
            'city': 'Vijayawada',
          },
        ],
      });
      expect(result, isNotNull);
      expect(result!.postOffices.length, 1);
      expect(result.primary.suggestedCity, 'Vijayawada');
    });

    test('parses normalized cloud success payload', () {
      final result = PinCodeService.parseCloudPayload({
        'success': true,
        'pin': '110001',
        'state': 'Delhi',
        'city': 'New Delhi',
        'area': 'Connaught Place',
        'country': 'India',
        'district': 'Central Delhi',
        'areas': ['Connaught Place', 'Janpath'],
        'postOffices': [
          {
            'name': 'Connaught Place',
            'district': 'Central Delhi',
            'state': 'Delhi',
            'matchedState': 'Delhi',
            'country': 'India',
            'region': 'Delhi',
            'city': 'New Delhi',
            'area': 'Connaught Place',
          },
          {
            'name': 'Janpath',
            'district': 'Central Delhi',
            'state': 'Delhi',
            'country': 'India',
            'region': 'Delhi',
          },
        ],
      });
      expect(result, isNotNull);
      expect(result!.postOffices.length, 2);
      expect(result.primary.name, 'Connaught Place');
      expect(result.hasMultipleAreas, isTrue);
    });

    test('builds offices from areas when postOffices list is empty', () {
      final result = PinCodeService.parseCloudPayload({
        'success': true,
        'pin': '500001',
        'state': 'Telangana',
        'matchedState': 'Telangana',
        'city': 'Hyderabad',
        'district': 'Hyderabad',
        'country': 'India',
        'areas': ['Abids', 'Koti'],
      });
      expect(result, isNotNull);
      expect(result!.postOffices.length, 2);
      expect(result.primary.name, 'Abids');
      expect(result.primary.district, 'Hyderabad');
    });

    test('parses office with area but no name', () {
      final result = PinCodeService.parseCloudPayload({
        'success': true,
        'postOffices': [
          {
            'area': 'Sector 18',
            'district': 'Gautam Buddha Nagar',
            'state': 'Uttar Pradesh',
            'matchedState': 'Uttar Pradesh',
            'city': 'Noida',
          },
        ],
      });
      expect(result, isNotNull);
      expect(result!.primary.name, 'Sector 18');
      expect(result.primary.suggestedCity, 'Noida');
    });

    test('maps cloud error codes to fetch status', () {
      expect(
        PinCodeService.statusFromCloudPayload({'success': false, 'error': 'invalid'})
            ?.status,
        PinCodeFetchStatus.invalid,
      );
      expect(
        PinCodeService.statusFromCloudPayload({'success': false, 'error': 'timeout'})
            ?.status,
        PinCodeFetchStatus.networkTimeout,
      );
      expect(
        PinCodeService.statusFromCloudPayload(
          {'success': false, 'error': 'unavailable'},
        )?.status,
        PinCodeFetchStatus.unknown,
      );
    });
  });

  group('PinCodeService.coercePayloadMap', () {
    test('accepts Map<String, dynamic>', () {
      final m = PinCodeService.coercePayloadMap({'success': true});
      expect(m, isNotNull);
      expect(m!['success'], isTrue);
    });

    test('accepts Map<Object?, Object?>', () {
      final m = PinCodeService.coercePayloadMap(<Object?, Object?>{
        'success': true,
        'pin': '110001',
      });
      expect(m, isNotNull);
      expect(m!['pin'], '110001');
    });

    test('returns null for non-map', () {
      expect(PinCodeService.coercePayloadMap(null), isNull);
      expect(PinCodeService.coercePayloadMap('text'), isNull);
    });
  });

  group('PinCodeService.isTruthySuccess', () {
    test('accepts common success representations', () {
      expect(PinCodeService.isTruthySuccess(true), isTrue);
      expect(PinCodeService.isTruthySuccess(1), isTrue);
      expect(PinCodeService.isTruthySuccess('true'), isTrue);
      expect(PinCodeService.isTruthySuccess('Success'), isTrue);
      expect(PinCodeService.isTruthySuccess(false), isFalse);
      expect(PinCodeService.isTruthySuccess('no'), isFalse);
    });
  });

  group('PinCodeService helpers', () {
    setUp(PinCodeService.clearMemoryCacheForTests);

    test('cache key uses versioned format', () {
      expect(PinCodeService.cacheKeyForPin('520010'), 'pincode_v2_520010');
    });

    test('normalizePin strips non-digits', () {
      expect(PinCodeService.normalizePin('52 00-10'), '520010');
    });

    test('lookup uses memory cache without network when seeded', () async {
      const body = '''
[{"Status":"Success","PostOffice":[{"Name":"A","District":"Krishna","State":"Andhra Pradesh"}]}]
''';
      final parsed = PinCodeService.parseResponseBody(body)!;
      PinCodeService.seedMemoryCacheForTests('520010', parsed);

      expect(await PinCodeService.hasCachedResult('520010'), isTrue);

      final response = await PinCodeService.lookup('520010');
      expect(response.status, PinCodeFetchStatus.success);
      expect(response.source, PinCodeLookupSource.memory);
      expect(response.fromCache, isTrue);
    });
  });

  group('PinCodeFetchResponse.userMessage', () {
    test('maps statuses to friendly copy', () {
      expect(PinCodeFetchResponse.invalid().userMessage, 'Invalid PIN code.');
      expect(
        PinCodeFetchResponse.malformed().userMessage,
        'Unable to verify PIN. Please try again.',
      );
      expect(
        PinCodeFetchResponse.networkTimeout().userMessage,
        'PIN lookup timed out. Please try again.',
      );
      expect(
        PinCodeFetchResponse.unknown().userMessage,
        'Unable to verify PIN. Please try again.',
      );
    });
  });
}
