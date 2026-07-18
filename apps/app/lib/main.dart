import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'app_settings.dart';
import 'app_state.dart';
import 'v2/rooms_controller.dart';
import 'firebase_options.dart';
import 'screens.dart';
import 'v2/deferred_invite.dart';
import 'v2/screens/join_screen.dart';
import 'v2/screens/onboarding_screen.dart';
import 'v2/screens/party_screen.dart';
import 'v2/screens/play_surface.dart';
import 'v2/screens/profile_screen.dart';
import 'v2/screens/room_detail.dart';
import 'v2/screens/notifications_primer.dart';
import 'v2/screens/room_history_screen.dart';
import 'v2/screens/room_review.dart';
import 'v2/screens/room_reveal.dart';
import 'v2/screens/rooms_home.dart';
import 'v2/screens/world_leaderboard.dart';
import 'v2/widgets_v2.dart' show V2NavigationShell;
import 'theme/rtw_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  final bootstrap = await _configureFirebase();
  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(bootstrap.firebaseReady),
        appSettingsProvider.overrideWithValue(bootstrap.settings),
      ],
      child: const ReadTheWorldApp(),
    ),
  );
}

const _useEmulators = bool.fromEnvironment('RTW_USE_EMULATORS');
const _appCheckDebugToken = String.fromEnvironment('RTW_APP_CHECK_DEBUG_TOKEN');
const _emulatorHost = String.fromEnvironment(
  'RTW_EMULATOR_HOST',
  defaultValue: 'localhost',
);

Future<AppBootstrap> _configureFirebase() async {
  if (!DefaultFirebaseOptions.configured) return const AppBootstrap();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    debugPrint('Firebase Core initialization failed: $error');
    return const AppBootstrap();
  }

  if (_useEmulators) {
    // Local QA against the emulator suite (firebase.json ports).
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
    FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).useFunctionsEmulator(_emulatorHost, 5001);
    debugPrint('Firebase emulators connected at $_emulatorHost');
  }

  final settings = await _configureFirebaseServices();
  return AppBootstrap(firebaseReady: true, settings: settings);
}

Future<AppSettings> _configureFirebaseServices() async {
  const recaptchaSiteKey = String.fromEnvironment(
    'RTW_RECAPTCHA_ENTERPRISE_SITE_KEY',
  );
  try {
    if (_useEmulators) {
      debugPrint('Firebase App Check skipped: emulator mode.');
    } else if (kIsWeb && recaptchaSiteKey.isEmpty) {
      debugPrint(
        'Firebase App Check skipped: RTW_RECAPTCHA_ENTERPRISE_SITE_KEY missing.',
      );
    } else {
      await FirebaseAppCheck.instance.activate(
        providerWeb: kDebugMode
            ? WebDebugProvider()
            : ReCaptchaEnterpriseProvider(recaptchaSiteKey),
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? AppleDebugProvider(
                debugToken: _appCheckDebugToken.isEmpty
                    ? null
                    : _appCheckDebugToken,
              )
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    }
  } catch (error) {
    debugPrint('Firebase App Check setup skipped: $error');
  }

  try {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);
  } catch (error) {
    debugPrint('Firebase Analytics setup skipped: $error');
  }

  try {
    await FirebasePerformance.instance.setPerformanceCollectionEnabled(
      !kDebugMode,
    );
  } catch (error) {
    debugPrint('Firebase Performance setup skipped: $error');
  }

  if (!kIsWeb) {
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (error) {
      debugPrint('Firebase Crashlytics setup skipped: $error');
    }
  }

  AppSettings settings = AppSettings.defaults;
  try {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1)
            : const Duration(hours: 1),
      ),
    );
    await remoteConfig.setDefaults(AppSettings.remoteConfigDefaults);
    // Cold start must not hang on the network: activate last launch's fetch
    // instantly, then give a live fetch a short window to land so kill
    // switches and flag flips still apply to this session on a healthy
    // connection. If it misses the window it keeps running for next launch.
    await remoteConfig.activate();
    final freshFetch = remoteConfig.fetchAndActivate().catchError((
      Object error,
    ) {
      debugPrint('Firebase Remote Config fetch failed: $error');
      return false;
    });
    await Future.any<Object?>([
      freshFetch,
      Future<Object?>.delayed(const Duration(seconds: 3)),
    ]);
    settings = AppSettings.fromRemoteConfig(remoteConfig);
  } catch (error) {
    debugPrint('Firebase Remote Config setup skipped: $error');
  }

  try {
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
  } catch (error) {
    debugPrint('Firebase Messaging setup skipped: $error');
  }

  if (!kIsWeb) {
    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
    } catch (error) {
      debugPrint('Firebase Messaging foreground setup skipped: $error');
    }
  }
  return settings;
}

class AppBootstrap {
  const AppBootstrap({
    this.firebaseReady = false,
    this.settings = AppSettings.defaults,
  });

  final bool firebaseReady;
  final AppSettings settings;
}

final firebaseReadyProvider = Provider<bool>((ref) => false);
final appSettingsProvider = Provider<AppSettings>(
  (ref) => AppSettings.defaults,
);

final rtwControllerProvider = ChangeNotifierProvider<RtwController>((ref) {
  return RtwController(firebaseReady: ref.watch(firebaseReadyProvider));
});

/// v2 rooms state (docs/v2-implementation-spec.md). Lives alongside the v1
/// controller during the rebuild; v1 retires when the v2 routes take over.
final roomsControllerProvider = ChangeNotifierProvider<RoomsController>((ref) {
  final controller = RoomsController(
    firebaseReady: ref.watch(firebaseReadyProvider),
  );
  controller.worldPredictionsUnlocked = ref
      .watch(appSettingsProvider)
      .worldRoomUnlocked;
  return controller;
});

GoRoute _appRoute(
  String path,
  Widget Function(BuildContext context, GoRouterState state) builder, {
  bool mobileSlide = false,
  bool mainFade = false,
}) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => _rtwPage(
      context,
      state,
      builder(context, state),
      mobileSlide: mobileSlide,
      mainFade: mainFade,
    ),
  );
}

Page<void> _rtwPage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  required bool mobileSlide,
  required bool mainFade,
}) {
  final mobileNative =
      mobileSlide && !kIsWeb && MediaQuery.sizeOf(context).width < 820;
  final nativeMainFade = mainFade && !kIsWeb;
  if (!mobileNative && !nativeMainFade) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }

  if (mobileNative) {
    return _RtwCupertinoPage(key: state.pageKey, child: child);
  }

  if (nativeMainFade) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (_, animation, _, child) {
        final opacity = animation.drive(CurveTween(curve: Curves.easeOutCubic));
        return FadeTransition(opacity: opacity, child: child);
      },
    );
  }

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (_, animation, _, child) {
      final position = animation.drive(
        Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      );
      return SlideTransition(position: position, child: child);
    },
  );
}

class _RtwCupertinoPage extends Page<void> {
  const _RtwCupertinoPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) {
    return CupertinoPageRoute<void>(settings: this, builder: (_) => child);
  }
}

final rtwRouterProvider = Provider<GoRouter>((ref) {
  const localPreview = bool.fromEnvironment('RTW_LOCAL_PREVIEW');
  final firebaseReady = ref.watch(firebaseReadyProvider);
  final appSettings = ref.watch(appSettingsProvider);
  final controller = ref.read(rtwControllerProvider);
  final roomsController = ref.read(roomsControllerProvider);
  final browserPath = Uri.base.path;
  final isLocalPreviewPath =
      localPreview && browserPath == '/review/onboarding';
  final isAppPath = [
    '/auth',
    '/onboarding',
    '/today',
    '/reveal',
    '/history',
    '/party',
    '/insights',
    '/account',
    '/invite',
    '/rooms',
    '/join',
    '/profile',
  ].any((path) => browserPath == path || browserPath.startsWith('$path/'));
  final isShortCodePath = RegExp(r'^/[A-Za-z0-9]{4,16}$').hasMatch(browserPath);
  final initialLocation = isAppPath || isShortCodePath || isLocalPreviewPath
      ? browserPath
      : '/today';
  return GoRouter(
    initialLocation: initialLocation,
    observers: firebaseReady
        ? <NavigatorObserver>[
            FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
          ]
        : const <NavigatorObserver>[],
    refreshListenable: Listenable.merge([controller, roomsController]),
    redirect: (_, state) {
      if (!appSettings.partyMode && state.uri.path == '/party') {
        return '/rooms';
      }
      // Anonymous sessions never count as signed in — the app has no anonymous
      // flow, so an anonymous user is always a stale/leftover session and must
      // be sent back to auth to sign in with a real account [Mike].
      final currentUser = firebaseReady
          ? FirebaseAuth.instance.currentUser
          : null;
      final signedOut =
          firebaseReady && (currentUser == null || currentUser.isAnonymous);
      final path = state.uri.path;
      if (localPreview && path == '/review/onboarding') return null;
      final authRequiredPath =
          path == '/onboarding' ||
          path == '/notifications' ||
          path == '/profile' ||
          path == '/party' ||
          path == '/today' ||
          path == '/today/play' ||
          path == '/rooms' ||
          path.startsWith('/rooms/') ||
          path == '/world/leaderboard';
      if (signedOut && authRequiredPath) {
        return '/auth';
      }
      // First run: the default tabs hand off to the intro demo. Deep links
      // (join codes, room links, auth) stay untouched.
      const gatedTabs = {'/today', '/rooms', '/party'};
      if (gatedTabs.contains(state.uri.path) &&
          roomsController.needsOnboarding) {
        return '/onboarding';
      }
      // A join link that arrived signed out resumes once the reader is signed
      // in and past onboarding, instead of losing the invite.
      final pendingInvite = controller.pendingInviteCode;
      if (pendingInvite != null &&
          !signedOut &&
          !roomsController.needsOnboarding &&
          (path == '/rooms' || path == '/today')) {
        controller.consumePendingInviteCode();
        return '/join/$pendingInvite';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/today'),
      if (localPreview)
        _appRoute('/review/onboarding', (_, _) => const OnboardingScreenV2()),
      _appRoute('/auth', (_, _) => const AuthScreen()),
      _appRoute('/onboarding', (_, _) => const OnboardingScreenV2()),
      _appRoute(
        '/notifications',
        (_, _) => const NotificationsPrimerScreen(),
        mainFade: true,
      ),
      // Legacy v1 paths (old notification routes, bookmarks) land safely.
      GoRoute(path: '/history', redirect: (_, _) => '/rooms'),
      GoRoute(path: '/insights', redirect: (_, _) => '/rooms'),
      GoRoute(path: '/account', redirect: (_, _) => '/profile'),
      GoRoute(path: '/reveal', redirect: (_, _) => '/rooms'),
      // Legacy v1 share/invite links: an honest dead-end instead of routing
      // into a misleading join failure or a silent rooms landing.
      _appRoute(
        '/reveal/:questionId',
        (_, state) => ShortLinkScreen(
          code:
              state.uri.queryParameters['code'] ??
              state.pathParameters['questionId'] ??
              '',
          unsupported: true,
        ),
        mobileSlide: true,
      ),
      GoRoute(path: '/today/predict', redirect: (_, _) => '/today'),
      GoRoute(path: '/today/locked', redirect: (_, _) => '/today'),
      _appRoute(
        '/invite/:code',
        (_, state) => ShortLinkScreen(
          code: state.pathParameters['code'] ?? '',
          unsupported: true,
        ),
        mobileSlide: true,
      ),
      // Authenticated routes share one mobile navigation shell. Pages still
      // own their surfaces, while the tab bar is mounted once outside the
      // nested Navigator so it never participates in page transitions.
      ShellRoute(
        builder: (context, state, child) =>
            V2NavigationShell(location: state.uri.path, child: child),
        routes: [
          _appRoute('/today', (_, _) => const TodayScreenV2(), mainFade: true),
          _appRoute('/party', (_, _) => const PartyScreenV2(), mainFade: true),
          // ── v2 rooms routes.
          _appRoute(
            '/rooms',
            (_, _) => const RoomsHomeScreen(),
            mainFade: true,
          ),
          _appRoute(
            '/rooms/:roomId',
            (_, state) => RoomDetailScreen(
              roomId: state.pathParameters['roomId'] ?? '',
              edit: state.uri.queryParameters['edit'] == '1',
            ),
            mobileSlide: true,
          ),
          _appRoute(
            '/rooms/:roomId/review',
            (_, state) =>
                RoomReviewScreen(roomId: state.pathParameters['roomId'] ?? ''),
            mobileSlide: true,
          ),
          _appRoute(
            '/rooms/:roomId/history',
            (_, state) =>
                RoomHistoryScreen(roomId: state.pathParameters['roomId'] ?? ''),
            mobileSlide: true,
          ),
          _appRoute(
            '/rooms/:roomId/reveal',
            (_, state) => RoomRevealScreen(
              roomId: state.pathParameters['roomId'] ?? '',
              fromToday: state.uri.queryParameters['from'] == 'today',
            ),
            mainFade: true,
          ),
          _appRoute('/today/play', (_, _) => const RoomPlayScreen()),
          _appRoute(
            '/world/leaderboard',
            (_, _) => const WorldLeaderboardScreen(),
            mobileSlide: true,
          ),
          _appRoute(
            '/profile',
            (_, _) => const ProfileScreenV2(),
            mobileSlide: true,
          ),
        ],
      ),
      _appRoute(
        '/join/:code',
        (_, state) => JoinRoomScreen(code: state.pathParameters['code'] ?? ''),
        mobileSlide: true,
      ),
      _appRoute(
        '/:code',
        (_, state) => ShortLinkScreen(code: state.pathParameters['code'] ?? ''),
        mobileSlide: true,
      ),
    ],
  );
});

class ReadTheWorldApp extends ConsumerStatefulWidget {
  const ReadTheWorldApp({super.key});

  @override
  ConsumerState<ReadTheWorldApp> createState() => _ReadTheWorldAppState();
}

class _ReadTheWorldAppState extends ConsumerState<ReadTheWorldApp> {
  StreamSubscription<RemoteMessage>? _notificationOpenSub;
  bool _notificationRoutingStarted = false;
  bool _deferredInviteCheckStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = ref.read(rtwRouterProvider);
      _startNotificationRouting(router);
      unawaited(_resumeDeferredInviteForSignedInUser(router));
    });
  }

  @override
  void dispose() {
    unawaited(_notificationOpenSub?.cancel());
    super.dispose();
  }

  void _startNotificationRouting(GoRouter router) {
    if (_notificationRoutingStarted || !ref.read(firebaseReadyProvider)) {
      return;
    }
    _notificationRoutingStarted = true;
    _notificationOpenSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _openNotificationRoute(router, message),
      onError: (Object error) {
        debugPrint('Firebase notification-open routing failed: $error');
      },
    );
    unawaited(
      FirebaseMessaging.instance
          .getInitialMessage()
          .then((message) {
            if (!mounted || message == null) return;
            _openNotificationRoute(ref.read(rtwRouterProvider), message);
          })
          .catchError((Object error) {
            debugPrint('Firebase initial notification route failed: $error');
            return null;
          }),
    );
  }

  void _openNotificationRoute(GoRouter router, RemoteMessage message) {
    final route = _notificationRouteFromData(message.data);
    if (route == null) return;
    router.go(route);
  }

  Future<void> _resumeDeferredInviteForSignedInUser(GoRouter router) async {
    if (_deferredInviteCheckStarted ||
        kIsWeb ||
        !ref.read(firebaseReadyProvider)) {
      return;
    }
    _deferredInviteCheckStarted = true;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      // AuthScreen owns the signed-out prompt and preserves the invite across
      // account creation and onboarding.
      return;
    }
    final check = await checkDeferredInvite();
    if (!mounted || !check.available) return;
    // Android supplies the code through Play Install Referrer. On iOS this
    // read presents the operating system's paste permission prompt.
    final code = check.code ?? await readDeferredInvite();
    if (!mounted || code == null) return;
    router.go('/join/$code');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(rtwRouterProvider);
    return MaterialApp.router(
      title: 'Read the World',
      scrollBehavior: const _RtwScrollBehavior(),
      debugShowCheckedModeBanner: false,
      theme: buildRtwTheme(),
      routerConfig: router,
    );
  }
}

/// Web/desktop: let mouse and trackpad drags scroll like touch so the
/// phone-column surfaces pan naturally (wheel support varies per embedder).
class _RtwScrollBehavior extends MaterialScrollBehavior {
  const _RtwScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

String? _notificationRouteFromData(Map<String, dynamic> data) {
  final rawRoute = data['route'];
  if (rawRoute is! String || rawRoute.isEmpty) return null;
  final uri = Uri.tryParse(rawRoute);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final path = uri.path;
  const allowedPaths = [
    '/today',
    '/reveal',
    '/history',
    '/party',
    '/insights',
    '/account',
    '/invite',
    '/rooms',
    '/join',
  ];
  final allowed = allowedPaths.any(
    (prefix) => path == prefix || path.startsWith('$prefix/'),
  );
  return allowed ? uri.toString() : null;
}
