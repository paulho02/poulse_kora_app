import 'package:flutter_test/flutter_test.dart';

import 'package:peerkola/src/features/profile/data/user_profile.dart';

Map<String, dynamic> json({Map<String, dynamic> overrides = const {}}) => {
  'id': 'ce1b6b1e-0000-4000-8000-000000000000',
  'email': 'ada@example.com',
  'username': 'ada',
  'bio': null,
  'dark_mode': false,
  'settings_revision': 3,
  'onboarding_completed': true,
  'is_verified': true,
  'auth_provider': 'password',
  'google_email': null,
  'profile_picture_url': null,
  ...overrides,
};

void main() {
  group('authProvider', () {
    test('reads the backend field', () {
      expect(UserProfile.fromJson(json()).isGoogleAccount, isFalse);
      expect(
        UserProfile.fromJson(
          json(overrides: {'auth_provider': 'google'}),
        ).isGoogleAccount,
        isTrue,
      );
    });

    test(
      'an entry written before the field existed reads as a password account',
      () {
        // Cached profiles outlive app updates. Defaulting the other way would hide
        // the change-password row from every pre-existing account on first launch.
        final legacy = json()..remove('auth_provider');
        final profile = UserProfile.fromJson(legacy);
        expect(profile.authProvider, 'password');
        expect(profile.isGoogleAccount, isFalse);
      },
    );

    test(
      'googleEmail is only "distinct" when it differs from the contact one',
      () {
        // Drives whether Settings spells out that the Email row isn't the sign-in
        // address. When they match, saying so would be noise.
        final same = UserProfile.fromJson(
          json(
            overrides: {
              'auth_provider': 'google',
              'google_email': 'ADA@example.com',
            },
          ),
        );
        expect(
          same.hasDistinctGoogleEmail,
          isFalse,
          reason: 'case-insensitive',
        );

        final different = UserProfile.fromJson(
          json(
            overrides: {
              'auth_provider': 'google',
              'google_email': 'ada.personal@gmail.com',
            },
          ),
        );
        expect(different.hasDistinctGoogleEmail, isTrue);
        expect(different.email, 'ada@example.com');
      },
    );

    test('a password account has no google email', () {
      expect(UserProfile.fromJson(json()).googleEmail, isNull);
      expect(UserProfile.fromJson(json()).hasDistinctGoogleEmail, isFalse);
    });

    test('survives copyWith', () {
      // copyWith takes no authProvider parameter, so it has to be threaded
      // through explicitly — easy to forget, and the symptom would be a Google
      // account silently offering to change a password it does not have.
      final google = UserProfile.fromJson(
        json(overrides: {'auth_provider': 'google'}),
      );
      expect(google.copyWith(bio: 'hi').isGoogleAccount, isTrue);
    });
  });

  group('profilePictureUrl', () {
    test('reads the backend field', () {
      final profile = UserProfile.fromJson(
        json(
          overrides: {
            'profile_picture_url':
                '/api/v1/users/ce1b6b1e-0000-4000-8000-000000000000'
                '/profile-picture',
          },
        ),
      );
      expect(
        profile.profilePictureUrl,
        '/api/v1/users/ce1b6b1e-0000-4000-8000-000000000000/profile-picture',
      );
    });

    test('an account with no picture reads as null', () {
      expect(UserProfile.fromJson(json()).profilePictureUrl, isNull);
    });

    test('an entry written before the field existed reads as no picture', () {
      // Cached profiles outlive app updates; the field simply won't be there.
      final legacy = json()..remove('profile_picture_url');
      expect(UserProfile.fromJson(legacy).profilePictureUrl, isNull);
    });

    test('survives copyWith', () {
      // Same hazard as authProvider above: copyWith takes no parameter for it,
      // so it has to be threaded through by hand. Dropping it would blank the
      // avatar the moment any unrelated field was copied.
      final withPicture = UserProfile.fromJson(
        json(overrides: {'profile_picture_url': '/api/v1/users/x/pp'}),
      );
      expect(
        withPicture.copyWith(bio: 'hi').profilePictureUrl,
        '/api/v1/users/x/pp',
      );
    });
  });
}
