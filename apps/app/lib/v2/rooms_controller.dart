import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mappers_v2.dart';
import 'models_v2.dart';
import 'tokens_v2.dart';

const worldRoomId = 'world';

/// Live view of one room the user belongs to: room doc + my member doc +
/// today's question set + my locked answer for it.
class RoomBinding {
  RtwRoom? room;
  RtwRoomMember? me;
  RoomDay? today;
  RoomAnswer? myTodayAnswer;
  bool todaySeen = false;

  bool get played => myTodayAnswer != null;
  bool get hasUnseenReveal {
    final lastClosed = room?.lastClosedDailyKey;
    if (lastClosed == null) return false;
    return me?.revealSeenDailyKey != lastClosed;
  }
}

/// One closed day in a room's history: the day doc plus my locked answer.
class RoomHistoryDay {
  const RoomHistoryDay({required this.day, this.myAnswer});

  final RoomDay day;
  final RoomAnswer? myAnswer;
}

/// Reveal payload for a room's most recently closed day.
class RoomRevealData {
  const RoomRevealData({
    required this.dailyKey,
    required this.day,
    required this.myAnswer,
  });

  final String dailyKey;
  final RoomDay day;
  final RoomAnswer? myAnswer;
}

/// In-flight play state, mirroring the prototype's `play` object.
class PlaySession {
  PlaySession({
    required this.mode,
    required this.deck,
    this.roomId,
  });

  /// 'today' (cross-room deck with intro cards) or 'room' (single block).
  final String mode;
  final List<TodayDeckCard> deck;
  final String? roomId;

  int idx = 0;
  PlayStage stage = PlayStage.pick;
  String? side; // 'a' | 'b'
  int pred = 50;
  double dragX = 0;
  bool dragging = false;
  bool armSwitch = false;
  String? answerSavedReason; // 'world' | 'solo'

  /// Accumulated picks per room; a room's picks submit when its block ends.
  final Map<String, List<RoomPick>> results = {};

  TodayDeckCard? get card => idx >= 0 && idx < deck.length ? deck[idx] : null;
  bool get isRoomIntro => card?.intro ?? false;
  bool get atEnd => idx >= deck.length;
}

class RoomsController extends ChangeNotifier {
  RoomsController({required this.firebaseReady}) {
    if (firebaseReady) {
      _bindAuth();
    } else {
      loadingRooms = false; // Nothing will ever load without Firebase.
    }
  }

  final bool firebaseReady;

  final Map<String, RoomBinding> bindings = {};
  List<String> roomOrder = [];
  RtwRoom? worldRoom;
  RoomDay? worldToday;
  PlaySession? play;

  /// Set when a room-mode round just finished — drives the summary screen.
  String? summaryRoomId;

  /// One-shot action for rooms home after the intro ('create' | 'join').
  String? pendingHomeAction;

  String? lastError;
  bool submitting = false;
  bool loadingRooms = true;

  /// users/{uid} profile doc state — gates the first-run onboarding demo.
  bool profileLoaded = false;
  bool hasOnboarded = false;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membershipsSub;
  final Map<String, List<StreamSubscription<dynamic>>> _roomSubs = {};
  final List<StreamSubscription<dynamic>> _worldSubs = [];
  String? _boundUid;
  bool _crossedCommitThreshold = false;

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  HttpsCallable _callable(String name) =>
      FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(name);

  // ── auth / listeners ──────────────────────────────────────────────────

  void _bindAuth() {
    _authSub = FirebaseAuth.instance.userChanges().listen((user) {
      if (_boundUid == user?.uid) return;
      _boundUid = user?.uid;
      _clearRoomSubs();
      _membershipsSub?.cancel();
      _profileSub?.cancel();
      bindings.clear();
      roomOrder = [];
      play = null;
      summaryRoomId = null;
      loadingRooms = true;
      profileLoaded = false;
      hasOnboarded = false;
      notifyListeners();
      if (user == null) return;
      _bindProfile(user.uid);
      _bindMemberships(user.uid);
      _bindWorld(user.uid);
    });
  }

  void _bindProfile(String uid) {
    _profileSub = _db.collection('users').doc(uid).snapshots().listen((snapshot) {
      hasOnboarded = hasOnboarded || snapshot.data()?['onboardedAt'] != null;
      profileLoaded = true;
      notifyListeners();
    }, onError: _handleError);
  }

  /// Stamp the profile so the intro never auto-plays again (replayable
  /// from the profile screen). Local flag flips immediately; the write
  /// persists it across restarts.
  void markOnboarded() {
    if (hasOnboarded) return;
    hasOnboarded = true;
    notifyListeners();
    if (!firebaseReady) return;
    final currentUid = uid;
    if (currentUid == null) return;
    unawaited(
      _db.collection('users').doc(currentUid).set({
        'onboardedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((Object error) {
        _handleError(error);
      }),
    );
  }

  /// True while a signed-in first-run user should be shown the intro demo:
  /// profile + memberships have both loaded, no real rooms, never onboarded.
  bool get needsOnboarding =>
      firebaseReady &&
      profileLoaded &&
      !loadingRooms &&
      !hasOnboarded &&
      roomOrder.where((id) => id != worldRoomId).isEmpty;

  void _bindMemberships(String uid) {
    _membershipsSub = _db
        .collection('users')
        .doc(uid)
        .collection('memberships')
        .snapshots()
        .listen((snapshot) {
          final current = snapshot.docs.map((doc) => doc.id).toSet();
          for (final roomId in bindings.keys.toList()) {
            if (!current.contains(roomId)) _unbindRoom(roomId);
          }
          for (final doc in snapshot.docs) {
            if (!bindings.containsKey(doc.id)) _bindRoom(doc.id, uid);
          }
          roomOrder = snapshot.docs.map((doc) => doc.id).toList()
            ..sort((a, b) {
              final aJoined = bindings[a]?.room?.createdBy ?? '';
              final bJoined = bindings[b]?.room?.createdBy ?? '';
              return aJoined.compareTo(bJoined);
            });
          loadingRooms = false;
          notifyListeners();
        }, onError: _handleError);
  }

  void _bindRoom(String roomId, String uid) {
    final binding = RoomBinding();
    bindings[roomId] = binding;
    final subs = <StreamSubscription<dynamic>>[];
    _roomSubs[roomId] = subs;
    final roomDoc = _db.collection('rooms').doc(roomId);

    subs.add(roomDoc.snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      final previousKey = binding.room?.currentDailyKey;
      binding.room = roomFromFirestore(snapshot.id, data);
      final nextKey = binding.room!.currentDailyKey;
      if (nextKey != null && nextKey != previousKey) {
        _bindRoomDay(roomId, uid, nextKey, subs, binding);
      }
      notifyListeners();
    }, onError: _handleError));

    subs.add(roomDoc.collection('members').doc(uid).snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      binding.me = roomMemberFromFirestore(uid, data);
      notifyListeners();
    }, onError: _handleError));
  }

  void _bindRoomDay(
    String roomId,
    String uid,
    String dailyKey,
    List<StreamSubscription<dynamic>> subs,
    RoomBinding binding,
  ) {
    // Replace prior day + answer listeners (indexes 2 and 3).
    while (subs.length > 2) {
      subs.removeLast().cancel();
    }
    final dayRef = _db
        .collection('rooms')
        .doc(roomId)
        .collection('days')
        .doc(dailyKey);
    subs.add(dayRef.snapshots().listen((snapshot) {
      final data = snapshot.data();
      binding.today = data == null ? null : roomDayFromFirestore(snapshot.id, data);
      notifyListeners();
    }, onError: _handleError));
    subs.add(dayRef.collection('answers').doc(uid).snapshots().listen((snapshot) {
      final data = snapshot.data();
      binding.myTodayAnswer = data == null ? null : roomAnswerFromFirestore(data);
      notifyListeners();
    }, onError: _handleError));
  }

  void _bindWorld(String uid) {
    final worldDoc = _db.collection('rooms').doc(worldRoomId);
    _worldSubs.add(worldDoc.snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;
      final previousKey = worldRoom?.currentDailyKey;
      worldRoom = roomFromFirestore(snapshot.id, data);
      final nextKey = worldRoom!.currentDailyKey;
      if (nextKey != null && nextKey != previousKey) {
        while (_worldSubs.length > 1) {
          _worldSubs.removeLast().cancel();
        }
        _worldSubs.add(
          worldDoc.collection('days').doc(nextKey).snapshots().listen((daySnap) {
            final dayData = daySnap.data();
            worldToday =
                dayData == null ? null : roomDayFromFirestore(daySnap.id, dayData);
            notifyListeners();
          }, onError: _handleError),
        );
      }
      notifyListeners();
    }, onError: _handleError));
  }

  void _unbindRoom(String roomId) {
    for (final sub in _roomSubs.remove(roomId) ?? const <StreamSubscription<dynamic>>[]) {
      sub.cancel();
    }
    bindings.remove(roomId);
  }

  void _clearRoomSubs() {
    for (final subs in _roomSubs.values) {
      for (final sub in subs) {
        sub.cancel();
      }
    }
    _roomSubs.clear();
    for (final sub in _worldSubs) {
      sub.cancel();
    }
    _worldSubs.clear();
    worldRoom = null;
    worldToday = null;
  }

  void _handleError(Object error) {
    lastError = error.toString();
    notifyListeners();
  }

  // ── derived views ─────────────────────────────────────────────────────

  /// Rooms for the home list (world excluded — it renders as the hero).
  List<RoomBinding> get visibleRooms => roomOrder
      .where((id) => id != worldRoomId)
      .map((id) => bindings[id])
      .whereType<RoomBinding>()
      .where((binding) => binding.room != null)
      .toList();

  List<RoomBinding> get unplayedRooms => visibleRooms
      .where(
        (binding) =>
            !binding.played && (binding.today?.activeQuestions.isNotEmpty ?? false),
      )
      .toList();

  int get caughtUpCount => visibleRooms.where((binding) => binding.played).length;

  RoomBinding? bindingFor(String? roomId) =>
      roomId == null ? null : (roomId == worldRoomId ? _worldBinding : bindings[roomId]);

  RoomBinding? get _worldBinding {
    if (worldRoom == null) return null;
    final binding = bindings[worldRoomId] ?? RoomBinding();
    binding.room = worldRoom;
    binding.today ??= worldToday;
    return binding;
  }

  // ── deck building (mirrors prototype buildTodayDeck) ──────────────────

  List<TodayDeckCard> buildTodayDeck() {
    final deck = <TodayDeckCard>[];
    void addRoomBlock(RtwRoom room, RoomDay day) {
      final questions = day.activeQuestions;
      if (questions.isEmpty) return;
      deck.add(TodayDeckCard.intro(
        roomId: room.id,
        roomName: room.name,
        roomColorToken: room.colorToken,
        roomMembers: room.memberCount,
        roomTotal: questions.length,
        isWorld: room.isWorld,
      ));
      for (var i = 0; i < questions.length; i++) {
        deck.add(TodayDeckCard.question(
          roomId: room.id,
          roomName: room.name,
          roomColorToken: room.colorToken,
          roomMembers: room.memberCount,
          roomTotal: questions.length,
          isWorld: room.isWorld,
          question: questions[i],
          indexInRoom: i,
        ));
      }
    }

    for (final binding in unplayedRooms) {
      addRoomBlock(binding.room!, binding.today!);
    }
    final world = _worldBinding;
    if (world != null &&
        world.room != null &&
        worldToday != null &&
        !(world.played) &&
        worldToday!.isLive) {
      // Only include world questions the user hasn't answered; the whole
      // block drops out once answered (answer doc exists).
      addRoomBlock(world.room!, worldToday!);
    }
    return deck;
  }

  void enterToday() {
    final deck = buildTodayDeck();
    play = deck.isEmpty ? null : PlaySession(mode: 'today', deck: deck);
    notifyListeners();
  }

  void startRoomPlay(String roomId) {
    final binding = bindingFor(roomId);
    final room = binding?.room;
    final day = roomId == worldRoomId ? worldToday : binding?.today;
    if (room == null || day == null) return;
    final questions = day.activeQuestions;
    final deck = <TodayDeckCard>[
      for (var i = 0; i < questions.length; i++)
        TodayDeckCard.question(
          roomId: room.id,
          roomName: room.name,
          roomColorToken: room.colorToken,
          roomMembers: room.memberCount,
          roomTotal: questions.length,
          isWorld: room.isWorld,
          question: questions[i],
          indexInRoom: i,
        ),
    ];
    if (deck.isEmpty) return;
    play = PlaySession(mode: 'room', deck: deck, roomId: roomId);
    notifyListeners();
  }

  void exitPlay() {
    play = null;
    notifyListeners();
  }

  /// Intro answers lock straight to The World (auto-enrolls on first
  /// answer server-side; double-locks are a no-op).
  Future<void> lockIntroWorldAnswers(List<RoomPick> picks) async {
    if (!firebaseReady || picks.isEmpty) return;
    await _submitRoomPicks(worldRoomId, picks);
  }

  void dismissSummary() {
    summaryRoomId = null;
    notifyListeners();
  }

  // ── swipe / gesture handlers (prototype thresholds, native physics) ───

  void cardDragStart() {
    final session = play;
    if (session == null || session.stage != PlayStage.pick) return;
    session.dragging = true;
    session.dragX = 0;
    _crossedCommitThreshold = false;
    notifyListeners();
  }

  void cardDragUpdate(double deltaX) {
    final session = play;
    if (session == null || !session.dragging) return;
    session.dragX = (session.dragX + deltaX)
        .clamp(-RtwV2Motion.dragClamp, RtwV2Motion.dragClamp);
    final crossed = session.dragX.abs() > RtwV2Motion.commitThreshold;
    if (crossed && !_crossedCommitThreshold) {
      unawaited(HapticFeedback.selectionClick());
    }
    _crossedCommitThreshold = crossed;
    notifyListeners();
  }

  void cardDragEnd(double velocityX) {
    final session = play;
    if (session == null || !session.dragging) return;
    session.dragging = false;
    const flingVelocity = 700.0;
    final dx = session.dragX;
    final fastFling = velocityX.abs() > flingVelocity &&
        dx.sign == velocityX.sign &&
        dx.abs() > 12;
    if (dx > RtwV2Motion.commitThreshold || (fastFling && velocityX > 0)) {
      commitSide('a');
    } else if (dx < -RtwV2Motion.commitThreshold || (fastFling && velocityX < 0)) {
      commitSide('b');
    } else {
      session.dragX = 0;
      notifyListeners();
    }
  }

  void tapSide(String side) {
    final session = play;
    if (session == null || session.stage != PlayStage.pick) return;
    session.dragging = false;
    session.dragX = side == 'a' ? RtwV2Motion.flingDistance : -RtwV2Motion.flingDistance;
    notifyListeners();
    Timer(RtwV2Motion.cardFling, () {
      if (play == session && session.stage == PlayStage.pick) commitSide(side);
    });
  }

  void commitSide(String side) {
    final session = play;
    final card = session?.card;
    if (session == null || card == null || card.intro) return;
    unawaited(HapticFeedback.mediumImpact());
    final binding = bindingFor(card.roomId);
    final worldLocked = card.isWorld && !worldPredictionsUnlocked;
    final solo = !card.isWorld && (binding?.room?.isSolo ?? false);
    if (worldLocked || solo) {
      session.stage = PlayStage.answerSaved;
      session.answerSavedReason = worldLocked ? 'world' : 'solo';
      session.side = side;
      session.dragX = 0;
      session.armSwitch = false;
      notifyListeners();
      return;
    }
    session.stage = PlayStage.predict;
    session.side = side;
    // Duo rooms start at "the other person matched" (prototype: pred=100).
    session.pred = (binding?.room?.isDuo ?? false) ? 100 : 50;
    session.dragX = 0;
    session.armSwitch = false;
    notifyListeners();
  }

  /// Whether The World allows predictions (flipped from the admin panel).
  /// Mirrored from whether today's world answers carry predictions server-side;
  /// clients treat locked as the default until the flag round-trips.
  bool worldPredictionsUnlocked = false;

  void meterUpdate(double fraction) {
    final session = play;
    if (session == null || session.stage != PlayStage.predict) return;
    final raw = (fraction.clamp(0.0, 1.0) * 100).round();
    // Meter docks to the picked side: side A docks right (prototype).
    final pred = session.side == 'a' ? 100 - raw : raw;
    session.pred = pred.clamp(0, 100);
    final arm = session.pred <= 2;
    if (arm && !session.armSwitch) unawaited(HapticFeedback.selectionClick());
    session.armSwitch = arm;
    notifyListeners();
  }

  void meterRelease() {
    final session = play;
    if (session == null) return;
    if (session.armSwitch) flipSide();
  }

  void flipSide() {
    final session = play;
    if (session == null) return;
    unawaited(HapticFeedback.selectionClick());
    session.side = session.side == 'a' ? 'b' : 'a';
    session.pred = 50;
    session.armSwitch = false;
    notifyListeners();
  }

  void changeAnswer() {
    final session = play;
    if (session == null) return;
    session.stage = PlayStage.pick;
    session.side = null;
    session.pred = 50;
    session.dragX = 0;
    session.armSwitch = false;
    notifyListeners();
  }

  void setDuoPrediction(bool matched) {
    final session = play;
    if (session == null) return;
    session.pred = matched ? 100 : 0;
    notifyListeners();
  }

  // ── lock flow ─────────────────────────────────────────────────────────

  Future<void> lockCurrent({bool answerOnly = false}) async {
    final session = play;
    final card = session?.card;
    final question = card?.question;
    if (session == null || card == null || question == null) return;
    final side = session.side;
    if (side == null) return;
    unawaited(HapticFeedback.mediumImpact());

    final picks = session.results.putIfAbsent(card.roomId, () => []);
    picks.add(RoomPick(
      qid: question.qid,
      side: side,
      prediction: answerOnly ? null : session.pred,
    ));

    final blockDone = card.indexInRoom + 1 >= card.roomTotal;
    if (blockDone) {
      unawaited(_submitRoomPicks(card.roomId, List.of(picks)));
    }
    _advance(session);
  }

  /// Jump to another room block in the today deck (room-switch sheet).
  void jumpToDeckIndex(int index) {
    final session = play;
    if (session == null || index < 0 || index >= session.deck.length) return;
    session.idx = index;
    session.stage = PlayStage.pick;
    session.side = null;
    session.pred = 50;
    session.dragX = 0;
    session.armSwitch = false;
    notifyListeners();
  }

  void continueFromIntro() {
    final session = play;
    if (session == null || !(session.card?.intro ?? false)) return;
    _advance(session);
  }

  void _advance(PlaySession session) {
    session.idx += 1;
    session.stage = PlayStage.pick;
    session.side = null;
    session.pred = 50;
    session.dragX = 0;
    session.armSwitch = false;
    session.answerSavedReason = null;
    if (session.atEnd) {
      if (session.mode == 'room' && session.roomId != null) {
        summaryRoomId = session.roomId;
      }
      play = null;
    }
    notifyListeners();
  }

  Future<void> _submitRoomPicks(String roomId, List<RoomPick> picks) async {
    submitting = true;
    notifyListeners();
    try {
      await _callable('lockRoomAnswers').call({
        'roomId': roomId,
        'picks': [
          for (final pick in picks)
            {
              'qid': pick.qid,
              'side': pick.side,
              if (pick.prediction != null) 'prediction': pick.prediction,
            },
        ],
      });
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'already-exists') {
        lastError = error.message ?? error.code;
      }
    } catch (error) {
      lastError = error.toString();
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  // ── reveal ────────────────────────────────────────────────────────────

  Future<RoomRevealData?> loadRoomReveal(String roomId) async {
    final binding = bindingFor(roomId);
    final dailyKey = binding?.room?.lastClosedDailyKey;
    final currentUid = uid;
    if (dailyKey == null || currentUid == null) return null;
    try {
      final dayRef = _db
          .collection('rooms')
          .doc(roomId)
          .collection('days')
          .doc(dailyKey);
      final results = await Future.wait([
        dayRef.get(),
        dayRef.collection('answers').doc(currentUid).get(),
      ]);
      final dayData = results[0].data();
      if (dayData == null) return null;
      final answerData = results[1].data();
      return RoomRevealData(
        dailyKey: dailyKey,
        day: roomDayFromFirestore(dailyKey, dayData),
        myAnswer: answerData == null ? null : roomAnswerFromFirestore(answerData),
      );
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return null;
    }
  }

  /// Closed days for the room-history sheet (newest first).
  Future<List<RoomHistoryDay>> loadRoomHistory(String roomId, {int limitDays = 90}) async {
    final currentUid = uid;
    if (currentUid == null) return const [];
    try {
      final daysSnap = await _db
          .collection('rooms')
          .doc(roomId)
          .collection('days')
          .orderBy('dailyKey', descending: true)
          .limit(limitDays)
          .get();
      final closedDocs = daysSnap.docs
          .where((doc) => doc.data()['status'] == 'closed')
          .toList();
      final answers = await Future.wait([
        for (final doc in closedDocs)
          doc.reference.collection('answers').doc(currentUid).get(),
      ]);
      return [
        for (final (index, doc) in closedDocs.indexed)
          RoomHistoryDay(
            day: roomDayFromFirestore(doc.id, doc.data()),
            myAnswer: answers[index].data() == null
                ? null
                : roomAnswerFromFirestore(answers[index].data()!),
          ),
      ];
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return const [];
    }
  }

  /// Recent world questions beyond today's 3 (browse-only), with my answers.
  Future<List<RoomHistoryDay>> loadWorldBrowse({int limitDays = 5}) async {
    final currentUid = uid;
    if (currentUid == null) return const [];
    final todayKey = worldRoom?.currentDailyKey;
    try {
      final daysSnap = await _db
          .collection('rooms')
          .doc(worldRoomId)
          .collection('days')
          .orderBy('dailyKey', descending: true)
          .limit(limitDays + 1)
          .get();
      final docs = daysSnap.docs.where((doc) => doc.id != todayKey).toList();
      final answers = await Future.wait([
        for (final doc in docs)
          doc.reference.collection('answers').doc(currentUid).get(),
      ]);
      return [
        for (final (index, doc) in docs.indexed)
          RoomHistoryDay(
            day: roomDayFromFirestore(doc.id, doc.data()),
            myAnswer: answers[index].data() == null
                ? null
                : roomAnswerFromFirestore(answers[index].data()!),
          ),
      ];
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return const [];
    }
  }

  /// Reorder the not-yet-played room blocks of the today deck (prototype
  /// room-switch drag). Past and current blocks stay in place.
  void reorderTodayBlocks(List<String> movableRoomIdsInOrder) {
    final session = play;
    if (session == null || session.mode != 'today') return;
    final deck = session.deck;
    final blocks = <List<TodayDeckCard>>[];
    var i = 0;
    while (i < deck.length) {
      final roomId = deck[i].roomId;
      var j = i;
      while (j < deck.length && deck[j].roomId == roomId) {
        j++;
      }
      blocks.add(deck.sublist(i, j));
      i = j;
    }
    final currentBlockIndex = blocks.indexWhere((block) {
      final start = deck.indexOf(block.first);
      return session.idx >= start && session.idx < start + block.length;
    });
    if (currentBlockIndex < 0) return;
    final fixed = blocks.sublist(0, currentBlockIndex + 1);
    final movable = blocks.sublist(currentBlockIndex + 1);
    final byRoomId = {for (final block in movable) block.first.roomId: block};
    final reordered = [
      for (final roomId in movableRoomIdsInOrder)
        if (byRoomId.containsKey(roomId)) byRoomId[roomId]!,
    ];
    if (reordered.length != movable.length) return;
    final currentCard = session.card;
    session.deck
      ..clear()
      ..addAll([...fixed.expand((block) => block), ...reordered.expand((block) => block)]);
    if (currentCard != null) {
      session.idx = session.deck.indexOf(currentCard);
    }
    notifyListeners();
  }

  Future<void> markRevealSeen(String roomId) async {
    try {
      await _callable('markRoomRevealSeen').call({'roomId': roomId});
    } catch (_) {
      // Reveal-seen is cosmetic; never block on it.
    }
  }

  Future<List<RoomDayDetailRow>> loadDayDetail(
    String roomId,
    String dailyKey,
  ) async {
    try {
      final result = await _callable('getRoomDayDetail').call({
        'roomId': roomId,
        'dailyKey': dailyKey,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final rows = data['rows'] as List? ?? const [];
      return rows
          .whereType<Map>()
          .map((row) => roomDayDetailRowFromData(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return const [];
    }
  }

  // ── room management callables ─────────────────────────────────────────

  Future<String?> createRoom({
    required String name,
    required RoomTier tier,
    required String colorToken,
    required List<String> cats,
    required bool customEnabled,
    required bool revealAnswers,
  }) async {
    submitting = true;
    lastError = null;
    notifyListeners();
    try {
      final result = await _callable('createRoom').call({
        'name': name,
        'tier': tier.wire,
        'color': colorToken,
        'cats': cats,
        'customEnabled': customEnabled,
        'revealAnswers': revealAnswers,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['roomId']?.toString();
    } catch (error) {
      lastError = _callableMessage(error);
      return null;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<String?> joinRoom(String code) async {
    submitting = true;
    lastError = null;
    notifyListeners();
    try {
      final result = await _callable('joinRoom').call({'code': code.trim()});
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['roomId']?.toString();
    } catch (error) {
      lastError = _callableMessage(error);
      return null;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<bool> leaveRoom(String roomId) => _simpleCall('leaveRoom', {'roomId': roomId});

  Future<bool> deleteRoom(String roomId) => _simpleCall('deleteRoom', {'roomId': roomId});

  Future<bool> updateRoomSettings(
    String roomId, {
    String? name,
    RoomTier? tier,
    String? colorToken,
    List<String>? cats,
    bool? customEnabled,
  }) =>
      _simpleCall('updateRoomSettings', {
        'roomId': roomId,
        'name': ?name,
        'tier': ?tier?.wire,
        'color': ?colorToken,
        'cats': ?cats,
        'customEnabled': ?customEnabled,
      });

  Future<bool> setRoomQuestionEnabled(String roomId, String qid, bool enabled) =>
      _simpleCall('setRoomQuestionEnabled', {
        'roomId': roomId,
        'qid': qid,
        'enabled': enabled,
      });

  Future<bool> setAnswerVisibility(String roomId, bool revealMine) =>
      _simpleCall('setRoomAnswerVisibility', {
        'roomId': roomId,
        'revealMine': revealMine,
      });

  Future<bool> queueCustomQuestion(
    String roomId,
    String text,
    String optA,
    String optB,
  ) =>
      _simpleCall('queueCustomQuestion', {
        'roomId': roomId,
        'text': text,
        'optA': optA,
        'optB': optB,
      });

  Future<bool> deleteCustomQuestion(String roomId, String itemId) =>
      _simpleCall('deleteCustomQuestion', {'roomId': roomId, 'itemId': itemId});

  Future<bool> flagQuestion(String roomId, String qid) =>
      _simpleCall('flagRoomQuestion', {'roomId': roomId, 'qid': qid});

  Stream<List<QueueItem>> queueStream(String roomId) => _db
      .collection('rooms')
      .doc(roomId)
      .collection('queue')
      .orderBy('createdAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => queueItemFromFirestore(doc.id, doc.data()))
            .toList(),
      );

  Stream<List<RtwRoomMember>> membersStream(String roomId) => _db
      .collection('rooms')
      .doc(roomId)
      .collection('members')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => roomMemberFromFirestore(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.roomScore.compareTo(a.roomScore)),
      );

  Future<bool> _simpleCall(String name, Map<String, dynamic> payload) async {
    submitting = true;
    lastError = null;
    notifyListeners();
    try {
      await _callable(name).call(payload);
      return true;
    } catch (error) {
      lastError = _callableMessage(error);
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  String _callableMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? error.code;
    }
    return error.toString();
  }

  // ── party pool ────────────────────────────────────────────────────────

  List<PartyQuestion> _partyPool = [];
  final Set<String> _partyPlayed = {};

  List<PartyQuestion> get partyPool => _partyPool;

  Future<void> refreshPartyPool() async {
    try {
      final result = await _callable('getPartyPool').call({
        'count': 60,
        'excludeIds': _partyPlayed.take(500).toList(),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final questions = data['questions'] as List? ?? const [];
      _partyPool = questions
          .whereType<Map>()
          .map((raw) => partyQuestionFromData(Map<String, dynamic>.from(raw)))
          .where((question) => question.qid.isNotEmpty)
          .toList();
      notifyListeners();
    } catch (error) {
      // Offline: keep whatever pool we already have cached in memory.
      debugPrint('Party pool refresh failed: $error');
    }
  }

  void markPartyPlayed(Iterable<String> qids) {
    _partyPlayed.addAll(qids);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    _membershipsSub?.cancel();
    _clearRoomSubs();
    super.dispose();
  }
}
