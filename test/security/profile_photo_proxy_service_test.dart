import 'package:brahmin_vivaaha_vedika/services/security/profile_photo_proxy_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ProfilePhotoProxyService.useProxy = true;
  });

  test('imageUrl points at cloud function with owner and variant', () {
    final url = ProfilePhotoProxyService.imageUrl(
      ownerUserId: 'user_abc123',
      variant: ProfilePhotoProxyVariant.full,
    );
    expect(url, contains('streamProfilePhoto'));
    expect(url, contains('ownerId=user_abc123'));
    expect(url, contains('variant=full'));
    expect(url, isNot(contains('cloudinary.com')));
    expect(url, isNot(contains('firebasestorage')));
  });

  test('preview variant encoded in URL', () {
    final url = ProfilePhotoProxyService.imageUrl(
      ownerUserId: 'uid1',
      variant: ProfilePhotoProxyVariant.preview,
    );
    expect(url, contains('variant=preview'));
  });

  test('resolveNetworkUrl prefers proxy when owner id present', () {
    final resolved = ProfilePhotoProxyService.resolveNetworkUrl(
      ownerUserId: 'uid1',
      legacyDirectUrl: 'https://res.cloudinary.com/secret/image.jpg',
    );
    expect(resolved, contains('streamProfilePhoto'));
    expect(resolved, isNot(contains('cloudinary.com')));
  });

  test('resolveNetworkUrl falls back to legacy when proxy disabled', () {
    ProfilePhotoProxyService.useProxy = false;
    const legacy = 'https://res.cloudinary.com/x/y.jpg';
    final resolved = ProfilePhotoProxyService.resolveNetworkUrl(
      ownerUserId: 'uid1',
      legacyDirectUrl: legacy,
    );
    expect(resolved, legacy);
  });

  test('shouldUseProxyFor false for owner', () {
    expect(
      ProfilePhotoProxyService.shouldUseProxyFor(
        ownerUserId: 'uid1',
        isOwner: true,
      ),
      isFalse,
    );
  });
}
