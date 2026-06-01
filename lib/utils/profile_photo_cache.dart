/// Cache-busting helpers for profile photos (Cloudinary/CDN + CachedNetworkImage).
library;

/// Appends a version query param so replaced assets at the same path load fresh.
String bustProfilePhotoCache(String url, {required int versionMs}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty || versionMs <= 0) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return trimmed;
  final params = Map<String, String>.from(uri.queryParameters);
  params['v'] = versionMs.toString();
  return uri.replace(queryParameters: params).toString();
}

/// Removes cache-buster query params before sending URLs to upload/storage APIs.
String stripProfilePhotoCacheBuster(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return trimmed;
  if (!uri.queryParameters.containsKey('v')) return trimmed;
  final params = Map<String, String>.from(uri.queryParameters)..remove('v');
  return uri.replace(queryParameters: params).toString();
}

/// Stable cache key for image widgets (URL + version).
String profilePhotoCacheKey(String url, {int? versionMs}) {
  final base = stripProfilePhotoCacheBuster(url);
  if (versionMs == null || versionMs <= 0) return base;
  return '$base?v=$versionMs';
}
