import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'app_settings.dart';
import 'app_state.dart';
import 'firebase_options.dart';
import 'screens.dart';
import 'theme/rtw_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

Future<AppBootstrap> _configureFirebase() async {
  if (!DefaultFirebaseOptions.configured) return const AppBootstrap();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final settings = await _configureFirebaseServices();
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    return AppBootstrap(firebaseReady: true, settings: settings);
  } catch (_) {
    return const AppBootstrap();
  }
}

Future<AppSettings> _configureFirebaseServices() async {
  const recaptchaSiteKey = String.fromEnvironment(
    'RTW_RECAPTCHA_ENTERPRISE_SITE_KEY',
  );
  if (kIsWeb && recaptchaSiteKey.isEmpty) {
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

  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);
  await FirebasePerformance.instance.setPerformanceCollectionEnabled(
    !kDebugMode,
  );
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

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
  final settings = AppSettings.fromRemoteConfig(remoteConfig);

  await FirebaseMessaging.instance.setAutoInitEnabled(true);
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

GoRoute _appRoute(
  String path,
  Widget Function(BuildContext context, GoRouterState state) builder, {
  bool mobileSlide = false,
}) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) =>
        _rtwPage(context, state, builder(context, state), mobileSlide),
  );
}

Page<void> _rtwPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
  bool mobileSlide,
) {
  final mobileNative =
      mobileSlide && !kIsWeb && MediaQuery.sizeOf(context).width < 820;
  if (!mobileNative) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
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

final rtwRouterProvider = Provider<GoRouter>((ref) {
  final firebaseReady = ref.watch(firebaseReadyProvider);
  final appSettings = ref.watch(appSettingsProvider);
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
    redirect: (_, state) {
      if (!appSettings.partyMode && state.uri.path == '/party') {
        return '/history';
      }
      if (!appSettings.onboardingDemographics &&
          state.uri.path == '/onboarding/about') {
        return '/today';
      }
      if (!appSettings.friends && state.uri.path.startsWith('/invite')) {
        return '/insights';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/today'),
      _appRoute('/auth', (_, _) => const AuthScreen()),
      _appRoute('/onboarding', (_, _) => const OnboardingScreen()),
      _appRoute(
        '/onboarding/about',
        (_, _) => const OnboardingScreen(initialStep: 1),
      ),
      _appRoute('/today', (_, _) => const TodayScreen()),
      _appRoute(
        '/today/predict',
        (_, _) => const PredictScreen(),
        mobileSlide: true,
      ),
      _appRoute(
        '/today/locked',
        (_, _) => const LockedScreen(),
        mobileSlide: true,
      ),
      _appRoute('/reveal', (_, _) => const RevealScreen()),
      _appRoute(
        '/reveal/:questionId',
        (_, state) =>
            RevealScreen(questionId: state.pathParameters['questionId']),
        mobileSlide: true,
      ),
      _appRoute('/history', (_, _) => const HistoryScreen()),
      _appRoute('/party', (_, _) => const PartyScreen()),
      _appRoute('/insights', (_, _) => const InsightsScreen()),
      _appRoute('/account', (_, _) => const AccountScreen(), mobileSlide: true),
      _appRoute(
        '/invite/:code',
        (_, state) => InviteScreen(code: state.pathParameters['code'] ?? ''),
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

class ReadTheWorldApp extends ConsumerWidget {
  const ReadTheWorldApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(rtwRouterProvider);
    return MaterialApp.router(
      title: 'Read the World',
      debugShowCheckedModeBanner: false,
      theme: buildRtwTheme(),
      routerConfig: router,
    );
  }
}
