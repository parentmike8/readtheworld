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
import 'v2/screens/join_screen.dart';
import 'v2/screens/onboarding_screen.dart';
import 'v2/screens/party_screen.dart';
import 'v2/screens/play_surface.dart';
import 'v2/screens/profile_screen.dart';
import 'v2/screens/room_detail.dart';
import 'v2/screens/room_reveal.dart';
import 'v2/screens/rooms_home.dart';
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
            ? const AppleDebugProvider()
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
    await remoteConfig.fetchAndActivate();
    settings = AppSettings.fromRemoteConfig(remoteConfig);
  } catch (error) {
    debugPrint('Firebase Remote Config setup skipped: $error');
  }

  try {
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
  } catch (error) {
    debugPrint('Firebase Messaging setup skipped: $error');
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
  final controller = RoomsController(firebaseReady: ref.watch(firebaseReadyProvider));
  controller.worldPredictionsUnlocked = ref.watch(appSettingsProvider).worldRoomUnlocked;
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
    return CupertinoPageRoute<void>(
      settings: this,
      builder: (_) => child,
    );
  }
}

final rtwRouterProvider = Provider<GoRouter>((ref) {
  final firebaseReady = ref.watch(firebaseReadyProvider);
  final appSettings = ref.watch(appSettingsProvider);
  final controller = ref.read(rtwControllerProvider);
  final roomsController = ref.read(roomsControllerProvider);
  final browserPath = Uri.base.path;
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
  final initialLocation = isAppPath || isShortCodePath ? browserPath : '/today';
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
      final signedOut =
          firebaseReady && FirebaseAuth.instance.currentUser == null;
      final path = state.uri.path;
      final authRequiredPath =
          path == '/onboarding' ||
          path == '/profile' ||
          path == '/party' ||
          path == '/today' ||
          path == '/today/play' ||
          path == '/rooms' ||
          path.startsWith('/rooms/');
      if (signedOut && authRequiredPath) {
        return '/auth';
      }
      // First run: the default tabs hand off to the intro demo. Deep links
      // (join codes, room links, auth) stay untouched.
      const gatedTabs = {'/today', '/rooms', '/party'};
      if (gatedTabs.contains(state.uri.path) && roomsController.needsOnboarding) {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/today'),
      _appRoute('/auth', (_, _) => const AuthScreen()),
      _appRoute('/onboarding', (_, _) => const OnboardingScreenV2()),
      _appRoute('/today', (_, _) => const TodayScreenV2(), mainFade: true),
      _appRoute('/party', (_, _) => const PartyScreenV2(), mainFade: true),
      // Legacy v1 paths (old notification routes, bookmarks) land safely.
      GoRoute(path: '/history', redirect: (_, _) => '/rooms'),
      GoRoute(path: '/insights', redirect: (_, _) => '/rooms'),
      GoRoute(path: '/account', redirect: (_, _) => '/profile'),
      GoRoute(path: '/reveal', redirect: (_, _) => '/rooms'),
      GoRoute(path: '/reveal/:questionId', redirect: (_, _) => '/rooms'),
      GoRoute(path: '/today/predict', redirect: (_, _) => '/today'),
      GoRoute(path: '/today/locked', redirect: (_, _) => '/today'),
      GoRoute(
        path: '/invite/:code',
        redirect: (_, state) => '/join/${state.pathParameters['code'] ?? ''}',
      ),
      // ── v2 rooms routes.
      _appRoute('/rooms', (_, _) => const RoomsHomeScreen(), mainFade: true),
      _appRoute(
        '/rooms/:roomId',
        (_, state) =>
            RoomDetailScreen(roomId: state.pathParameters['roomId'] ?? ''),
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
      _appRoute('/profile', (_, _) => const ProfileScreenV2(), mobileSlide: true),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startNotificationRouting(ref.read(rtwRouterProvider));
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
