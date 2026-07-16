import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:read_the_world/app_state.dart';
import 'package:read_the_world/app_settings.dart';
import 'package:read_the_world/main.dart';
import 'package:read_the_world/scoring.dart';
import 'package:read_the_world/v2/models_v2.dart';
import 'package:read_the_world/v2/mappers_v2.dart';
import 'package:read_the_world/v2/party_controller.dart';
import 'package:read_the_world/v2/review_tools.dart';
import 'package:read_the_world/v2/rooms_controller.dart';
import 'package:read_the_world/v2/screens/onboarding_screen.dart';
import 'package:read_the_world/v2/screens/party_screen.dart';
import 'package:read_the_world/v2/screens/play_surface.dart';
import 'package:read_the_world/v2/screens/profile_screen.dart';
import 'package:read_the_world/v2/screens/room_detail.dart';
import 'package:read_the_world/v2/screens/rooms_home.dart';
import 'package:read_the_world/v2/sheets/room_sheets.dart';
import 'package:read_the_world/v2/tokens_v2.dart';
import 'package:read_the_world/v2/widgets_v2.dart';

RoomDayQuestion _question(String qid, {String tag = 'Social'}) =>
    RoomDayQuestion(
      qid: qid,
      prompt: 'Prompt $qid?',
      optA: 'Yes',
      optB: 'No',
      tag: tag,
      shape: 'TASTE',
      custom: false,
    );

RoomBinding _binding({
  required String id,
  required String name,
  int members = 5,
  bool isWorld = false,
  List<String> qids = const ['q1', 'q2', 'q3'],
}) {
  return RoomBinding()
    ..room = RtwRoom(
      id: id,
      name: name,
      colorToken: 'oklch(0.50 0.10 256)',
      tier: RoomTier.normal,
      cats: const ['All'],
      customEnabled: true,
      memberCount: members,
      isWorld: isWorld,
    )
    ..today = RoomDay(
      dailyKey: '2026-07-02',
      status: 'live',
      questions: [for (final qid in qids) _question(qid)],
    );
}

RoomsController _roomsWith(List<RoomBinding> bindings) {
  final controller = RoomsController(firebaseReady: false);
  for (final binding in bindings) {
    controller.bindings[binding.room!.id] = binding;
  }
  controller.roomOrder = [for (final binding in bindings) binding.room!.id];
  controller.loadingRooms = false;
  return controller;
}

PartyQuestion _partyQuestion(
  String qid, {
  String tag = 'Social',
  String tier = 'work-safe',
}) => PartyQuestion(
  qid: qid,
  prompt: 'Party $qid?',
  optA: 'Yes',
  optB: 'No',
  tag: tag,
  shape: 'TASTE',
  tier: tier,
);

/// Drives one full party question to its reveal: the reader swipes a side and
/// locks a prediction, every voter swipes, and the reveal hand-off is taken.
void _playPartyQuestionToReveal(PartyController party, {int pred = 50}) {
  party.cardDragStart();
  party.cardDragUpdate(80);
  party.cardDragEnd(0);
  party.pred = pred;
  party.lockTurn();
  for (var voter = 1; voter < party.players; voter++) {
    party.passContinue();
    party.cardDragStart();
    party.cardDragUpdate(80);
    party.cardDragEnd(0);
  }
  party.passContinue(); // revealPass → reveal
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scoring', () {
    test('Read Accuracy uses absolute percentage-point error', () {
      expect(calculateReadAccuracy(predictedShare: 5, actualShare: 16), 89);
      expect(calculateReadAccuracy(predictedShare: 42, actualShare: 35), 93);
      expect(calculateReadAccuracy(predictedShare: 0, actualShare: 100), 0);
    });

    test('K-factor shrinks with games played', () {
      expect(kFactor(0), 32);
      expect(kFactor(10), 24);
      expect(kFactor(50), 16);
      expect(kFactor(150), 12);
    });
  });

  group('Private-room custom questions', () {
    test('review tools are limited to debug or iOS TestFlight builds', () {
      expect(
        reviewToolsAvailableFor(
          debugBuild: true,
          isIos: false,
          isTestFlight: false,
        ),
        isTrue,
      );
      expect(
        reviewToolsAvailableFor(
          debugBuild: false,
          isIos: true,
          isTestFlight: true,
        ),
        isTrue,
      );
      expect(
        reviewToolsAvailableFor(
          debugBuild: false,
          isIos: true,
          isTestFlight: false,
        ),
        isFalse,
      );
      expect(
        reviewToolsAvailableFor(
          debugBuild: false,
          isIos: false,
          isTestFlight: true,
        ),
        isFalse,
      );
    });

    test('named custom questions remain playable until reported', () {
      const official = RoomDayQuestion(
        qid: 'official',
        prompt: 'Official question?',
        optA: 'Yes',
        optB: 'No',
        tag: 'Social',
        shape: 'TASTE',
        custom: false,
      );
      const userCreated = RoomDayQuestion(
        qid: 'custom-1',
        prompt: 'User-created question?',
        optA: 'Yes',
        optB: 'No',
        tag: 'Custom',
        shape: 'CUSTOM',
        custom: true,
        authorUid: 'member-1',
        authorName: 'Taylor',
      );
      const day = RoomDay(
        dailyKey: '2026-07-11',
        status: 'live',
        questions: [official, userCreated],
      );

      expect(day.activeQuestions, [official, userCreated]);
      expect(day.answerableQuestions, [official, userCreated]);
      expect(day.activeQuestions.last.authorName, 'Taylor');
    });

    test(
      'debug preview exercises reporting without changing the live day',
      () async {
        final rooms = _roomsWith([_binding(id: 'studio', name: 'The Studio')]);
        const queued = QueueItem(
          id: 'queued-1',
          text: 'Should we order pizza?',
          optA: 'Yes',
          optB: 'No',
          authorUid: 'me',
          authorName: 'Michael',
        );

        rooms.startQueuedQuestionQaPreview('studio', queued);

        final preview = rooms.play?.card?.question;
        expect(rooms.play?.mode, 'qa');
        expect(preview?.prompt, queued.text);
        expect(preview?.custom, isTrue);
        expect(preview?.authorName, 'QA Guest');
        expect(rooms.bindingFor('studio')?.today?.questions, hasLength(3));

        final reported = await rooms.flagQuestion(
          'studio',
          preview!.qid,
          reason: 'other',
          blockAuthor: true,
        );

        expect(reported, isTrue);
        expect(rooms.play, isNull);
        expect(rooms.pendingPlayExitRoute, '/rooms/studio');
        expect(rooms.bindingFor('studio')?.today?.questions, hasLength(3));
      },
    );
  });

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
    container.read(roomsControllerProvider).enterToday();

    expect(identical(container.read(rtwRouterProvider), router), isTrue);
  });

  testWidgets('profile exposes a permanent account deletion flow', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreenV2()),
        GoRoute(path: '/auth', builder: (_, _) => const Text('Signed out')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(false),
          appSettingsProvider.overrideWithValue(AppSettings.defaults),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final deleteAccount = find.text('Delete account');
    expect(deleteAccount, findsOneWidget);
    await tester.ensureVisible(deleteAccount);
    await tester.tap(deleteAccount);
    await tester.pumpAndSettle();

    expect(find.text('Permanently delete your account?'), findsOneWidget);
    expect(find.text('Delete my account'), findsOneWidget);
    expect(find.text('Keep my account'), findsOneWidget);
  });

  testWidgets('room play exit returns to that room detail', (tester) async {
    final rooms = _roomsWith([_binding(id: 'studio', name: 'The Studio')]);
    rooms.startRoomPlay('studio');

    final router = GoRouter(
      initialLocation: '/today/play',
      routes: [
        GoRoute(path: '/today/play', builder: (_, _) => const RoomPlayScreen()),
        GoRoute(path: '/rooms', builder: (_, _) => const Text('Rooms index')),
        GoRoute(
          path: '/rooms/:roomId',
          builder: (_, state) => Text('Room ${state.pathParameters['roomId']}'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(false),
          appSettingsProvider.overrideWithValue(AppSettings.defaults),
          roomsControllerProvider.overrideWith(
            (_) => rooms,
            disposeNotifier: false,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/rooms/studio');
  });

  testWidgets('room detail redirects once membership is gone', (tester) async {
    final rooms = _roomsWith([]);
    final router = GoRouter(
      initialLocation: '/rooms/studio',
      routes: [
        GoRoute(path: '/rooms', builder: (_, _) => const Text('Rooms index')),
        GoRoute(
          path: '/rooms/:roomId',
          builder: (_, state) =>
              RoomDetailScreen(roomId: state.pathParameters['roomId'] ?? ''),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseReadyProvider.overrideWithValue(false),
          appSettingsProvider.overrideWithValue(AppSettings.defaults),
          roomsControllerProvider.overrideWith(
            (_) => rooms,
            disposeNotifier: false,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/rooms');
  });

  group('today deck', () {
    test('builds an intro card plus a question block per unplayed room', () {
      final rooms = _roomsWith([
        _binding(id: 'studio', name: 'The Studio'),
        _binding(id: 'fam', name: 'Family', qids: ['f1', 'f2']),
      ]);
      final deck = rooms.buildTodayDeck();
      expect(deck.length, 4 + 3); // intro+3, intro+2
      expect(deck[0].intro, isTrue);
      expect(deck[0].roomName, 'The Studio');
      expect(deck[1].question!.qid, 'q1');
      expect(deck[4].intro, isTrue);
      expect(deck[4].roomName, 'Family');
    });

    test('skips played rooms and pulled questions', () {
      final played = _binding(id: 'studio', name: 'The Studio')
        ..myTodayAnswer = const RoomAnswer(picks: [], answerOnly: false);
      final pulled = RoomBinding()
        ..room = _binding(id: 'fam', name: 'Family').room
        ..today = RoomDay(
          dailyKey: '2026-07-02',
          status: 'live',
          questions: [
            _question('f1'),
            const RoomDayQuestion(
              qid: 'f2',
              prompt: 'Pulled?',
              optA: 'Yes',
              optB: 'No',
              tag: 'Social',
              shape: 'GREY',
              custom: true,
              pulled: true,
            ),
          ],
        );
      final rooms = _roomsWith([played, pulled]);
      final deck = rooms.buildTodayDeck();
      expect(deck.where((card) => card.roomId == 'studio'), isEmpty);
      expect(deck.where((card) => !card.intro).length, 1);
    });

    test('skips world questions once the live world answer exists', () {
      final world = _binding(id: worldRoomId, name: 'The World', isWorld: true)
        ..myTodayAnswer = const RoomAnswer(
          picks: [RoomPick(qid: 'q1', side: 'a')],
          answerOnly: true,
        );
      final rooms = _roomsWith([])
        ..worldRoom = world.room
        ..worldToday = world.today
        ..bindings[worldRoomId] = world;

      expect(rooms.buildTodayDeck(), isEmpty);
    });
  });

  group('play state machine', () {
    test('swipe commit routes to predict with duo snap', () {
      final rooms = _roomsWith([
        _binding(id: 'duo', name: 'You & Sam', members: 2),
      ]);
      rooms.enterToday();
      rooms.continueFromIntro();
      rooms.commitSide('a');
      expect(rooms.play!.stage, PlayStage.predict);
      expect(rooms.play!.pred, 100); // duo starts at "they matched"
    });

    test('solo rooms now take an infinite-room prediction', () {
      final rooms = _roomsWith([
        _binding(id: 'solo', name: 'Just You', members: 1),
      ]);
      rooms.enterToday();
      rooms.continueFromIntro();
      rooms.commitSide('b');
      // Solo used to be answer-only; it now predicts a share of everyone so it
      // scores once the room fills [Mike].
      expect(rooms.play!.stage, PlayStage.predict);
      expect(rooms.play!.pred, 50);
    });

    test('the world always takes a prediction', () {
      final world = _binding(
        id: 'world',
        name: 'The World',
        members: 900,
        isWorld: true,
      );
      final rooms = _roomsWith([world]);
      rooms.worldRoom = world.room;
      rooms.worldToday = world.today;
      rooms.enterToday();
      rooms.continueFromIntro();
      rooms.commitSide('a');
      // The World now captures a prediction too; scoring waits for the
      // question to cross its threshold, not the meter to unlock.
      expect(rooms.play!.stage, PlayStage.predict);
    });

    test('caught up count includes The World with personal rooms', () {
      final test = _binding(id: 'test', name: 'Test')
        ..myTodayAnswer = const RoomAnswer(picks: [], answerOnly: false);
      final yeah = _binding(id: 'yeah', name: 'YEAH')
        ..myTodayAnswer = const RoomAnswer(picks: [], answerOnly: false);
      final world = _binding(
        id: worldRoomId,
        name: 'The World',
        members: 4,
        isWorld: true,
      )..myTodayAnswer = const RoomAnswer(picks: [], answerOnly: false);
      final rooms = _roomsWith([test, yeah])
        ..worldRoom = world.room
        ..worldToday = world.today
        ..bindings[worldRoomId] = world;

      expect(rooms.caughtUpCount, 3);
    });

    test(
      'answered world room reopens with saved picks for modification',
      () async {
        final world =
            _binding(
                id: worldRoomId,
                name: 'The World',
                members: 900,
                isWorld: true,
              )
              ..myTodayAnswer = const RoomAnswer(
                picks: [
                  RoomPick(qid: 'q1', side: 'b'),
                  RoomPick(qid: 'q2', side: 'a'),
                  RoomPick(qid: 'q3', side: 'b'),
                ],
                answerOnly: true,
              );
        final rooms = _roomsWith([])
          ..worldRoom = world.room
          ..worldToday = world.today
          ..bindings[worldRoomId] = world;

        rooms.startRoomPlay(worldRoomId);
        // World always predicts now, so a saved answer reopens on the editable
        // predict step at question 1 (not the old answer-only "saved" screen).
        expect(rooms.play!.stage, PlayStage.predict);
        expect(rooms.play!.side, 'b');

        rooms.changeAnswer();
        rooms.commitSide('a');
        await rooms.lockCurrent();

        final picks = rooms.play!.results[worldRoomId]!;
        expect(picks, hasLength(3));
        expect(picks.firstWhere((pick) => pick.qid == 'q1').side, 'a');
        expect(rooms.play!.idx, 1);
        expect(rooms.play!.stage, PlayStage.predict);
        expect(rooms.play!.side, 'a');
      },
    );

    test(
      'submitted room modification starts at question one with the saved pick',
      () {
        final room =
            _binding(
                id: 'studio',
                name: 'The Studio',
                qids: const ['q1', 'q2', 'q3'],
              )
              ..myTodayAnswer = const RoomAnswer(
                picks: [
                  RoomPick(qid: 'q1', side: 'b', prediction: 67),
                  RoomPick(qid: 'q2', side: 'a', prediction: 33),
                ],
                answerOnly: false,
              );
        final rooms = _roomsWith([room]);

        rooms.startRoomPlay('studio');

        expect(rooms.play, isNotNull);
        expect(rooms.play!.idx, 0);
        expect(rooms.play!.card!.question!.qid, 'q1');
        expect(rooms.play!.stage, PlayStage.predict);
        expect(rooms.play!.side, 'b');
        expect(rooms.play!.pred, 75);
      },
    );

    test('meter always runs left to right without switching sides', () {
      final rooms = _roomsWith([_binding(id: 'studio', name: 'The Studio')]);
      rooms.enterToday();
      rooms.continueFromIntro();
      rooms.commitSide('a');
      rooms.meterUpdate(0.0);
      expect(rooms.play!.pred, 0);
      rooms.meterUpdate(1.0);
      expect(rooms.play!.pred, 100);
      expect(rooms.play!.side, 'a');
    });

    test('small-room predictions snap to whole-person counts', () {
      final rooms = _roomsWith([
        _binding(id: 'small', name: 'Small Room', members: 4),
      ]);
      rooms.enterToday();
      rooms.continueFromIntro();
      rooms.commitSide('b');
      expect(rooms.play!.pred, 67); // 2 of 3 others.
      rooms.meterUpdate(0.0);
      expect(rooms.play!.pred, 0);
      rooms.meterUpdate(1.0);
      expect(rooms.play!.pred, 100);
    });

    test('large-room predictions move in one percent steps', () {
      final rooms = _roomsWith([
        _binding(id: 'large', name: 'Large Room', members: 102),
      ]);
      rooms.enterToday();
      rooms.continueFromIntro();
      rooms.commitSide('a');
      rooms.meterUpdate(0.25);
      expect(rooms.play!.pred, 25);
      rooms.meterUpdate(0.26);
      expect(rooms.play!.pred, 26);
    });

    test('room answer mapper accepts legacy predictedShare picks', () {
      final answer = roomAnswerFromFirestore({
        'picks': [
          {'qid': 'q1', 'side': 'b', 'predictedShare': 62},
        ],
        'answerOnly': false,
      });

      expect(answer.pickFor('q1')?.prediction, 62);
    });

    test(
      'intro session runs the real loop and captures picks one-shot',
      () async {
        final rooms = RoomsController(firebaseReady: false);
        rooms.startIntroSession([
          _question('w1'),
          _question('w2'),
          _question('w3'),
        ]);
        expect(rooms.play!.mode, 'intro');
        expect(rooms.play!.card!.roomMembers, 0);

        rooms.commitSide('a');
        expect(rooms.play!.pred, 50);
        rooms.meterUpdate(0.51);
        expect(rooms.play!.pred, 51);
        rooms.play!.pred = 70;
        await rooms.lockCurrent();
        rooms.commitSide('b');
        await rooms.lockCurrent();
        rooms.commitSide('a');
        await rooms.lockCurrent();

        expect(rooms.play, isNull);
        final picks = rooms.takeIntroPicks()!;
        expect(picks.length, 3);
        expect(picks[0].side, 'a');
        expect(picks[0].prediction, 70);
        expect(rooms.takeIntroPicks(), isNull); // one-shot
      },
    );

    test(
      'intro finish is safe without a server and hands off home actions',
      () async {
        final rooms = RoomsController(firebaseReady: false);

        // markOnboarded flips the local gate immediately.
        expect(rooms.hasOnboarded, isFalse);
        rooms.markOnboarded();
        expect(rooms.hasOnboarded, isTrue);
        expect(rooms.needsOnboarding, isFalse);

        // The closer's CTA is a one-shot flag for rooms home.
        rooms.pendingHomeAction = 'create';
        expect(rooms.pendingHomeAction, 'create');
      },
    );
  });

  group('party controller', () {
    test('deck cycles the filtered pool across rounds x players', () {
      final party = PartyController()
        ..setPlayers(3)
        ..setRounds(2);
      party.start([_partyQuestion('p1'), _partyQuestion('p2')]);
      expect(party.deck.length, 6);
      expect(party.stage, PartyStage.play);
    });

    test(
      'topics multi-select with All fallback; spice level gates the pool',
      () {
        final party = PartyController();
        final pool = [
          _partyQuestion('safe1', tag: 'Work'),
          _partyQuestion('safe2', tag: 'Social'),
          _partyQuestion('edgy1', tag: 'Social', tier: 'mature'),
        ];

        // Everyday default: mature stays out, all topics in.
        expect(party.poolFor(pool).map((q) => q.qid), ['safe1', 'safe2']);

        // Multi-select: two tags on, then dropping both falls back to All.
        party.toggleTopic('Work');
        party.toggleTopic('Social');
        expect(party.topics, {'Work', 'Social'});
        party.toggleTopic('Work');
        expect(party.poolFor(pool).map((q) => q.qid), ['safe2']);
        party.toggleTopic('Social');
        expect(party.topics, {'All'});

        // After Dark drops work-safe entirely and resets topics.
        party.toggleTopic('Work');
        party.setTier(RoomTier.mature);
        expect(party.topics, {'All'});
        expect(party.poolFor(pool).map((q) => q.qid), ['edgy1']);
      },
    );

    test('reader predicts, voters commit by swipe, scoring matches x1.3', () {
      final party = PartyController()
        ..setPlayers(3)
        ..setRounds(1);
      party.start([
        _partyQuestion('p1'),
        _partyQuestion('p2'),
        _partyQuestion('p3'),
      ]);

      // Reader (player 1) picks Yes, predicts 50% of the other two.
      party.cardDragStart();
      party.cardDragUpdate(80);
      party.cardDragEnd(0);
      expect(party.sub, PartySub.predict);
      party.meterUpdate(0.5);
      expect(party.pred % 50, 0); // snapped to 100/(3-1)=50 steps
      party.pred = 50;
      party.lockTurn();
      expect(party.sub, PartySub.pass);

      // Player 2 votes Yes, player 3 votes No -> actual = 50%.
      party.passContinue();
      party.cardDragStart();
      party.cardDragUpdate(80);
      party.cardDragEnd(0);
      party.passContinue();
      party.cardDragStart();
      party.cardDragUpdate(-80);
      party.cardDragEnd(0);

      expect(party.sub, PartySub.revealPass);
      expect(party.currentPlayerIndex, 0); // pass back to the reader
      party.passContinue();
      expect(party.sub, PartySub.reveal);
      expect(party.readerRevealScore, 100); // |50-50|*1.3 = 0 off
      expect(party.scores[0], 100);
      expect(party.otherPlayerCount, 2);
      expect(party.othersYesCount, 1);
      expect(party.othersYesPct, 50); // 1 of the other 2 said Yes
      expect(party.readerAgreementPct, 50);
    });

    test(
      'reader rotates per question and solo advances without predicting',
      () {
        final party = PartyController()
          ..setPlayers(2)
          ..setRounds(1);
        party.start([_partyQuestion('p1'), _partyQuestion('p2')]);
        expect(party.readerIndex, 0);
        _playPartyQuestionToReveal(party);
        party.next();
        expect(party.readerIndex, 1);

        final solo = PartyController()
          ..setPlayers(1)
          ..setRounds(1);
        solo.start([_partyQuestion('s1')]);
        solo.cardDragStart();
        solo.cardDragUpdate(80);
        solo.cardDragEnd(0);
        expect(solo.stage, PartyStage.done);
      },
    );

    test('advancing to a new question hands off via the pass screen', () {
      final multi = PartyController()
        ..setPlayers(3)
        ..setRounds(2);
      multi.start([_partyQuestion('p1'), _partyQuestion('p2')]);
      expect(multi.sub, PartySub.pick); // first question goes straight in
      _playPartyQuestionToReveal(multi);
      multi.next();
      expect(multi.sub, PartySub.pass); // between questions: hand-off first
      expect(multi.turn, 0); // new reader answers first

      final solo = PartyController()
        ..setPlayers(1)
        ..setRounds(2);
      solo.start([_partyQuestion('s1'), _partyQuestion('s2')]);
      solo.cardDragStart();
      solo.cardDragUpdate(80);
      solo.cardDragEnd(0);
      expect(solo.idx, 1);
      expect(solo.sub, PartySub.pick); // solo skips the hand-off
    });

    test('double-taps on lock and next advance exactly one step', () {
      final party = PartyController()
        ..setPlayers(3)
        ..setRounds(2);
      party.start([_partyQuestion('p1'), _partyQuestion('p2')]);

      // The reader locks; a second tap of the same button must be a no-op
      // instead of throwing on the cleared side or double-counting the pick.
      party.cardDragStart();
      party.cardDragUpdate(80);
      party.cardDragEnd(0);
      party.pred = 50;
      party.lockTurn();
      expect(party.lockTurn, returnsNormally);
      expect(party.turn, 1);
      expect(party.turnPicks, hasLength(1));
      expect(party.sub, PartySub.pass);

      // Finish the question, then double-tap "Next question".
      party.passContinue();
      party.cardDragStart();
      party.cardDragUpdate(80);
      party.cardDragEnd(0);
      party.passContinue();
      party.cardDragStart();
      party.cardDragUpdate(-80);
      party.cardDragEnd(0);
      party.passContinue();
      expect(party.sub, PartySub.reveal);

      final beforeIdx = party.idx;
      party.next();
      party.next();
      expect(party.idx, beforeIdx + 1); // exactly one question forward
      expect(party.stage, PartyStage.play);
      expect(party.sub, PartySub.pass);
    });

    test('undo rewinds the last committing move', () {
      final party = PartyController()
        ..setPlayers(3)
        ..setRounds(1);
      party.start([
        _partyQuestion('p1'),
        _partyQuestion('p2'),
        _partyQuestion('p3'),
      ]);
      expect(party.canUndo, isFalse);

      // Reader (player 1) picks and locks a prediction.
      party.cardDragStart();
      party.cardDragUpdate(80);
      party.cardDragEnd(0);
      party.pred = 50;
      party.lockTurn();
      expect(party.canUndo, isTrue);
      expect(party.sub, PartySub.pass); // handing to player 2

      // Player 2 misclicks -> undo returns to the reader's locked prediction.
      party.undo();
      expect(party.sub, PartySub.predict);
      expect(party.turn, 0);
      expect(party.turnPicks, isEmpty);
    });

    test('reader can swap questions with a per-game cap', () {
      final party = PartyController()
        ..setPlayers(3)
        ..setRounds(1);
      final pool = [for (var i = 1; i <= 8; i++) _partyQuestion('p$i')];
      party.start(pool);
      final originalQid = party.card!.qid;

      expect(party.canSwapQuestion, isTrue);

      // The reader can still swap after choosing a side but before locking
      // their prediction. Swapping resets them to the pick step.
      party.cardDragStart();
      party.cardDragUpdate(80);
      party.cardDragEnd(0);
      expect(party.sub, PartySub.predict);

      party.swapQuestion();
      expect(party.sub, PartySub.pick);
      expect(party.card!.qid, isNot(originalQid));
      expect(party.swapsUsed, 1);

      party.swapQuestion();
      party.swapQuestion();
      expect(party.swapsUsed, PartyController.maxSwaps);
      expect(party.canSwapQuestion, isFalse);
    });

    test('restart keeps player names and draws a fresh deck when possible', () {
      final party = PartyController()
        ..setPlayers(3)
        ..setRounds(1);
      final pool = [for (var i = 1; i <= 6; i++) _partyQuestion('p$i')];
      party.start(pool);
      party.setPlayerName(1, 'Sam');
      party.scores[1] = 42;
      final previousQids = party.deck.map((question) => question.qid).toSet();

      party.restartGame();

      expect(party.stage, PartyStage.play);
      expect(party.playerName(1), 'Sam');
      expect(party.scores, [0.0, 0.0, 0.0]);
      expect(party.swapsUsed, 0);
      expect(
        party.deck.where((question) => previousQids.contains(question.qid)),
        isEmpty,
      );
    });

    test('cached party pool excludes recently played questions', () {
      final rooms = RoomsController(firebaseReady: false);
      rooms.replacePartyPoolForTesting([
        _partyQuestion('p1'),
        _partyQuestion('p2'),
        _partyQuestion('p3'),
      ]);

      expect(rooms.partyPool.map((question) => question.qid), [
        'p1',
        'p2',
        'p3',
      ]);

      rooms.markPartyPlayed(['p2']);

      expect(rooms.partyPool.map((question) => question.qid), ['p1', 'p3']);
    });
  });

  group('v2 screens', () {
    Widget app() => ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(false),
        appSettingsProvider.overrideWithValue(AppSettings.defaults),
      ],
      child: const ReadTheWorldApp(),
    );

    testWidgets('today shows the caught-up state with no rooms', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text("You're all caught up."), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Rooms'), findsOneWidget);
      expect(find.text('Party'), findsOneWidget);
    });

    testWidgets('today starts when room data arrives after first build', (
      tester,
    ) async {
      final rooms = RoomsController(firebaseReady: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            roomsControllerProvider.overrideWith(
              (_) => rooms,
              disposeNotifier: false,
            ),
          ],
          child: const ReadTheWorldApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("You're all caught up."), findsOneWidget);

      final binding = _binding(id: 'studio', name: 'The Studio');
      rooms.bindings[binding.room!.id] = binding;
      rooms.roomOrder = [binding.room!.id];
      rooms.markTodaySeen(binding.room!.id);
      await tester.pump();
      await tester.pump();

      expect(find.text('The Studio'), findsWidgets);
      expect(find.text("You're all caught up."), findsNothing);

      await tester.tap(find.textContaining('Tap to start'));
      await tester.pumpAndSettle();

      expect(find.text('Prompt q1?'), findsOneWidget);
      expect(find.text("You're all caught up."), findsNothing);
    });

    testWidgets('rooms tab renders the world hero and empty state', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rooms'));
      await tester.pumpAndSettle();
      expect(find.text('Read all of humanity.'), findsOneWidget);
      expect(
        find.text(
          'Reveals and scoring only opens once 5K players have joined. '
          'Until then, answer daily and invite your friends!',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Play →'), findsOneWidget);
      expect(find.textContaining('more players to unlock'), findsNothing);
      expect(
        find.text('Invite friends to help unlock world scoring'),
        findsOneWidget,
      );
      expect(find.text('No rooms yet'), findsOneWidget);
      expect(find.text('Have a code? Join a room'), findsOneWidget);
    });

    testWidgets('world hero CTA changes after answers are submitted', (
      tester,
    ) async {
      final world = _binding(id: worldRoomId, name: 'The World', isWorld: true)
        ..myTodayAnswer = const RoomAnswer(
          picks: [RoomPick(qid: 'q1', side: 'a')],
          answerOnly: true,
        );
      final rooms = _roomsWith([])
        ..worldRoom = world.room
        ..worldToday = world.today
        ..bindings[worldRoomId] = world;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            roomsControllerProvider.overrideWith(
              (_) => rooms,
              disposeNotifier: false,
            ),
          ],
          child: const MaterialApp(home: RoomsHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review answers'), findsOneWidget);
      expect(find.bySemanticsLabel('Play →'), findsNothing);
      expect(find.bySemanticsLabel('Answer world questions →'), findsNothing);
    });

    testWidgets('profile exposes feedback composer', (tester) async {
      final profile = RtwController(firebaseReady: false)
        ..displayName = 'Mike'
        ..email = 'mike@example.com'
        ..lastError = null;

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

      expect(find.text('Share feedback'), findsOneWidget);

      await tester.ensureVisible(find.text('Share feedback'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share feedback'));
      await tester.pumpAndSettle();

      expect(find.text('Tell us what to fix.'), findsOneWidget);
      expect(find.text('Send feedback'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('submitted room card exposes a modify action', (tester) async {
      final room = _binding(id: 'studio', name: 'The Studio')
        ..myTodayAnswer = const RoomAnswer(
          picks: [RoomPick(qid: 'q1', side: 'a', prediction: 60)],
          answerOnly: false,
        );
      final rooms = _roomsWith([room]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            roomsControllerProvider.overrideWith(
              (_) => rooms,
              disposeNotifier: false,
            ),
          ],
          child: const MaterialApp(home: RoomsHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review answers'), findsOneWidget);
      expect(find.textContaining('Locked in'), findsNothing);
    });

    testWidgets(
      'locked world summary avoids tomorrow copy and returns to world detail',
      (tester) async {
        final world =
            _binding(id: worldRoomId, name: 'The World', isWorld: true)
              ..myTodayAnswer = const RoomAnswer(
                picks: [
                  RoomPick(qid: 'q1', side: 'a'),
                  RoomPick(qid: 'q2', side: 'b'),
                  RoomPick(qid: 'q3', side: 'a'),
                ],
                answerOnly: true,
              );
        final rooms = _roomsWith([world])
          ..worldRoom = world.room
          ..worldToday = world.today
          ..summaryRoomId = worldRoomId
          ..worldPredictionsUnlocked = false;
        final router = GoRouter(
          initialLocation: '/today/play',
          routes: [
            GoRoute(
              path: '/today/play',
              builder: (_, _) => const RoomPlayScreen(),
            ),
            GoRoute(
              path: '/rooms',
              builder: (_, _) => const Text('Rooms index'),
            ),
            GoRoute(
              path: '/rooms/:roomId',
              builder: (_, state) =>
                  Text('Room ${state.pathParameters['roomId']}'),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseReadyProvider.overrideWithValue(false),
              appSettingsProvider.overrideWithValue(AppSettings.defaults),
              roomsControllerProvider.overrideWith(
                (_) => rooms,
                disposeNotifier: false,
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('tomorrow'), findsNothing);
        expect(find.text('3 ANSWERED'), findsOneWidget);
        expect(find.widgetWithText(V2Button, 'Review answers'), findsOneWidget);
        expect(find.textContaining('You said'), findsNothing);

        await tester.tap(find.widgetWithText(V2Button, 'Back to The World'));
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/rooms/world');
      },
    );

    testWidgets('leave room confirms creator transfer', (tester) async {
      final binding = _binding(id: 'studio', name: 'The Studio', members: 3)
        ..me = const RtwRoomMember(
          uid: 'u1',
          displayName: 'You',
          role: 'creator',
          revealMine: false,
          roomScore: 1500,
          streak: 0,
          questionsAnswered: 0,
        );
      final rooms = _roomsWith([binding]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            roomsControllerProvider.overrideWith(
              (_) => rooms,
              disposeNotifier: false,
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showRoomMenuSheet(
                      context,
                      ref,
                      'studio',
                      onHistory: () {},
                    ),
                    child: const Text('Open room menu'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open room menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();

      expect(find.text('Leave The Studio?'), findsOneWidget);
      expect(find.textContaining('creator status will move'), findsOneWidget);
      expect(find.text('Stay in room'), findsOneWidget);
    });

    testWidgets('prediction readout uses fractions for small rooms', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PredictionReadout(
              percent: 67,
              people: 3,
              sideLabel: 'Yes',
              sideColor: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.text('How many will agree with you?'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('of 3'), findsOneWidget);
      expect(find.text('Would pick “Yes”'), findsOneWidget);
      expect(find.text('67% of the room'), findsOneWidget);
    });

    testWidgets('prediction readout uses percent plus count for large rooms', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PredictionReadout(
              percent: 75,
              people: 32,
              sideLabel: 'Yes',
              sideColor: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.text('75%'), findsOneWidget);
      expect(find.text('24 of 32 players'), findsOneWidget);
    });

    testWidgets('intro prediction is clearly distinguished from a result', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PredictionReadout(
              percent: 50,
              people: 0,
              sideLabel: 'Yes',
              sideColor: Colors.blue,
              infinite: true,
              eyebrow: 'NEXT: MAKE A PREDICTION',
              prompt: 'What % of people do you think will also choose “Yes”?',
              sideCaption: 'This is your prediction. Results come later.',
              secondaryText: '',
            ),
          ),
        ),
      );

      expect(find.text('NEXT: MAKE A PREDICTION'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(
        find.text('This is your prediction. Results come later.'),
        findsOneWidget,
      );
      expect(find.text('of people who answer'), findsNothing);
    });

    testWidgets('prediction meter switches from notches to guide lines', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PredictionAgreementMeter(
                  percent: 67,
                  people: 3,
                  onUpdate: (_) {},
                ),
                PredictionAgreementMeter(
                  percent: 75,
                  people: 16,
                  onUpdate: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('prediction-meter-person-notch')),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const ValueKey('prediction-meter-guide')),
        findsNWidgets(3),
      );
      expect(find.text('ALL 3'), findsOneWidget);
      expect(find.text('ALL 16'), findsOneWidget);
    });

    testWidgets('prediction meter can begin without a selected value', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PredictionAgreementMeter(
              percent: 50,
              people: 0,
              infinite: true,
              showSelection: false,
              onUpdate: (_) {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('prediction-meter-fill')), findsNothing);
      expect(
        find.byKey(const ValueKey('prediction-meter-handle')),
        findsNothing,
      );
      expect(find.text('NO ONE'), findsOneWidget);
      expect(find.text('EVERYONE'), findsOneWidget);
    });

    testWidgets('onboarding scoring explainer renders after practice', (
      tester,
    ) async {
      final rooms = RoomsController(firebaseReady: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            roomsControllerProvider.overrideWith(
              (_) => rooms,
              disposeNotifier: false,
            ),
          ],
          child: const MaterialApp(home: OnboardingScreenV2()),
        ),
      );
      await tester.pump();
      expect(rooms.play, isNotNull);

      for (var i = 0; i < 3; i++) {
        rooms.commitSide('a');
        rooms.meterUpdate(0.25);
        await rooms.lockCurrent();
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('Closer predictions score more.'), findsOneWidget);
      expect(find.text('65% of people chose Yes'), findsOneWidget);
      expect(find.text('You predicted 25%'), findsOneWidget);
      expect(find.text('40 points apart'), findsOneWidget);
      expect(
        find.text(
          'Your Read Score rises or falls based on how your prediction ranks in the room.',
        ),
        findsOneWidget,
      );
      expect(
        find.text("It's not about being right.\nIt's about reading the room."),
        findsOneWidget,
      );
      expect(
        find.text('The farther away, the fewer points you earn.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('party tab renders setup and starts a local round', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Party'));
      await tester.pumpAndSettle();
      expect(find.text('Pass the phone.'), findsOneWidget);
      expect(
        find.text('Play with everyone in the room, right from your phone.'),
        findsOneWidget,
      );
      expect(find.text('Load more questions'), findsOneWidget);
    });

    testWidgets('party play surface exposes swaps and the game menu', (
      tester,
    ) async {
      final party = PartyController()
        ..setPlayers(4)
        ..setRounds(1);
      party.start([for (var i = 1; i <= 8; i++) _partyQuestion('p$i')]);
      party.scores[1] = 42;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            partyControllerProvider.overrideWith(
              (_) => party,
              disposeNotifier: false,
            ),
            roomsControllerProvider.overrideWith(
              (_) => RoomsController(firebaseReady: false),
            ),
          ],
          child: const MaterialApp(home: PartyScreenV2()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Player 1's turn"), findsOneWidget);
      expect(find.textContaining('Swap question'), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Game menu'), findsOneWidget);
      expect(find.text('LEADERBOARD'), findsOneWidget);
      expect(find.text('EDIT PLAYER NAMES'), findsOneWidget);
      expect(find.text('Restart game'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Player 2'), 'Sam');
      await tester.pump();
      expect(party.playerName(1), 'Sam');

      await tester.ensureVisible(find.widgetWithText(V2Button, 'Restart game'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(V2Button, 'Restart game'));
      await tester.pumpAndSettle();
      expect(find.text('Start over?'), findsOneWidget);
      expect(party.scores[1], 42);

      await tester.tap(find.widgetWithText(V2Button, 'Restart now'));
      await tester.pumpAndSettle();
      expect(party.scores[1], 0);
      expect(party.playerName(1), 'Sam');
    });

    testWidgets('party reveal returns to reader before advancing', (
      tester,
    ) async {
      final party = PartyController()
        ..setPlayers(3)
        ..setRounds(1);
      party.start([_partyQuestion('p1')]);

      // The reader says Yes and predicts one of the other two will agree.
      party.cardDragStart();
      party.cardDragUpdate(80);
      party.cardDragEnd(0);
      party.pred = 50;
      party.lockTurn();

      // The other players split Yes/No, so the reveal basis is 1 of 2.
      party.passContinue();
      party.cardDragStart();
      party.cardDragUpdate(80);
      party.cardDragEnd(0);
      party.passContinue();
      party.cardDragStart();
      party.cardDragUpdate(-80);
      party.cardDragEnd(0);

      expect(party.sub, PartySub.revealPass);
      expect(party.currentPlayerIndex, 0);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            partyControllerProvider.overrideWith(
              (_) => party,
              disposeNotifier: false,
            ),
            roomsControllerProvider.overrideWith(
              (_) => RoomsController(firebaseReady: false),
            ),
          ],
          child: const MaterialApp(home: PartyScreenV2()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pass back for the reveal.'), findsOneWidget);
      expect(find.widgetWithText(V2Button, "I'm Player 1"), findsOneWidget);
      expect(find.text('OTHER PLAYERS · 1 of 2 said Yes'), findsNothing);

      await tester.tap(find.widgetWithText(V2Button, "I'm Player 1"));
      await tester.pumpAndSettle();

      expect(find.text('OTHER PLAYERS · 1 of 2 said Yes'), findsOneWidget);
      expect(find.textContaining('2 of 3 said Yes'), findsNothing);
      expect(party.readerRevealScore, 100);

      await tester.tap(find.widgetWithText(V2Button, 'Next question'));
      await tester.pumpAndSettle();

      expect(party.readerIndex, 1);
      expect(party.currentPlayerIndex, 1);
      expect(find.widgetWithText(V2Button, "I'm Player 2"), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      party.dispose();
    });

    testWidgets('party pick gutters choose the nearest side', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final party = PartyController()
        ..setPlayers(4)
        ..setRounds(1);
      party.start([_partyQuestion('p1')]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            partyControllerProvider.overrideWith(
              (_) => party,
              disposeNotifier: false,
            ),
            roomsControllerProvider.overrideWith(
              (_) => RoomsController(firebaseReady: false),
            ),
          ],
          child: const MaterialApp(home: PartyScreenV2()),
        ),
      );
      await tester.pumpAndSettle();

      final pickZone = tester.getRect(
        find.byKey(const ValueKey('party-pick-zone')),
      );
      final promptCenter = tester.getCenter(find.text('Party p1?'));
      await tester.tapAt(Offset(pickZone.left + 24, promptCenter.dy));
      await tester.pump(
        RtwV2Motion.cardFling + const Duration(milliseconds: 1),
      );

      expect(party.side, 'b');
      expect(party.sub, PartySub.predict);
    });

    testWidgets('room play gutters choose the nearest side', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rooms = _roomsWith([
        _binding(id: 'studio', name: 'The Studio', qids: const ['q1']),
      ]);
      rooms.startRoomPlay('studio');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            roomsControllerProvider.overrideWith(
              (_) => rooms,
              disposeNotifier: false,
            ),
          ],
          child: MaterialApp(home: PlaySurface(session: rooms.play!)),
        ),
      );
      await tester.pumpAndSettle();

      final pickZone = tester.getRect(
        find.byKey(const ValueKey('play-pick-zone')),
      );
      final promptCenter = tester.getCenter(find.text('Prompt q1?'));
      await tester.tapAt(Offset(pickZone.right - 24, promptCenter.dy));
      await tester.pump(
        RtwV2Motion.cardFling + const Duration(milliseconds: 1),
      );

      expect(rooms.play!.side, 'a');
      expect(rooms.play!.stage, PlayStage.predict);
    });

    testWidgets('question reaction buttons do not choose a side', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rooms = _roomsWith([
        _binding(id: 'studio', name: 'The Studio', qids: const ['q1']),
      ]);
      rooms.startRoomPlay('studio');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            roomsControllerProvider.overrideWith(
              (_) => rooms,
              disposeNotifier: false,
            ),
          ],
          child: MaterialApp(home: PlaySurface(session: rooms.play!)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Like question'));
      await tester.pump(
        RtwV2Motion.cardFling + const Duration(milliseconds: 1),
      );

      expect(rooms.reactionForQuestion('q1'), QuestionReaction.liked);
      expect(rooms.play!.side, isNull);
      expect(rooms.play!.stage, PlayStage.pick);
      expect(find.byIcon(Icons.thumb_up_alt), findsOneWidget);
    });

    testWidgets('custom questions show their author and a report path', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final binding = _binding(id: 'studio', name: 'The Studio', qids: const [])
        ..today = const RoomDay(
          dailyKey: '2026-07-11',
          status: 'live',
          questions: [
            RoomDayQuestion(
              qid: 'custom-1',
              prompt: 'Should we order pizza?',
              optA: 'Yes',
              optB: 'No',
              tag: 'Custom',
              shape: 'CUSTOM',
              custom: true,
              authorUid: 'member-1',
              authorName: 'Taylor',
            ),
          ],
        );
      final rooms = _roomsWith([binding]);
      rooms.startRoomPlay('studio');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseReadyProvider.overrideWithValue(false),
            appSettingsProvider.overrideWithValue(AppSettings.defaults),
            roomsControllerProvider.overrideWith(
              (_) => rooms,
              disposeNotifier: false,
            ),
          ],
          child: MaterialApp(home: PlaySurface(session: rooms.play!)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SUBMITTED BY TAYLOR'), findsOneWidget);
      await tester.tap(find.byTooltip('Report this question'));
      await tester.pumpAndSettle();

      expect(find.text('REPORT QUESTION'), findsOneWidget);
      expect(find.textContaining('private room'), findsOneWidget);
      expect(find.text('Report & remove for everyone'), findsOneWidget);
      expect(rooms.play!.side, isNull);
    });
  });
}
