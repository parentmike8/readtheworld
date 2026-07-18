import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:read_the_world/app_settings.dart';
import 'package:read_the_world/app_state.dart';
import 'package:read_the_world/main.dart';
import 'package:read_the_world/screens.dart';
import 'package:read_the_world/v2/deferred_invite.dart';
import 'package:read_the_world/v2/rooms_controller.dart';
import 'package:read_the_world/v2/screens/join_screen.dart';
import 'package:read_the_world/v2/screens/profile_screen.dart';

/// Lets tests emit a profile change the way the Firestore snapshot listener
/// does (field write + notify), without the optimistic-write path.
class _TestRtwController extends RtwController {
  _TestRtwController() : super(firebaseReady: false);

  void emitProfileName(String value) {
    displayName = value;
    notifyListeners();
  }
}

class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException(String code)
    : super(message: 'Internal details', code: code);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pending invite stash', () {
    test('normalizes the code and clears on consume', () {
      final controller = RtwController(firebaseReady: false);
      expect(controller.pendingInviteCode, isNull);

      controller.stashPendingInviteCode('  room42 ');
      expect(controller.pendingInviteCode, 'ROOM42');
      // Reading does not clear; only consume does.
      expect(controller.pendingInviteCode, 'ROOM42');

      expect(controller.consumePendingInviteCode(), 'ROOM42');
      expect(controller.pendingInviteCode, isNull);
      expect(controller.consumePendingInviteCode(), isNull);
    });

    test('ignores empty codes', () {
      final controller = RtwController(firebaseReady: false);
      controller.stashPendingInviteCode('   ');
      expect(controller.pendingInviteCode, isNull);
    });

    test('postAuthRoute keeps the stash when onboarding comes first', () async {
      final controller = RtwController(firebaseReady: false)
        ..stashPendingInviteCode('ROOM42');
      // Without live Firebase the route falls back to onboarding; the stash
      // must survive so the router can resume the invite afterwards.
      expect(await controller.postAuthRoute(), '/onboarding');
      expect(controller.pendingInviteCode, 'ROOM42');
    });

    testWidgets('a stashed invite resumes at /join/CODE from the home tabs', (
      tester,
    ) async {
      final profile = RtwController(firebaseReady: false)
        ..stashPendingInviteCode('ROOM42');
      final rooms = RoomsController(firebaseReady: false)..loadingRooms = false;
      final container = ProviderContainer(
        overrides: [
          firebaseReadyProvider.overrideWithValue(false),
          appSettingsProvider.overrideWithValue(AppSettings.defaults),
          rtwControllerProvider.overrideWith(
            (_) => profile,
            disposeNotifier: false,
          ),
          roomsControllerProvider.overrideWith(
            (_) => rooms,
            disposeNotifier: false,
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(rtwRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/join/ROOM42');
      expect(profile.pendingInviteCode, isNull);
    });
  });

  group('Deferred invite parsing', () {
    test('accepts short links, app join links, and bare room codes', () {
      expect(
        roomInviteCodeFromDeferredText('https://rtw.codes/studio-7f2'),
        'STUDIO-7F2',
      );
      expect(
        roomInviteCodeFromDeferredText(
          'https://app.readtheworld.today/join/room42',
        ),
        'ROOM42',
      );
      expect(roomInviteCodeFromDeferredText(' room42 '), 'ROOM42');
    });

    test('rejects unrelated clipboard text and URLs', () {
      expect(roomInviteCodeFromDeferredText('hello world'), isNull);
      expect(
        roomInviteCodeFromDeferredText('https://example.com/room42'),
        isNull,
      );
    });
  });

  group('Join preview initial', () {
    test('falls back to ? for missing or empty room names', () {
      expect(joinPreviewInitial(null), '?');
      expect(joinPreviewInitial(''), '?');
      expect(joinPreviewInitial('Studio'), 'S');
    });

    test('preview failures never expose internal exception details', () {
      expect(
        joinPreviewErrorMessage(_TestFunctionsException('not-found')),
        'This invite is not valid.',
      );
      expect(
        joinPreviewErrorMessage(StateError('Internal stack trace')),
        'Could not open this invite. Please try again.',
      );
    });
  });

  group('Legacy short links', () {
    test('short-link failures never expose internal exception details', () {
      expect(
        shortLinkErrorMessage(_TestFunctionsException('unauthenticated')),
        'Could not verify this link. Please try again.',
      );
      expect(
        shortLinkErrorMessage(StateError('Internal stack trace')),
        'Could not open this link. Please try again.',
      );
    });

    testWidgets('unsupported links show an honest dead-end', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
          ],
          child: const MaterialApp(
            home: ShortLinkScreen(code: 'AB12CD', unsupported: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This link is unavailable.'), findsOneWidget);
      expect(find.text('This link is no longer supported.'), findsOneWidget);
    });
  });

  group('Profile display name field', () {
    testWidgets('resyncs when the profile lands after first build', (
      tester,
    ) async {
      final profile = _TestRtwController()..displayName = 'Reader';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            rtwControllerProvider.overrideWith(
              (_) => profile,
              disposeNotifier: false,
            ),
          ],
          child: const MaterialApp(home: ProfileScreenV2()),
        ),
      );
      await tester.pumpAndSettle();

      profile.emitProfileName('Mike');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Mike');
    });

    testWidgets('keeps the reader\'s edit when a profile change arrives', (
      tester,
    ) async {
      final profile = _TestRtwController()..displayName = 'Reader';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            rtwControllerProvider.overrideWith(
              (_) => profile,
              disposeNotifier: false,
            ),
          ],
          child: const MaterialApp(home: ProfileScreenV2()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'My Own Name');
      await tester.pump();

      profile.emitProfileName('Server Name');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'My Own Name');
    });
  });
}
