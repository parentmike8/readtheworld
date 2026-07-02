import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:read_the_world/app_settings.dart';
import 'package:read_the_world/app_state.dart';
import 'package:read_the_world/firestore_mappers.dart';
import 'package:read_the_world/main.dart';
import 'package:read_the_world/models.dart';
import 'package:read_the_world/scoring.dart';
import 'package:read_the_world/screens.dart';
import 'package:read_the_world/widgets.dart';

import 'fixtures/demo_data.dart';

Widget _testApp({
  required String initialLocation,
  required List<RouteBase> routes,
  AppSettings appSettings = AppSettings.defaults,
  bool useDemoController = true,
  RtwController? controller,
}) {
  final activeController =
      controller ?? (useDemoController ? _demoController() : null);
  return ProviderScope(
    overrides: [
      firebaseReadyProvider.overrideWithValue(false),
      appSettingsProvider.overrideWithValue(appSettings),
      if (activeController != null)
        rtwControllerProvider.overrideWith((_) => activeController),
      rtwRouterProvider.overrideWithValue(
        GoRouter(
          initialLocation: initialLocation,
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
            if (activeController?.lockedToday == true &&
                (state.uri.path == '/today' ||
                    state.uri.path == '/today/predict')) {
              return '/today/locked';
            }
            return null;
          },
          routes: routes,
        ),
      ),
    ],
    child: const ReadTheWorldApp(),
  );
}

RtwController _demoController() {
  final controller = _FixtureRtwController()
    ..today = todayQuestion
    ..liveCount = todayQuestion.totalAnswers
    ..displayName = 'Alex'
    ..email = 'alex@email.com'
    ..readScore = 1840
    ..officialQuestionsAnswered = 142
    ..readScorePercentileLabel = 'Top 6% worldwide'
    ..currentStreak = 7
    ..history = buildDemoHistory()
    ..friends = List.of(demoFriends)
    ..categoryInsights = List.of(demoCategoryInsights)
    ..lastError = null;
  return controller;
}

class _FixtureRtwController extends RtwController {
  _FixtureRtwController() : super(firebaseReady: false);

  @override
  Future<void> lockPrediction() async {
    if (selectedOptionId == null) return;
    lockedToday = true;
    lastError = null;
    notifyListeners();
  }

  @override
  Future<String> createResultShareUrl(String questionId) async {
    return 'https://rtw.codes/demo';
  }

  @override
  Future<String> createInviteUrl() async {
    return 'https://rtw.codes/demo';
  }

  @override
  Future<bool> acceptInvite(String code) async {
    final hasInviteFriend = friends.any(
      (friend) => friend.name == 'New reader',
    );
    if (!hasInviteFriend) {
      friends = [...friends, const FriendRow(name: 'New reader', score: 1500)];
    }
    notifyListeners();
    return true;
  }

  @override
  Future<String?> resolveShortCodeRoute(String code) async {
    return '/invite/${Uri.encodeComponent(code.trim().toUpperCase())}';
  }
}

class _SlowLockRtwController extends _FixtureRtwController {
  final completer = Completer<void>();

  @override
  Future<void> lockPrediction() async {
    if (selectedOptionId == null) return;
    submitting = true;
    lockedToday = true;
    lastError = null;
    notifyListeners();
    await completer.future;
    submitting = false;
    notifyListeners();
  }
}

List<RouteBase> _demoRoutes() {
  return [
    GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    GoRoute(
      path: '/onboarding/about',
      builder: (_, _) => const OnboardingScreen(initialStep: 1),
    ),
    GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
    GoRoute(path: '/today/predict', builder: (_, _) => const PredictScreen()),
    GoRoute(path: '/today/locked', builder: (_, _) => const LockedScreen()),
    GoRoute(
      path: '/reveal/:questionId',
      builder: (_, state) =>
          RevealScreen(questionId: state.pathParameters['questionId']),
    ),
    GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
    GoRoute(path: '/party', builder: (_, _) => const PartyScreen()),
    GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen()),
    GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
    GoRoute(
      path: '/invite/:code',
      builder: (_, state) =>
          InviteScreen(code: state.pathParameters['code'] ?? ''),
    ),
    GoRoute(
      path: '/:code',
      builder: (_, state) =>
          ShortLinkScreen(code: state.pathParameters['code'] ?? ''),
    ),
  ];
}

void main() {
  test('app router stays stable across controller notifications', () {
    final container = ProviderContainer(
      overrides: [
        firebaseReadyProvider.overrideWithValue(false),
        appSettingsProvider.overrideWithValue(AppSettings.defaults),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(rtwRouterProvider);
    final controller = container.read(rtwControllerProvider);
    controller.setPrediction(67);

    expect(identical(container.read(rtwRouterProvider), router), isTrue);
  });

  test('Read Accuracy uses absolute percentage-point error', () {
    expect(calculateReadAccuracy(predictedShare: 5, actualShare: 16), 89);
    expect(calculateReadAccuracy(predictedShare: 42, actualShare: 35), 93);
    expect(calculateReadAccuracy(predictedShare: 0, actualShare: 150), 0);
  });

  test('Firestore question mapper parses live question fields', () {
    final question = questionFromFirestore('2026-06-28-culture-dinner', {
      'dailyKey': '2026-06-28',
      'category': 'culture',
      'prompt': 'Is dinner too late after 9?',
      'type': 'binary',
      'options': [
        {'id': 'yes', 'label': 'Yes'},
        {'id': 'no', 'label': 'No'},
      ],
      'totalAnswers': 42,
    });

    expect(question.id, '2026-06-28-culture-dinner');
    expect(question.dateLabel, 'JUN 28');
    expect(question.category, 'CULTURE');
    expect(question.type, QuestionType.binary);
    expect(question.options.map((option) => option.label), ['Yes', 'No']);
    expect(question.totalAnswers, 42);
  });

  test('Firestore history mapper merges closed result and user answer', () {
    final entry = historyEntryFromDailyResult(
      questionId: '2026-06-27-science-fusion',
      resultData: {
        'dailyKey': '2026-06-27',
        'category': 'science',
        'prompt': 'Will fusion power reach the grid within 20 years?',
        'options': [
          {'id': 'yes', 'label': 'Yes'},
          {'id': 'no', 'label': 'No'},
        ],
        'optionPcts': {'yes': 54, 'no': 46},
        'totalAnswers': 1000,
      },
      answerData: {'selectedOptionId': 'yes', 'predictedShare': 66},
      scoreData: {
        'readAccuracy': 88,
        'readScoreDelta': 12,
        'dailyPercentile': 91.2,
        'countedTowardScore': true,
      },
    );

    expect(entry.status, HistoryStatus.scored);
    expect(entry.question.worldShareFor('yes'), 54);
    expect(entry.prediction, 66);
    expect(entry.readAccuracy, 88);
    expect(entry.readScoreDelta, 12);
    expect(entry.dailyPercentile, 91.2);
    expect(entry.countedTowardScore, isTrue);
  });

  test('Firestore history mapper treats practice answers as revealed only', () {
    final entry = historyEntryFromDailyResult(
      questionId: '2026-06-24-culture-phone-table',
      resultData: {
        'dailyKey': '2026-06-24',
        'category': 'culture',
        'prompt': 'Is it rude to keep your phone on the table during dinner?',
        'options': [
          {'id': 'yes', 'label': 'Yes'},
          {'id': 'no', 'label': 'No'},
        ],
        'optionPcts': {'yes': 62, 'no': 38},
        'totalAnswers': 1000,
      },
      answerData: {
        'selectedOptionId': 'no',
        'predictedShare': 44,
        'official': false,
        'countedTowardScore': false,
      },
    );

    expect(entry.status, HistoryStatus.revealed);
    expect(entry.played, isTrue);
    expect(entry.countedTowardScore, isFalse);
    expect(entry.readAccuracy, 94);
  });

  test('Controller saves demographics and clears local score data', () async {
    final controller = RtwController(firebaseReady: false);
    await controller.saveDemographics(
      birthdate: DateTime(1990, 6, 20),
      gender: 'Non-binary',
      country: 'United States',
    );

    expect(controller.birthdateDisplay, contains('Jun 20, 1990'));
    expect(controller.genderDisplay, 'Non-binary');
    expect(controller.countryDisplay, 'United States');

    await controller.clearAllData();

    expect(controller.readScore, 1500);
    expect(controller.officialQuestionsAnswered, 0);
    expect(controller.currentStreak, 0);
    expect(controller.categoryInsights, isEmpty);
    expect(controller.friends, hasLength(1));
    expect(controller.friends.single.score, 1500);
    expect(
      controller.history.every(
        (entry) => entry.status == HistoryStatus.skipped,
      ),
      isTrue,
    );
    expect(controller.countryDisplay, 'United States');
    controller.dispose();
  });

  test(
    'Controller saves practice answers without changing official score state',
    () async {
      final controller = _demoController();
      final skipped = controller.history.firstWhere(
        (entry) => entry.status == HistoryStatus.skipped,
      );

      await controller.savePracticeAnswer(skipped, 'yes', 52);
      final saved = controller.history.firstWhere(
        (entry) => entry.question.id == skipped.question.id,
      );

      expect(saved.status, HistoryStatus.revealed);
      expect(saved.selectedOptionId, 'yes');
      expect(saved.prediction, 52);
      expect(saved.played, isTrue);
      expect(saved.countedTowardScore, isFalse);
      expect(controller.readScore, 1840);
      expect(controller.officialQuestionsAnswered, 142);
      controller.dispose();
    },
  );

  testWidgets('Read the World app renders today route', (tester) async {
    await tester.pumpWidget(
      _testApp(
        initialLocation: '/today',
        routes: [
          GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
          GoRoute(
            path: '/onboarding',
            builder: (_, _) => const OnboardingScreen(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Can you read the world today?'), findsOneWidget);
    expect(
      find.text("Would you want to know the exact date you'll die?"),
      findsOneWidget,
    );
  });

  testWidgets('Native mobile scaffold fills wider iPhone viewports', (
    tester,
  ) async {
    const surfaceKey = Key('native-mobile-surface');
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: AppScaffold(
          location: '/today',
          showBottomNav: false,
          child: SizedBox(key: surfaceKey, width: double.infinity, height: 100),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(surfaceKey)).width, 430);
  });

  testWidgets('Onboarding about step opens DOB and country pickers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(false),
          rtwRouterProvider.overrideWithValue(
            GoRouter(
              initialLocation: '/onboarding',
              routes: [
                GoRoute(
                  path: '/onboarding',
                  builder: (_, _) => const OnboardingScreen(),
                ),
                GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
              ],
            ),
          ),
        ],
        child: const ReadTheWorldApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Get started'), 120);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('A little about you.'), findsOneWidget);
    expect(find.text('Fill in each to continue'), findsOneWidget);
    expect(find.text('Skip for now'), findsNothing);
    await tester.tap(find.text('Select your date of birth'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a date'), findsOneWidget);

    await tester.tap(find.text('Use this date'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Select your country'), 120);
    await tester.tap(find.text('Select your country'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you reading from?'), findsOneWidget);
    expect(find.text('Canada'), findsWidgets);
  });

  testWidgets('Onboarding DOB sheet is usable on compact web height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/onboarding/about', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select your date of birth'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a date'), findsOneWidget);
    expect(find.text('Use this date'), findsOneWidget);
    await tester.tap(find.text('Use this date'));
    await tester.pumpAndSettle();

    expect(find.text('Select your date of birth'), findsNothing);
  });

  testWidgets('Onboarding locks desktop nav exits', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/onboarding', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('How well do you know what everyone else thinks?'),
      findsOneWidget,
    );
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(
      find.text('How well do you know what everyone else thinks?'),
      findsOneWidget,
    );
    expect(find.text("Every call you've made."), findsNothing);

    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(
      find.text('How well do you know what everyone else thinks?'),
      findsOneWidget,
    );
    expect(find.text('Your Read Score'), findsNothing);
  });

  testWidgets('Auth email flow validates required fields before navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(false),
          rtwRouterProvider.overrideWithValue(
            GoRouter(
              initialLocation: '/auth',
              routes: [
                GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
                GoRoute(
                  path: '/onboarding',
                  builder: (_, _) => const OnboardingScreen(),
                ),
              ],
            ),
          ),
        ],
        child: const ReadTheWorldApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email and password.'), findsOneWidget);
    expect(find.text('Welcome to the daily read.'), findsNothing);
  });

  testWidgets('Auth screen matches source sign-in and create details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(false),
          rtwRouterProvider.overrideWithValue(
            GoRouter(
              initialLocation: '/auth',
              routes: [
                GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
              ],
            ),
          ),
        ],
        child: const ReadTheWorldApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Demo mode until Firebase credentials are added.'),
      findsNothing,
    );
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('••••••••'), findsOneWidget);

    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account.'), findsOneWidget);
    expect(find.text('at least 8 characters'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Already have an account? '), findsOneWidget);
  });

  testWidgets(
    'Feature flags hide party, friends, and result sharing surfaces',
    (tester) async {
      tester.view.physicalSize = const Size(393, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const settings = AppSettings(
        partyMode: false,
        friends: false,
        resultSharing: false,
      );

      await tester.pumpWidget(
        _testApp(
          initialLocation: '/history',
          routes: _demoRoutes(),
          appSettings: settings,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Party'), findsNothing);

      await tester.pumpWidget(
        _testApp(
          initialLocation: '/insights',
          routes: _demoRoutes(),
          appSettings: settings,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('FRIENDS'), findsNothing);
      expect(find.text('Invite a friend →'), findsNothing);

      await tester.pumpWidget(
        _testApp(
          initialLocation: '/reveal/demo',
          routes: _demoRoutes(),
          appSettings: settings,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Among your friends'), findsNothing);
      expect(find.text('Share this result'), findsNothing);

      await tester.pumpWidget(
        _testApp(
          initialLocation: '/invite/ABCD123',
          routes: _demoRoutes(),
          appSettings: settings,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Read the world together.'), findsNothing);
      expect(find.byType(InviteScreen), findsNothing);
      expect(find.byType(InsightsScreen), findsOneWidget);
    },
  );

  testWidgets('Friends leaderboard flag hides score rows but keeps invites', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        initialLocation: '/insights',
        routes: _demoRoutes(),
        appSettings: const AppSettings(friendsLeaderboard: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FRIENDS'), findsOneWidget);
    expect(find.text('Dana K.'), findsNothing);
    expect(find.text('Invite a friend →'), findsOneWidget);
  });

  testWidgets('Invite route renders accept flow', (tester) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(false),
          rtwControllerProvider.overrideWith((_) => _demoController()),
          rtwRouterProvider.overrideWithValue(
            GoRouter(
              initialLocation: '/invite/ABCD123',
              routes: [
                GoRoute(
                  path: '/invite/:code',
                  builder: (_, state) =>
                      InviteScreen(code: state.pathParameters['code'] ?? ''),
                ),
                GoRoute(
                  path: '/insights',
                  builder: (_, _) => const InsightsScreen(),
                ),
              ],
            ),
          ),
        ],
        child: const ReadTheWorldApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read the world together.'), findsOneWidget);
    expect(find.text('ABCD123'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Accept invite'),
      findsOneWidget,
    );
  });

  testWidgets('Daily loop answers, predicts, and locks locally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/today', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Now read the world \u2192'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Now read the world \u2192'),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('What share of people also said “Yes”?'),
      findsOneWidget,
    );
    expect(
      find.text("Would you want to know the exact date you'll die?"),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Lock in my prediction'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Lock in my prediction'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Locked in\nfor today.'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('50% say Yes'), findsOneWidget);
  });

  testWidgets('Today route redirects locked users to locked state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _demoController()
      ..selectedOptionId = 'yes'
      ..prediction = 68
      ..lockedToday = true;

    await tester.pumpWidget(
      _testApp(
        initialLocation: '/today',
        routes: _demoRoutes(),
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Locked in\nfor today.'), findsOneWidget);
    expect(find.text('68% say Yes'), findsOneWidget);
    expect(find.text('Can you read the world today?'), findsNothing);
  });

  testWidgets('Lock button routes while prediction submit is still pending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _SlowLockRtwController()
      ..today = todayQuestion
      ..liveCount = todayQuestion.totalAnswers
      ..selectedOptionId = 'yes'
      ..prediction = 62
      ..lastError = null;
    addTearDown(() {
      if (!controller.completer.isCompleted) {
        controller.completer.complete();
      }
    });

    await tester.pumpWidget(
      _testApp(
        initialLocation: '/today/predict',
        routes: _demoRoutes(),
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Lock in my prediction'),
    );
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Lock in my prediction'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Locked in\nfor today.'), findsOneWidget);
    expect(controller.submitting, isTrue);

    controller.completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Skipped reveal does not show a fake user guess', (tester) async {
    tester.view.physicalSize = const Size(393, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final skipped = buildDemoHistory().firstWhere(
      (entry) => entry.status == HistoryStatus.skipped,
    );

    await tester.pumpWidget(
      _testApp(
        initialLocation: '/reveal/${skipped.question.id}',
        routes: _demoRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(skipped.question.prompt), findsOneWidget);
    expect(
      find.textContaining("You didn't answer this one", findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('You guessed', findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('YOU 0%'), findsNothing);
    expect(find.text('READ ACCURACY'), findsNothing);
  });

  testWidgets('History review opens the selected reveal entry', (tester) async {
    tester.view.physicalSize = const Size(393, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/history', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    expect(find.text("Every call you've made."), findsOneWidget);
    await tester.tap(find.text('See the reveal →').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Should AI-generated content always be labelled?'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('READ ACCURACY'), 240);
    expect(find.text('READ ACCURACY'), findsOneWidget);
  });

  testWidgets('Party mode starts and reveals a replay card', (tester) async {
    tester.view.physicalSize = const Size(393, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/party', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read the room.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Start the round →'), 260);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Start the round →'));
    await tester.pumpAndSettle();

    expect(find.text('Reveal the world ↓'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reveal the world ↓'));
    await tester.pumpAndSettle();

    expect(find.textContaining('The world'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Next question →'),
      findsOneWidget,
    );
  });

  testWidgets('Party answer and predict mode advances through result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/party', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Answer & predict'), 260);
    await tester.tap(find.text('Answer & predict'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Start the round →'), 260);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Start the round →'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Yes').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('What share also answered'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Lock it in ↓'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Read score:'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Next question →'),
      findsOneWidget,
    );
  });

  testWidgets('Account profile edits local preferences', (tester) async {
    tester.view.physicalSize = const Size(393, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/account', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Mika');
    await tester.pumpAndSettle();
    expect(find.text('Mika'), findsOneWidget);

    await tester.tap(find.text('Change colour'));
    await tester.pumpAndSettle();
    expect(find.text('Daily reminder'), findsOneWidget);
  });

  testWidgets('Account edit opens the onboarding about step', (tester) async {
    tester.view.physicalSize = const Size(393, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/account', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Jan 1, 1989'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('A little about you.'), findsOneWidget);
    expect(
      find.text('How well do you know what everyone else thinks?'),
      findsNothing,
    );
  });

  testWidgets('Account logout routes to auth', (tester) async {
    tester.view.physicalSize = const Size(393, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/account', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    final logout = find.text('Log out').first;
    await tester.tap(logout);
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.'), findsOneWidget);
  });

  testWidgets('Accepting an invite lands on insights with local friend row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/invite/ABCD123', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Accept invite'));
    await tester.pumpAndSettle();

    expect(find.text('YOUR READ SCORE'), findsOneWidget);
    expect(find.text('New reader'), findsOneWidget);
  });

  testWidgets('Direct short-code app link resolves to invite flow locally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/ABCD123', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read the world together.'), findsOneWidget);
    expect(find.text('ABCD123'), findsOneWidget);
  });

  testWidgets('Reveal share action opens the result share sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        initialLocation: '/reveal/2026-06-25-technology-ai-labels',
        routes: _demoRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Share this result'), 260);
    await tester.ensureVisible(find.text('Share this result'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share this result'));
    await tester.pumpAndSettle();

    expect(find.text('SHARE YOUR RESULT'), findsOneWidget);
    expect(find.text('DAILY READ'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    final progress = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.last.value, 0.84);
  });

  testWidgets('Insights invite action opens the invite sheet', (tester) async {
    tester.view.physicalSize = const Size(393, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/insights', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Invite a friend →'), 260);
    await tester.tap(find.text('Invite a friend →'));
    await tester.pumpAndSettle();

    expect(find.text('INVITE A FRIEND'), findsOneWidget);
    expect(find.text('Compare your reads.'), findsOneWidget);
    expect(find.text('rtw.codes/demo'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share invite link'), findsOneWidget);
  });

  testWidgets('Insights friend rows match source default copy', (tester) async {
    tester.view.physicalSize = const Size(393, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(initialLocation: '/insights', routes: _demoRoutes()),
    );
    await tester.pumpAndSettle();

    expect(find.text('1,840'), findsNWidgets(2));
    expect(find.text('1,792'), findsOneWidget);
    expect(find.text('1,710'), findsOneWidget);
    expect(find.text('Scores only'), findsNWidgets(2));
    expect(find.text('Answers shared'), findsNothing);
    await tester.scrollUntilVisible(
      find.text(
        'Friends compare Read Scores. Tap a name to set answer visibility, or swipe to remove.',
      ),
      200,
    );
    expect(
      find.text(
        'Friends compare Read Scores. Tap a name to set answer visibility, or swipe to remove.',
      ),
      findsOneWidget,
    );
    expect(find.byType(Dismissible), findsNWidgets(2));
  });
}
