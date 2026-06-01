import 'dart:convert';

import 'package:http/http.dart' as http;

import 'astrology_service.dart';

class AstroApiConfig {
  const AstroApiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.userId,
  });

  final String baseUrl;
  final String apiKey;
  final String userId;
}

class AstrologyApiProvider implements AstrologyProvider {
  AstrologyApiProvider({
    required AstroApiConfig config,
    http.Client? client,
    AstrologyProvider? fallback,
  })  : _config = config,
        _client = client ?? http.Client(),
        _fallback = fallback ?? FallbackAstrologyProvider();

  final AstroApiConfig _config;
  final http.Client _client;
  final AstrologyProvider _fallback;

  @override
  Future<AstrologyDetails> compute({
    required DateTime birthDateTime,
    double? latitude,
    double? longitude,
  }) async {
    final uri = Uri.parse('${_config.baseUrl}/nakshatra_pada');
    final body = json.encode({
      'datetime': birthDateTime.toIso8601String(),
      'latitude': latitude ?? 13.0827,
      'longitude': longitude ?? 80.2707,
    });

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-API-KEY': _config.apiKey,
          'X-USER-ID': _config.userId,
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final nakshatra = decoded['nakshatra'] as String?;
        final pada = decoded['pada']?.toString();
        if (nakshatra != null && pada != null) {
          return AstrologyDetails(nakshatra: nakshatra, pada: pada);
        }
      }
    } catch (_) {
      // Swallow errors and fall back
    }

    return _fallback.compute(
      birthDateTime: birthDateTime,
      latitude: latitude,
      longitude: longitude,
    );
  }

  void dispose() {
    _client.close();
  }
}


