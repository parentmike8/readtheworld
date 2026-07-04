import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:read_the_world/app_settings.dart';
import 'package:read_the_world/main.dart';
import 'package:read_the_world/scoring.dart';
import 'package:read_the_world/v2/models_v2.dart';
import 'package:read_the_world/v2/party_controller.dart';
import 'package:read_the_world/v2/rooms_controller.dart';
import 'package:read_the_world/v2/screens/party_screen.dart';
import 'package:read_the_world/v2/screens/rooms_home.dart';

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
      final world = _binding(
        id: worldRoomId,
        name: 'The World',
        isWorld: true,
      )..myTodayAnswer = const RoomAnswer(
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

    test('solo rooms save answer-only', () {
      final rooms = _roomsWith([
        _binding(id: 'solo', name: 'Just You', members: 1),
      ]);
      rooms.enterToday();
      rooms.continueFromIntro();
      rooms.commitSide('b');
      expect(rooms.play!.stage, PlayStage.answerSaved);
      expect(rooms.play!.answerSavedReason, 'solo');
    });

    test('locked world is answer-only until the flag flips', () {
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
      expect(rooms.play!.answerSavedReason, 'world');

      rooms.worldPredictionsUnlocked = true;
      rooms.changeAnswer();
      rooms.commitSide('a');
      expect(rooms.play!.stage, PlayStage.predict);
    });

    test('answered world room reopens with saved picks for modification', () async {
      final world = _binding(
        id: worldRoomId,
        name: 'The World',
        members: 900,
        isWorld: true,
      )..myTodayAnswer = const RoomAnswer(
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
      expect(rooms.play!.stage, PlayStage.answerSaved);
      expect(rooms.play!.answerSavedReason, 'world');
      expect(rooms.play!.side, 'b');

      rooms.changeAnswer();
      rooms.commitSide('a');
      await rooms.lockCurrent(answerOnly: true);

      final picks = rooms.play!.results[worldRoomId]!;
      expect(picks, hasLength(3));
      expect(picks.firstWhere((pick) => pick.qid == 'q1').side, 'a');
      expect(rooms.play!.idx, 1);
      expect(rooms.play!.stage, PlayStage.answerSaved);
      expect(rooms.play!.side, 'a');
    });

    test('meter docks to the picked side and arms the flip at <=2', () {
      final rooms = _roomsWith([_binding(id: 'studio', name: 'The Studio')]);
      rooms.enterToday();
      rooms.continueFromIntro();
      rooms.commitSide('a');
      rooms.meterUpdate(0.0); // side A docks right: left edge = 100%
      expect(rooms.play!.pred, 100);
      rooms.meterUpdate(1.0);
      expect(rooms.play!.pred, 0);
      expect(rooms.play!.armSwitch, isTrue);
      rooms.meterRelease();
      expect(rooms.play!.side, 'b'); // flip fired
      expect(rooms.play!.pred, 50);
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

        rooms.commitSide('a');
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

        // No Firebase → locking is a silent no-op, never a throw.
        await rooms.lockIntroWorldAnswers(const [
          RoomPick(qid: 'q1', side: 'a'),
          RoomPick(qid: 'q2', side: 'b'),
          RoomPick(qid: 'q3', side: 'a'),
        ]);
        expect(rooms.lastError, isNull);

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

      expect(party.sub, PartySub.reveal);
      expect(party.readerRevealScore, 100); // |50-50|*1.3 = 0 off
      expect(party.scores[0], 100);
      expect(party.tableYesPct, 67); // 2 of 3 said Yes
    });

    test(
      'reader rotates per question and solo advances without predicting',
      () {
        final party = PartyController()
          ..setPlayers(2)
          ..setRounds(1);
        party.start([_partyQuestion('p1'), _partyQuestion('p2')]);
        expect(party.readerIndex, 0);
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
      multi.next();
      expect(multi.sub, PartySub.pass); // between questions: hand-off first
      expect(multi.turn, 0); // new reader answers first

      final solo = PartyController()
        ..setPlayers(1)
        ..setRounds(2);
      solo.start([_partyQuestion('s1'), _partyQuestion('s2')]);
      solo.next();
      expect(solo.sub, PartySub.pick); // solo skips the hand-off
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

    testWidgets('rooms tab renders the world hero and empty state', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rooms'));
      await tester.pumpAndSettle();
      expect(find.text('Read all of humanity.'), findsOneWidget);
      expect(find.text('No rooms yet'), findsOneWidget);
      expect(find.text('Have a code? Join a room'), findsOneWidget);
    });

    testWidgets('world hero CTA changes after answers are submitted', (
      tester,
    ) async {
      final world = _binding(
        id: worldRoomId,
        name: 'The World',
        isWorld: true,
      )..myTodayAnswer = const RoomAnswer(
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

      expect(find.text('View or modify your answers →'), findsOneWidget);
      expect(find.text('Answer world questions →'), findsNothing);
    });

    testWidgets('submitted room card exposes a modify action', (
      tester,
    ) async {
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

      expect(find.text('View or modify answers →'), findsOneWidget);
      expect(find.textContaining('Locked in'), findsNothing);
    });

    testWidgets('party tab renders setup and starts a local round', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Party'));
      await tester.pumpAndSettle();
      expect(find.text('Pass the phone.'), findsOneWidget);
      expect(find.text('Loading questions…'), findsOneWidget);
    });

    testWidgets('party play surface exposes swaps and the game menu', (
      tester,
    ) async {
      final party = PartyController()
        ..setPlayers(4)
        ..setRounds(1);
      party.start([for (var i = 1; i <= 8; i++) _partyQuestion('p$i')]);

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
      expect(find.text('Restart game'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Player 2'), 'Sam');
      await tester.pump();
      expect(party.playerName(1), 'Sam');
    });
  });
}
