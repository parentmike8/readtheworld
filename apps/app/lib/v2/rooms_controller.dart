import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mappers_v2.dart';
import 'models_v2.dart';
import 'tokens_v2.dart';

const worldRoomId = 'world';
const int _partyPlayedLimit = 500;

int? _timestampMillis(Object? value) {
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is num) return value.toInt();
  return null;
}

Set<String> _stringSet(Object? value) {
  if (value is! List) return {};
  return value
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toSet();
}

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
    this.dailyKey,
  });

  /// 'today' (cross-room deck with intro cards) or 'room' (single block).
  final String mode;
  final List<TodayDeckCard> deck;
  final String? roomId;

  /// World catch-up: the specific past day these picks lock into. Null means
  /// today (the server default).
  final String? dailyKey;

  int idx = 0;
  PlayStage stage = PlayStage.pick;
  String? side; // 'a' | 'b'
  int pred = 50;
  double dragX = 0;
  bool dragging = false;

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

  /// One-shot route to return to when a user exits room-mode play before
  /// finishing (the screen they entered play from).
  String? pendingPlayExitRoute;

  /// The route play was entered from, used to route [exitPlay] and the round
  /// summary's "Back" back there.
  String? _playEntryRoute;
  String? get playEntryRoute => _playEntryRoute;

  /// One-shot action for rooms home after the intro ('create' | 'join').
  String? pendingHomeAction;

  /// Picks from the just-finished intro session (consumed one-shot by the
  /// onboarding closer; the intro plays the real surface but locks at the
  /// end rather than per-block).
  List<RoomPick>? introPicks;

  String? lastError;
  bool submitting = false;
  bool loadingRooms = true;

  /// users/{uid} profile doc state — gates the first-run onboarding demo.
  bool profileLoaded = false;
  bool hasOnboarded = false;
  Set<String> likedQuestionIds = {};
  Set<String> dislikedQuestionIds = {};

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membershipsSub;
  final Map<String, List<StreamSubscription<dynamic>>> _roomSubs = {};
  final List<StreamSubscription<dynamic>> _worldSubs = [];
  String? _boundUid;
  bool _crossedCommitThreshold = false;
  bool _reviewPreviewActive = false;

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
      _partyPool = [];
      _partyPlayed.clear();
      partyPoolLoading = false;
      partyPoolLoadAttempted = false;
      partyPoolError = null;
      loadingRooms = true;
      profileLoaded = false;
      hasOnboarded = false;
      hasMatureConsent = false;
      notifPrimerSeen = false;
      notifyListeners();
      if (user == null) return;
      _bindProfile(user.uid);
      _bindMemberships(user.uid);
      _bindWorld(user.uid);
    });
  }

  void _bindProfile(String uid) {
    _profileSub = _db.collection('users').doc(uid).snapshots().listen((
      snapshot,
    ) {
      hasOnboarded = hasOnboarded || snapshot.data()?['onboardedAt'] != null;
      hasMatureConsent =
          hasMatureConsent || snapshot.data()?['matureContent'] == true;
      notifPrimerSeen =
          notifPrimerSeen || snapshot.data()?['notifPrimerSeenAt'] != null;
      likedQuestionIds = _stringSet(snapshot.data()?['likedQuestionIds']);
      dislikedQuestionIds = _stringSet(snapshot.data()?['dislikedQuestionIds']);
      profileLoaded = true;
      notifyListeners();
    }, onError: _handleError);
  }

  /// Whether the one-time "turn on notifications" primer should show: a
  /// signed-in reader who has finished onboarding and hasn't seen it yet.
  bool notifPrimerSeen = false;

  bool get needsNotifPrimer =>
      firebaseReady &&
      profileLoaded &&
      !loadingRooms &&
      hasOnboarded &&
      !notifPrimerSeen;

  /// Stamp the profile so the notifications primer never shows again.
  void markNotifPrimerSeen() {
    if (notifPrimerSeen) return;
    notifPrimerSeen = true;
    notifyListeners();
    if (!firebaseReady) return;
    final currentUid = uid;
    if (currentUid == null) return;
    unawaited(
      _db
          .collection('users')
          .doc(currentUid)
          .set({
            'notifPrimerSeenAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .catchError((Object error) {
            _handleError(error);
          }),
    );
  }

  /// Whether this user has ever accepted the After Dark consent sheet
  /// (joining a mature room or switching party mode to After Dark).
  /// getPartyPool withholds mature questions until this is stamped.
  bool hasMatureConsent = false;

  Future<void> markMatureConsent() async {
    if (hasMatureConsent) return;
    hasMatureConsent = true;
    notifyListeners();
    if (!firebaseReady) return;
    final currentUid = uid;
    if (currentUid == null) return;
    try {
      await _db.collection('users').doc(currentUid).set({
        'matureContent': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      _handleError(error);
    }
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
      _db
          .collection('users')
          .doc(currentUid)
          .set({
            'onboardedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .catchError((Object error) {
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
          // The World is bound once by _bindWorld; a memberships/world doc
          // must neither double-bind it nor unbind it here.
          for (final roomId in bindings.keys.toList()) {
            if (roomId == worldRoomId) continue;
            if (!current.contains(roomId)) _unbindRoom(roomId);
          }
          for (final doc in snapshot.docs) {
            if (doc.id == worldRoomId) continue;
            if (!bindings.containsKey(doc.id)) _bindRoom(doc.id, uid);
          }
          final joinedAtByRoom = {
            for (final doc in snapshot.docs)
              doc.id: _timestampMillis(doc.data()['joinedAt']),
          };
          roomOrder = snapshot.docs.map((doc) => doc.id).toList()
            ..sort((a, b) {
              final aJoined = joinedAtByRoom[a] ?? 0;
              final bJoined = joinedAtByRoom[b] ?? 0;
              if (aJoined != bJoined) return aJoined.compareTo(bJoined);
              return a.compareTo(b);
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

    subs.add(
      roomDoc.snapshots().listen((snapshot) {
        final data = snapshot.data();
        if (data == null) return;
        final previousKey = binding.room?.currentDailyKey;
        binding.room = roomFromFirestore(snapshot.id, data);
        final nextKey = binding.room!.currentDailyKey;
        if (nextKey != null && nextKey != previousKey) {
          _bindRoomDay(roomId, uid, nextKey, subs, binding);
        }
        notifyListeners();
      }, onError: _handleError),
    );

    subs.add(
      roomDoc.collection('members').doc(uid).snapshots().listen((snapshot) {
        final data = snapshot.data();
        if (data == null) return;
        binding.me = roomMemberFromFirestore(uid, data);
        notifyListeners();
      }, onError: _handleError),
    );
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
    subs.add(
      dayRef.snapshots().listen((snapshot) {
        final data = snapshot.data();
        binding.today = data == null
            ? null
            : roomDayFromFirestore(snapshot.id, data);
        notifyListeners();
      }, onError: _handleError),
    );
    subs.add(
      dayRef.collection('answers').doc(uid).snapshots().listen((snapshot) {
        final data = snapshot.data();
        binding.myTodayAnswer = data == null
            ? null
            : roomAnswerFromFirestore(data);
        notifyListeners();
      }, onError: _handleError),
    );
  }

  void _bindWorld(String uid) {
    final worldDoc = _db.collection('rooms').doc(worldRoomId);
    _worldSubs.add(
      worldDoc.snapshots().listen((snapshot) {
        final data = snapshot.data();
        if (data == null) return;
        final previousKey = worldRoom?.currentDailyKey;
        worldRoom = roomFromFirestore(snapshot.id, data);
        final binding = bindings.putIfAbsent(worldRoomId, () => RoomBinding());
        binding.room = worldRoom;
        final nextKey = worldRoom!.currentDailyKey;
        if (nextKey != null && nextKey != previousKey) {
          while (_worldSubs.length > 1) {
            _worldSubs.removeLast().cancel();
          }
          worldToday = null;
          binding.today = null;
          binding.myTodayAnswer = null;
          _worldSubs.add(
            worldDoc.collection('days').doc(nextKey).snapshots().listen((
              daySnap,
            ) {
              final dayData = daySnap.data();
              worldToday = dayData == null
                  ? null
                  : roomDayFromFirestore(daySnap.id, dayData);
              binding.today = worldToday;
              notifyListeners();
            }, onError: _handleError),
          );
          _worldSubs.add(
            worldDoc
                .collection('days')
                .doc(nextKey)
                .collection('answers')
                .doc(uid)
                .snapshots()
                .listen((answerSnap) {
                  final answerData = answerSnap.data();
                  binding.myTodayAnswer = answerData == null
                      ? null
                      : roomAnswerFromFirestore(answerData);
                  notifyListeners();
                }, onError: _handleError),
          );
        }
        notifyListeners();
      }, onError: _handleError),
    );
  }

  void _unbindRoom(String roomId) {
    for (final sub
        in _roomSubs.remove(roomId) ?? const <StreamSubscription<dynamic>>[]) {
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
            !binding.played &&
            (binding.today?.activeQuestions.isNotEmpty ?? false),
      )
      .toList();

  int get caughtUpCount {
    final roomCount = visibleRooms.where((binding) => binding.played).length;
    final worldCount = (_worldBinding?.played ?? false) ? 1 : 0;
    return roomCount + worldCount;
  }

  RoomBinding? bindingFor(String? roomId) => roomId == null
      ? null
      : (roomId == worldRoomId ? _worldBinding : bindings[roomId]);

  RoomBinding? get _worldBinding {
    if (worldRoom == null) return null;
    final binding = bindings.putIfAbsent(worldRoomId, () => RoomBinding());
    binding.room = worldRoom;
    if (worldToday != null) binding.today = worldToday;
    return binding;
  }

  // ── deck building (mirrors prototype buildTodayDeck) ──────────────────

  List<TodayDeckCard> buildTodayDeck() {
    final deck = <TodayDeckCard>[];
    void addRoomBlock(RtwRoom room, RoomDay day) {
      // Exclude World questions that already revealed (they can't be answered).
      final questions = day.answerableQuestions;
      if (questions.isEmpty) return;
      deck.add(
        TodayDeckCard.intro(
          roomId: room.id,
          roomName: room.name,
          roomColorToken: room.colorToken,
          roomMembers: room.memberCount,
          roomTotal: questions.length,
          isWorld: room.isWorld,
        ),
      );
      for (var i = 0; i < questions.length; i++) {
        deck.add(
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
        );
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

  bool enterToday() {
    final deck = buildTodayDeck();
    if (deck.isEmpty) {
      if (play == null) return false;
      play = null;
      notifyListeners();
      return false;
    }
    play = PlaySession(mode: 'today', deck: deck);
    notifyListeners();
    return true;
  }

  void startRoomPlay(String roomId, {String? entryRoute}) {
    final binding = bindingFor(roomId);
    final room = binding?.room;
    final day = roomId == worldRoomId ? worldToday : binding?.today;
    if (room == null || day == null) return;
    _playEntryRoute = entryRoute;
    _startDayPlay(room, day, binding?.myTodayAnswer);
  }

  /// Review-only play-card preview for exercising custom-question attribution,
  /// reporting, and creator blocking without changing the live room day.
  void startQueuedQuestionQaPreview(String roomId, QueueItem item) {
    final room = bindingFor(roomId)?.room;
    if (room == null) return;
    _reviewPreviewActive = true;
    _playEntryRoute = '/rooms/$roomId';
    play = PlaySession(
      mode: 'qa',
      roomId: roomId,
      dailyKey: room.currentDailyKey,
      deck: [
        TodayDeckCard.question(
          roomId: roomId,
          roomName: room.name,
          roomColorToken: room.colorToken,
          roomMembers: math.max(2, room.memberCount),
          roomTotal: 1,
          isWorld: false,
          question: RoomDayQuestion(
            qid: 'qa-preview-${item.id}',
            prompt: item.text,
            optA: item.optA,
            optB: item.optB,
            tag: 'Review preview',
            shape: 'CUSTOM',
            custom: true,
            authorUid: 'qa-preview-member',
            authorName: 'QA Guest',
          ),
          indexInRoom: 0,
        ),
      ],
    );
    notifyListeners();
  }

  /// The World lets readers answer a past, not-yet-revealed day (instant lock,
  /// no 24h gap). Locks against that day's key.
  void startWorldDayPlay(RoomHistoryDay history, {String? entryRoute}) {
    final room = worldRoom;
    if (room == null) return;
    _playEntryRoute = entryRoute;
    _startDayPlay(room, history.day, history.myAnswer);
  }

  void _startDayPlay(RtwRoom room, RoomDay day, RoomAnswer? answer) {
    // Revealed World questions are locked out; only offer the still-open ones.
    final questions = day.answerableQuestions;
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
    final session = PlaySession(
      mode: 'room',
      deck: deck,
      roomId: room.id,
      dailyKey: day.dailyKey,
    );
    if (day.isLive && answer != null) {
      final qids = questions.map((question) => question.qid).toSet();
      session.results[room.id] = [
        for (final pick in answer.picks)
          if (qids.contains(pick.qid)) pick,
      ];
      _restoreCurrentSavedPick(session);
    }
    play = session;
    notifyListeners();
  }

  /// Exit mid-round: return to wherever this play session was entered from
  /// (e.g. the review page), falling back to the room detail.
  void exitPlay() {
    final session = play;
    if (session != null && session.mode != 'intro') {
      final roomId = session.roomId;
      pendingPlayExitRoute =
          _playEntryRoute ??
          (roomId != null && roomId.isNotEmpty ? '/rooms/$roomId' : '/rooms');
    } else {
      pendingPlayExitRoute = null;
    }
    _playEntryRoute = null;
    play = null;
    notifyListeners();
  }

  void clearPendingPlayExit() {
    pendingPlayExitRoute = null;
  }

  /// Clear a room's "NEW" badge once the reader has opened it (detail or play).
  void markTodaySeen(String roomId) {
    final binding = bindingFor(roomId);
    if (binding == null || binding.todaySeen) return;
    binding.todaySeen = true;
    notifyListeners();
  }

  QuestionReaction? reactionForQuestion(String qid) {
    if (likedQuestionIds.contains(qid)) return QuestionReaction.liked;
    if (dislikedQuestionIds.contains(qid)) return QuestionReaction.disliked;
    return null;
  }

  Future<void> toggleQuestionReaction(
    String qid,
    QuestionReaction reaction,
  ) async {
    if (qid.isEmpty) return;
    final beforeLiked = {...likedQuestionIds};
    final beforeDisliked = {...dislikedQuestionIds};
    final nextReaction = reactionForQuestion(qid) == reaction ? null : reaction;
    _applyLocalQuestionReaction(qid, nextReaction);
    notifyListeners();
    if (!firebaseReady) return;
    try {
      await _callable('setQuestionReaction').call({
        'qid': qid,
        'reaction': nextReaction == null
            ? null
            : switch (nextReaction) {
                QuestionReaction.liked => 'liked',
                QuestionReaction.disliked => 'disliked',
              },
      });
    } catch (error) {
      likedQuestionIds = beforeLiked;
      dislikedQuestionIds = beforeDisliked;
      lastError = _callableMessage(error);
      notifyListeners();
    }
  }

  void _applyLocalQuestionReaction(String qid, QuestionReaction? reaction) {
    likedQuestionIds = {...likedQuestionIds}..remove(qid);
    dislikedQuestionIds = {...dislikedQuestionIds}..remove(qid);
    switch (reaction) {
      case QuestionReaction.liked:
        likedQuestionIds = {...likedQuestionIds}..add(qid);
      case QuestionReaction.disliked:
        dislikedQuestionIds = {...dislikedQuestionIds}..add(qid);
      case null:
        break;
    }
  }

  /// First-run intro: fixed tutorial questions on the real play surface with
  /// the real swipe and prediction meter. The session stays practice-only;
  /// neither answers nor predictions are submitted or persisted.
  void startIntroSession(List<RoomDayQuestion> questions) {
    introPicks = null;
    play = PlaySession(
      mode: 'intro',
      roomId: 'intro',
      deck: [
        for (var i = 0; i < questions.length; i++)
          TodayDeckCard.question(
            roomId: 'intro',
            roomName: 'How it works',
            roomColorToken: 'oklch(0.50 0.10 256)',
            // The tutorial predicts the share of all people, not a fictional
            // room headcount. Intro mode still runs the full pick → predict
            // loop, but its meter is continuous like The World.
            roomMembers: 0,
            roomTotal: questions.length,
            isWorld: false,
            question: questions[i],
            indexInRoom: i,
          ),
      ],
    );
    notifyListeners();
  }

  /// One-shot read of the finished intro's picks.
  List<RoomPick>? takeIntroPicks() {
    final picks = introPicks;
    introPicks = null;
    return picks;
  }

  /// Keyboard nudge for the prediction meter (web-native controls).
  void nudgePred(int delta) {
    final session = play;
    if (session == null || session.stage != PlayStage.predict) return;
    final people = _predictionPeople(session);
    if (!_predictionInfinite(session) &&
        people <= _countFirstPredictionThreshold) {
      final current = ((session.pred / 100) * people).round();
      final rawNext = current + delta;
      final next = rawNext < 0
          ? 0
          : rawNext > people
          ? people
          : rawNext;
      session.pred = ((next / people) * 100).round();
    } else {
      session.pred = _boundedPrediction(session.pred + delta);
    }
    notifyListeners();
  }

  void dismissSummary({bool notify = true}) {
    summaryRoomId = null;
    if (notify) notifyListeners();
  }

  /// Leave the round summary and route to [route] via the single play-exit
  /// path (avoids the summary-back navigation racing the exit redirect, which
  /// was bouncing "Back to [Room]" to /rooms).
  void dismissSummaryTo(String route) {
    summaryRoomId = null;
    pendingPlayExitRoute = route;
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
    session.dragX = (session.dragX + deltaX).clamp(
      -RtwV2Motion.dragClamp,
      RtwV2Motion.dragClamp,
    );
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
    final fastFling =
        velocityX.abs() > flingVelocity &&
        dx.sign == velocityX.sign &&
        dx.abs() > 12;
    if (dx > RtwV2Motion.commitThreshold || (fastFling && velocityX > 0)) {
      commitSide('a');
    } else if (dx < -RtwV2Motion.commitThreshold ||
        (fastFling && velocityX < 0)) {
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
    session.dragX = side == 'a'
        ? RtwV2Motion.flingDistance
        : -RtwV2Motion.flingDistance;
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
    // Every room now takes a prediction, The World included: the reader guesses
    // what share of people would agree. World scoring simply waits until the
    // question crosses its threshold [Mike].
    session.stage = PlayStage.predict;
    session.side = side;
    // Duo rooms start at "the other person matched" (prototype: pred=100);
    // solo / world predict a free share of everyone (infinite meter).
    final defaultPred = (binding?.room?.isDuo ?? false) ? 100 : 50;
    session.pred = _snapPredictionForSession(session, defaultPred);
    session.dragX = 0;
    notifyListeners();
  }

  static const int _countFirstPredictionThreshold = 25;

  int _predictionPeople(PlaySession session) {
    final members = session.card?.roomMembers ?? 0;
    return math.max(0, members - 1);
  }

  /// Intro, Solo and The World read the prediction as a free share of everyone,
  /// so the meter must NOT snap to a current (or fictional) member count.
  bool _predictionInfinite(PlaySession session) =>
      session.mode == 'intro' ||
      (session.card?.isWorld ?? false) ||
      _predictionPeople(session) <= 0;

  int _boundedPrediction(int value) => value < 0
      ? 0
      : value > 100
      ? 100
      : value;

  int _snapPredictionForSession(PlaySession session, int value) {
    final bounded = _boundedPrediction(value);
    final people = _predictionPeople(session);
    if (_predictionInfinite(session) ||
        people > _countFirstPredictionThreshold) {
      return bounded;
    }
    final rawCount = ((bounded / 100) * people).round();
    final count = rawCount < 0
        ? 0
        : rawCount > people
        ? people
        : rawCount;
    return _boundedPrediction(((count / people) * 100).round());
  }

  int _snapPredictionFractionForSession(PlaySession session, double fraction) {
    final boundedFraction = fraction.clamp(0.0, 1.0);
    final people = _predictionPeople(session);
    if (_predictionInfinite(session) ||
        people > _countFirstPredictionThreshold) {
      return _boundedPrediction((boundedFraction * 100).round());
    }
    final count = (boundedFraction * people).round().clamp(0, people);
    return _boundedPrediction(((count / people) * 100).round());
  }

  /// Whether The World allows predictions (flipped from the admin panel).
  /// Mirrored from whether today's world answers carry predictions server-side;
  /// clients treat locked as the default until the flag round-trips.
  bool worldPredictionsUnlocked = false;

  void meterUpdate(double fraction) {
    final session = play;
    if (session == null || session.stage != PlayStage.predict) return;
    final previousPred = session.pred;
    session.pred = _snapPredictionFractionForSession(session, fraction);
    if (session.pred != previousPred) {
      unawaited(HapticFeedback.selectionClick());
    }
    notifyListeners();
  }

  void changeAnswer() {
    final session = play;
    if (session == null) return;
    session.stage = PlayStage.pick;
    session.side = null;
    session.pred = 50;
    session.dragX = 0;
    notifyListeners();
  }

  /// Whether there's an earlier question in the *current room block* to step
  /// back to (never crosses an intro card or into another room's block).
  bool get canGoBack {
    final session = play;
    final card = session?.card;
    if (session == null || card == null) return false;
    final prev = session.idx - 1;
    return prev >= 0 &&
        !session.deck[prev].intro &&
        session.deck[prev].roomId == card.roomId;
  }

  /// Step back to the previous question to revise it — it's fine to change an
  /// answer before the round locks (party-mode style). Restores the saved pick
  /// on the editable predict step, or a clean pick if none.
  void goBack() {
    final session = play;
    if (session == null || !canGoBack) return;
    unawaited(HapticFeedback.selectionClick());
    session.idx -= 1;
    session.dragX = 0;
    session.dragging = false;
    final card = session.card;
    final qid = card?.question?.qid;
    RoomPick? saved;
    for (final pick in session.results[card?.roomId] ?? const <RoomPick>[]) {
      if (pick.qid == qid) {
        saved = pick;
        break;
      }
    }
    if (saved != null) {
      session.side = saved.side;
      session.pred = _snapPredictionForSession(session, saved.prediction ?? 50);
      session.stage = PlayStage.predict;
    } else {
      session.side = null;
      session.pred = 50;
      session.stage = PlayStage.pick;
    }
    notifyListeners();
  }

  RoomPick? _savedPickForCurrent(PlaySession session) {
    if (session.mode != 'room') return null;
    final card = session.card;
    final qid = card?.question?.qid;
    if (card == null || qid == null) return null;
    for (final pick in session.results[card.roomId] ?? const <RoomPick>[]) {
      if (pick.qid == qid) return pick;
    }
    return null;
  }

  void _restoreCurrentSavedPick(PlaySession session) {
    final card = session.card;
    final pick = _savedPickForCurrent(session);
    if (card == null || pick == null) return;
    session.side = pick.side;
    session.pred = _snapPredictionForSession(session, pick.prediction ?? 50);
    session.dragX = 0;
    session.dragging = false;
    // Every room predicts now, so reopening a saved answer lands on the
    // editable prediction step — even a legacy answer-only pick gets a default
    // to adjust, rather than the old "saved" dead-end screen.
    session.stage = PlayStage.predict;
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
    if (submitting) return;
    final side = session.side;
    if (side == null) return;
    unawaited(HapticFeedback.mediumImpact());
    lastError = null;

    final picks = session.results.putIfAbsent(card.roomId, () => []);
    final pick = RoomPick(
      qid: question.qid,
      side: side,
      prediction: answerOnly ? null : session.pred,
    );
    final existing = picks.indexWhere((item) => item.qid == question.qid);
    if (existing >= 0) {
      picks[existing] = pick;
    } else {
      picks.add(pick);
    }

    final blockDone = card.indexInRoom + 1 >= card.roomTotal;
    if (blockDone && session.mode == 'intro') {
      introPicks = List.of(picks);
    } else if (blockDone) {
      final submitted = await _submitRoomPicks(
        card.roomId,
        List.of(picks),
        dailyKey: session.dailyKey,
      );
      if (!submitted) return;
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
    _restoreCurrentSavedPick(session);
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
    if (session.atEnd) {
      if (session.mode == 'room' && session.roomId != null) {
        summaryRoomId = session.roomId;
      }
      play = null;
    } else {
      _restoreCurrentSavedPick(session);
    }
    notifyListeners();
  }

  Future<bool> _submitRoomPicks(
    String roomId,
    List<RoomPick> picks, {
    String? dailyKey,
  }) async {
    submitting = true;
    notifyListeners();
    try {
      final payload = <String, dynamic>{
        'roomId': roomId,
        'picks': [
          for (final pick in picks)
            {
              'qid': pick.qid,
              'side': pick.side,
              if (pick.prediction != null) ...{
                'prediction': pick.prediction,
                'predictedShare': pick.prediction,
              },
            },
        ],
      };
      if (dailyKey != null) payload['dailyKey'] = dailyKey;
      await _callable('lockRoomAnswers').call(payload);
      _hydrateSubmittedRoomAnswer(roomId, picks, dailyKey: dailyKey);
      return true;
    } on FirebaseFunctionsException catch (error) {
      lastError = error.message ?? error.code;
      return false;
    } catch (error) {
      lastError = error.toString();
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  void _hydrateSubmittedRoomAnswer(
    String roomId,
    List<RoomPick> picks, {
    String? dailyKey,
  }) {
    if (picks.isEmpty) return;
    final binding = bindingFor(roomId);
    final submittedAnswer = RoomAnswer(
      picks: List<RoomPick>.unmodifiable(picks),
      answerOnly: picks.every((pick) => pick.prediction == null),
    );
    if (binding != null &&
        (dailyKey == null || binding.today?.dailyKey == dailyKey)) {
      binding.myTodayAnswer = submittedAnswer;
    }
    if (roomId == worldRoomId &&
        (dailyKey == null || worldToday?.dailyKey == dailyKey)) {
      final worldBinding = bindings.putIfAbsent(
        worldRoomId,
        () => RoomBinding(),
      );
      worldBinding.myTodayAnswer = submittedAnswer;
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
        myAnswer: answerData == null
            ? null
            : roomAnswerFromFirestore(answerData),
      );
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return null;
    }
  }

  /// Closed days for the room-history sheet (newest first).
  Future<List<RoomHistoryDay>> loadRoomHistory(
    String roomId, {
    int limitDays = 90,
    bool includeLive = false,
  }) async {
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
      // The World never "closes" its days (questions reveal per-threshold), so
      // its history includes live/open days the reader can still answer.
      final closedDocs = includeLive
          ? daysSnap.docs.toList()
          : daysSnap.docs
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
      ..addAll([
        ...fixed.expand((block) => block),
        ...reordered.expand((block) => block),
      ]);
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
      final result = await _callable(
        'getRoomDayDetail',
      ).call({'roomId': roomId, 'dailyKey': dailyKey});
      final data = Map<String, dynamic>.from(result.data as Map);
      final rows = data['rows'] as List? ?? const [];
      return rows
          .whereType<Map>()
          .map(
            (row) => roomDayDetailRowFromData(Map<String, dynamic>.from(row)),
          )
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

  Future<bool> leaveRoom(String roomId) =>
      _simpleCall('leaveRoom', {'roomId': roomId});

  Future<bool> deleteRoom(String roomId) =>
      _simpleCall('deleteRoom', {'roomId': roomId});

  Future<bool> updateRoomSettings(
    String roomId, {
    String? name,
    RoomTier? tier,
    String? colorToken,
    List<String>? cats,
    bool? customEnabled,
  }) => _simpleCall('updateRoomSettings', {
    'roomId': roomId,
    'name': ?name,
    'tier': ?tier?.wire,
    'color': ?colorToken,
    'cats': ?cats,
    'customEnabled': ?customEnabled,
  });

  Future<bool> setRoomQuestionEnabled(
    String roomId,
    String qid,
    bool enabled,
  ) => _simpleCall('setRoomQuestionEnabled', {
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
    String optB, {
    required bool acceptedCommunityStandards,
  }) => _simpleCall('queueCustomQuestion', {
    'roomId': roomId,
    'text': text,
    'optA': optA,
    'optB': optB,
    'acceptedCommunityStandards': acceptedCommunityStandards,
  });

  Future<bool> deleteCustomQuestion(String roomId, String itemId) =>
      _simpleCall('deleteCustomQuestion', {'roomId': roomId, 'itemId': itemId});

  Future<bool> flagQuestion(
    String roomId,
    String qid, {
    required String reason,
    bool blockAuthor = false,
  }) async {
    if (_reviewPreviewActive && qid.startsWith('qa-preview-')) {
      _reviewPreviewActive = false;
      play = null;
      pendingPlayExitRoute = '/rooms/$roomId';
      notifyListeners();
      return true;
    }
    return _simpleCall('flagRoomQuestion', {
      'roomId': roomId,
      'qid': qid,
      'reason': reason,
      'blockAuthor': blockAuthor,
    });
  }

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
        (snapshot) =>
            snapshot.docs
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
  final ListQueue<String> _partyPlayedOrder = ListQueue<String>();
  final Set<String> _partyPlayed = {};
  bool partyPoolLoading = false;
  bool partyPoolLoadAttempted = false;
  String? partyPoolError;

  List<PartyQuestion> get partyPool => _partyPool
      .where((question) => !dislikedQuestionIds.contains(question.qid))
      .where((question) => !_partyPlayed.contains(question.qid))
      .toList();

  /// Fetch a fresh pool, optionally scoped to a spice level server-side so
  /// e.g. After Dark gets a full deck instead of a diluted random sample.
  Future<void> refreshPartyPool({RoomTier? tier}) async {
    partyPoolLoading = true;
    partyPoolError = null;
    notifyListeners();
    try {
      final result = await _callable('getPartyPool').call({
        'count': 60,
        'excludeIds': _partyPlayedOrder.toList(),
        if (tier != null) 'tier': tier.wire,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final questions = data['questions'] as List? ?? const [];
      _partyPool = questions
          .whereType<Map>()
          .map((raw) => partyQuestionFromData(Map<String, dynamic>.from(raw)))
          .where((question) => question.qid.isNotEmpty)
          .toList();
    } catch (error) {
      // Offline: keep whatever pool we already have cached in memory.
      partyPoolError = _callableMessage(error);
      debugPrint('Party pool refresh failed: $error');
    } finally {
      partyPoolLoadAttempted = true;
      partyPoolLoading = false;
      notifyListeners();
    }
  }

  void markPartyPlayed(Iterable<String> qids) {
    for (final qid in qids) {
      if (qid.isEmpty) continue;
      if (_partyPlayed.remove(qid)) {
        _partyPlayedOrder.remove(qid);
      }
      _partyPlayed.add(qid);
      _partyPlayedOrder.add(qid);
    }
    while (_partyPlayedOrder.length > _partyPlayedLimit) {
      _partyPlayed.remove(_partyPlayedOrder.removeFirst());
    }
  }

  @visibleForTesting
  void replacePartyPoolForTesting(List<PartyQuestion> questions) {
    _partyPool = List.of(questions);
  }

  /// The World leaderboard: everyone you share a (non-World) room with, ranked
  /// by their World Read Score. Empty until the first World questions reveal.
  Future<List<WorldLeaderRow>> loadWorldLeaderboard() async {
    if (!firebaseReady) return const [];
    try {
      final result = await _callable('getWorldLeaderboard').call({});
      final data = Map<String, dynamic>.from(result.data as Map);
      return (data['rows'] as List? ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map(
            (row) => WorldLeaderRow(
              rank: (row['rank'] as num?)?.toInt() ?? 0,
              uid: row['uid']?.toString() ?? '',
              displayName: row['displayName']?.toString() ?? 'Reader',
              avatarColor: row['avatarColor']?.toString() ?? 'blue',
              readScore: (row['readScore'] as num?)?.toInt() ?? 1500,
              questionsScored:
                  (row['officialQuestionsAnswered'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    } catch (error) {
      // Rethrow so the screen can show a real error state (an empty board
      // here would read as "no peers yet", which is a different truth). The
      // FutureBuilder owns presentation — do NOT set lastError here, or the
      // play surface's submit-error slot would paint a stale leaderboard
      // failure next to the Submit button.
      rethrow;
    }
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
