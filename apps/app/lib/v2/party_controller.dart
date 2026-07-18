import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/services.dart';

import 'models_v2.dart';
import 'tokens_v2.dart';

final partyControllerProvider = ChangeNotifierProvider<PartyController>((ref) {
  return PartyController();
});

/// Pass-the-phone party state machine — a faithful port of the prototype's
/// party handlers. Entirely session-local: scores never touch the profile.
///
/// Per question: the reader (rotating by question index) swipes their answer
/// and predicts the room; every other player just swipes a vote. The reveal
/// tallies the table and scores the reader's read.
enum PartyStage { setup, play, done }

enum PartySub { pick, predict, pass, revealPass, reveal }

class PartyTurnPick {
  const PartyTurnPick({required this.side, this.prediction});

  final String side; // 'a' | 'b'
  final int? prediction;
}

/// Full play-state snapshot for undo; taken before every committing move.
class _PartySnapshot {
  _PartySnapshot({
    required this.idx,
    required this.turn,
    required this.sub,
    required this.side,
    required this.pred,
    required this.turnPicks,
    required this.scores,
  });

  final int idx;
  final int turn;
  final PartySub sub;
  final String? side;
  final int pred;
  final List<PartyTurnPick> turnPicks;
  final List<double> scores;
}

class PartyController extends ChangeNotifier {
  static const int maxSwaps = 3;

  PartyStage stage = PartyStage.setup;
  int players = 4;
  int rounds = 3;
  Set<String> topics = {'All'};
  RoomTier tier = RoomTier.normal;

  List<String> playerNames = List.generate(4, (index) => 'Player ${index + 1}');
  List<PartyQuestion> deck = [];
  List<PartyQuestion> _gamePool = [];
  int idx = 0;
  int turn = 0;
  PartySub sub = PartySub.pick;
  String? side;
  int pred = 50;
  int swapsUsed = 0;
  int swapPulse = 0;
  double dragX = 0;
  bool dragging = false;
  List<PartyTurnPick> turnPicks = [];
  List<double> scores = [];
  double revealT = 0;
  Timer? _revealTimer;
  Timer? _flingTimer;
  bool _crossedCommit = false;
  final List<_PartySnapshot> _undoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;

  bool get solo => players < 2;
  int get readerIndex => players > 0 ? idx % players : 0;
  int get currentPlayerIndex {
    if (players <= 0) return 0;
    if (sub == PartySub.revealPass) return readerIndex;
    return (readerIndex + turn) % players;
  }

  PartyQuestion? get card => idx >= 0 && idx < deck.length ? deck[idx] : null;
  int get swapsLeft => math.max(0, maxSwaps - swapsUsed);
  bool get swapControlVisible =>
      stage == PartyStage.play &&
      turn == 0 &&
      (sub == PartySub.pick || sub == PartySub.predict);
  bool get canSwapQuestion =>
      swapControlVisible && swapsLeft > 0 && _swapCandidates().isNotEmpty;
  String get currentPlayerName => playerName(currentPlayerIndex);
  String get readerName => playerName(readerIndex);

  void setPlayers(int value) {
    players = value.clamp(1, 20);
    _syncPlayerNames();
    notifyListeners();
  }

  void _syncPlayerNames() {
    if (playerNames.length < players) {
      playerNames = [
        ...playerNames,
        for (var index = playerNames.length; index < players; index++)
          'Player ${index + 1}',
      ];
    } else if (playerNames.length > players) {
      playerNames = playerNames.take(players).toList();
    }
  }

  String playerName(int index) {
    if (index < 0 || index >= playerNames.length) return 'Player ${index + 1}';
    final value = playerNames[index].trim();
    return value.isEmpty ? 'Player ${index + 1}' : value;
  }

  void setPlayerName(int index, String value) {
    if (index < 0 || index >= players) return;
    _syncPlayerNames();
    playerNames[index] = value;
    notifyListeners();
  }

  void setRounds(int value) {
    rounds = value.clamp(1, 5);
    notifyListeners();
  }

  /// Same semantics as the room category chips: 'All' is exclusive, tapping
  /// a tag drops it, and clearing the last tag falls back to 'All'.
  void toggleTopic(String value) {
    if (value == 'All') {
      topics = {'All'};
    } else {
      final next = {...topics}..remove('All');
      if (!next.add(value)) next.remove(value);
      topics = next.isEmpty ? {'All'} : next;
    }
    notifyListeners();
  }

  void setTier(RoomTier value) {
    if (tier != value) topics = {'All'};
    tier = value;
    notifyListeners();
  }

  /// The playable slice of the fetched pool: spice level first (server
  /// pre-filters too, but cached pools may span tiers), then topics.
  List<PartyQuestion> poolFor(List<PartyQuestion> pool) => pool
      .where((question) => tier.allowsQuestionTier(question.tier))
      .where(
        (question) => topics.contains('All') || topics.contains(question.tag),
      )
      .toList();

  void start(List<PartyQuestion> pool) {
    final filtered = poolFor(pool);
    if (filtered.isEmpty) return;
    _syncPlayerNames();
    _gamePool = filtered;
    deck = _buildDeck(_gamePool);
    _resetPlayState();
    notifyListeners();
  }

  List<PartyQuestion> _buildDeck(
    List<PartyQuestion> source, {
    Set<String> avoidQids = const {},
  }) {
    final random = math.Random();
    final fresh =
        source.where((question) => !avoidQids.contains(question.qid)).toList()
          ..shuffle(random);
    final fallback =
        source.where((question) => avoidQids.contains(question.qid)).toList()
          ..shuffle(random);
    final shuffled = [...fresh, ...fallback];
    final total = rounds * players;
    return [for (var i = 0; i < total; i++) shuffled[i % shuffled.length]];
  }

  void _resetPlayState() {
    _undoStack.clear();
    scores = List.filled(players, 0);
    idx = 0;
    turn = 0;
    sub = PartySub.pick;
    side = null;
    pred = 50;
    swapsUsed = 0;
    swapPulse = 0;
    dragX = 0;
    dragging = false;
    turnPicks = [];
    revealT = 0;
    stage = PartyStage.play;
  }

  void again() {
    stage = PartyStage.setup;
    deck = [];
    idx = 0;
    turn = 0;
    swapsUsed = 0;
    turnPicks = [];
    _undoStack.clear();
    notifyListeners();
  }

  void restartGame() {
    if (_gamePool.isEmpty) return;
    final previousQids = deck.map((question) => question.qid).toSet();
    deck = _buildDeck(_gamePool, avoidQids: previousQids);
    _resetPlayState();
    notifyListeners();
  }

  List<PartyQuestion> _swapCandidates() {
    final currentQid = card?.qid;
    if (currentQid == null || _gamePool.isEmpty) return const [];

    final deckQids = deck.map((question) => question.qid).toSet();
    final fresh = _gamePool
        .where(
          (question) =>
              question.qid != currentQid && !deckQids.contains(question.qid),
        )
        .toList();
    if (fresh.isNotEmpty) return fresh;

    return _gamePool.where((question) => question.qid != currentQid).toList();
  }

  void swapQuestion() {
    if (!canSwapQuestion) return;
    final candidates = _swapCandidates();
    final replacement = candidates[math.Random().nextInt(candidates.length)];
    final nextDeck = List<PartyQuestion>.of(deck);
    nextDeck[idx] = replacement;
    deck = nextDeck;
    swapsUsed += 1;
    swapPulse += 1;
    sub = PartySub.pick;
    side = null;
    pred = 50;
    dragX = 0;
    dragging = false;
    turnPicks = [];
    _flingTimer?.cancel();
    unawaited(HapticFeedback.selectionClick());
    notifyListeners();
  }

  // ── undo (misclick recovery) ──────────────────────────────────────────

  void _pushUndo() {
    _undoStack.add(
      _PartySnapshot(
        idx: idx,
        turn: turn,
        sub: sub,
        side: side,
        pred: pred,
        turnPicks: List.of(turnPicks),
        scores: List.of(scores),
      ),
    );
    if (_undoStack.length > 12) _undoStack.removeAt(0);
  }

  /// Restore the state captured before the last committing move (a voter
  /// swipe, the reader's lock, or advancing past a reveal).
  void undo() {
    if (_undoStack.isEmpty) return;
    final snapshot = _undoStack.removeLast();
    idx = snapshot.idx;
    turn = snapshot.turn;
    sub = snapshot.sub;
    side = snapshot.side;
    pred = snapshot.pred;
    turnPicks = List.of(snapshot.turnPicks);
    scores = List.of(snapshot.scores);
    dragX = 0;
    dragging = false;
    _revealTimer?.cancel();
    // Re-entering a reveal skips the count-up; the numbers were already seen.
    revealT = sub == PartySub.reveal ? 1 : 0;
    notifyListeners();
  }

  // ── swipe (same physics as the play surface) ──────────────────────────

  void cardDragStart() {
    if (sub != PartySub.pick) return;
    dragging = true;
    dragX = 0;
    _crossedCommit = false;
    notifyListeners();
  }

  void cardDragUpdate(double deltaX) {
    if (!dragging) return;
    dragX = (dragX + deltaX).clamp(
      -RtwV2Motion.dragClamp,
      RtwV2Motion.dragClamp,
    );
    final crossed = dragX.abs() > RtwV2Motion.commitThreshold;
    if (crossed && !_crossedCommit) unawaited(HapticFeedback.selectionClick());
    _crossedCommit = crossed;
    notifyListeners();
  }

  void cardDragEnd(double velocityX) {
    if (!dragging) return;
    dragging = false;
    const flingVelocity = 700.0;
    final fastFling =
        velocityX.abs() > flingVelocity &&
        dragX.sign == velocityX.sign &&
        dragX.abs() > 12;
    if (dragX > RtwV2Motion.commitThreshold || (fastFling && velocityX > 0)) {
      _commit('a');
    } else if (dragX < -RtwV2Motion.commitThreshold ||
        (fastFling && velocityX < 0)) {
      _commit('b');
    } else {
      dragX = 0;
      notifyListeners();
    }
  }

  void tapSide(String pickedSide) {
    if (sub != PartySub.pick) return;
    dragging = false;
    dragX = pickedSide == 'a'
        ? RtwV2Motion.flingDistance
        : -RtwV2Motion.flingDistance;
    notifyListeners();
    _flingTimer?.cancel();
    _flingTimer = Timer(RtwV2Motion.cardFling, () {
      if (sub == PartySub.pick) _commit(pickedSide);
    });
  }

  /// Prototype partyCommit: solo advances; the reader predicts; voters'
  /// swipes commit directly (pass to the next player or finalize).
  void _commit(String pickedSide) {
    unawaited(HapticFeedback.mediumImpact());
    side = pickedSide;
    dragX = 0;
    dragging = false;
    if (solo) {
      _nextQuestionOrDone();
      return;
    }
    if (turn == 0) {
      sub = PartySub.predict;
      pred = _snapPredictionValue(players <= 2 ? 100 : 50);
      notifyListeners();
      return;
    }
    _pushUndo();
    turnPicks = [...turnPicks, PartyTurnPick(side: pickedSide)];
    if (turn + 1 < players) {
      turn += 1;
      sub = PartySub.pass;
      side = null;
      notifyListeners();
    } else {
      _finalize();
    }
  }

  void changePick() {
    sub = PartySub.pick;
    side = null;
    pred = 50;
    dragX = 0;
    notifyListeners();
  }

  // ── meter (reader's prediction; snaps to 100/(players-1) steps) ───────

  int _snapPredictionValue(int value) {
    final people = math.max(1, players - 1);
    final bounded = value.clamp(0, 100);
    if (people > 25) return bounded;
    final count = ((bounded / 100) * people).round();
    return ((count / people) * 100).round().clamp(0, 100);
  }

  void meterUpdate(double fraction) {
    if (sub != PartySub.predict) return;
    final previousPred = pred;
    final people = math.max(1, players - 1);
    if (people <= 25) {
      final count = (fraction.clamp(0.0, 1.0) * people).round();
      pred = ((count / people) * 100).round().clamp(0, 100);
    } else {
      pred = (fraction.clamp(0.0, 1.0) * 100).round().clamp(0, 100);
    }
    if (pred != previousPred) unawaited(HapticFeedback.selectionClick());
    notifyListeners();
  }

  void lockTurn() {
    // Double-tap guard: the first tap moves to pass/reveal and clears the
    // side, so a re-entrant call would throw on `side!` and double-count
    // the reader's pick.
    if (sub != PartySub.predict || side == null) return;
    unawaited(HapticFeedback.mediumImpact());
    _pushUndo();
    turnPicks = [...turnPicks, PartyTurnPick(side: side!, prediction: pred)];
    if (turn + 1 < players) {
      turn += 1;
      sub = PartySub.pass;
      side = null;
      notifyListeners();
    } else {
      _finalize();
    }
  }

  void passContinue() {
    if (sub == PartySub.revealPass) {
      sub = PartySub.reveal;
      revealT = 0;
      notifyListeners();
      _animateReveal();
      return;
    }
    sub = PartySub.pick;
    side = null;
    pred = 50;
    dragX = 0;
    notifyListeners();
  }

  // ── reveal ────────────────────────────────────────────────────────────

  /// Prototype finalizeQ: actual = share of the *other* players matching the
  /// reader's side; reader score = max(0, 100 − |pred − actual|×1.3).
  void _finalize() {
    final reader = turnPicks.first;
    final actual = readerAgreementPct;
    final score = math.max(
      0,
      100 - (((reader.prediction ?? 0) - actual).abs() * 1.3).round(),
    );
    scores[readerIndex] += score;
    // The final voter must hand the phone back to the reader before any
    // answers or scores are revealed. After the reader views the reveal,
    // next() advances to the next reader's normal pass screen.
    sub = PartySub.revealPass;
    revealT = 0;
    notifyListeners();
  }

  void _animateReveal() {
    _revealTimer?.cancel();
    final start = DateTime.now();
    _revealTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().difference(start);
      final t =
          (elapsed.inMilliseconds / RtwV2Motion.partyReveal.inMilliseconds)
              .clamp(0.0, 1.0);
      revealT = 1 - math.pow(1 - t, 3).toDouble();
      notifyListeners();
      if (t >= 1) timer.cancel();
    });
  }

  int get otherPlayerCount => math.max(0, turnPicks.length - 1);

  int get othersYesCount =>
      turnPicks.skip(1).where((pick) => pick.side == 'a').length;

  /// The reveal split mirrors the population the reader predicted: everyone
  /// except the reader. Including the reader here makes a three-person game
  /// look like it was scored out of three even though the score correctly uses
  /// the other two votes.
  int get othersYesPct => otherPlayerCount == 0
      ? 0
      : ((othersYesCount / otherPlayerCount) * 100).round();

  int get readerAgreementPct {
    final reader = turnPicks.isEmpty ? null : turnPicks.first;
    if (reader == null || otherPlayerCount == 0) return 0;
    final agree = turnPicks
        .skip(1)
        .where((pick) => pick.side == reader.side)
        .length;
    return ((agree / otherPlayerCount) * 100).round();
  }

  int get readerRevealScore {
    final reader = turnPicks.isEmpty ? null : turnPicks.first;
    if (reader == null) return 0;
    return math.max(
      0,
      100 -
          (((reader.prediction ?? 0) - readerAgreementPct).abs() * 1.3).round(),
    );
  }

  void next() {
    // Double-tap guard: next() only advances off the reveal screen; the
    // first tap already moved to the hand-off (or the summary), so a second
    // call would skip a question and push a stray undo frame.
    if (stage != PartyStage.play || sub != PartySub.reveal) return;
    if (idx + 1 < deck.length) _pushUndo();
    _nextQuestionOrDone();
  }

  void _nextQuestionOrDone() {
    if (idx + 1 >= deck.length) {
      stage = PartyStage.done;
      notifyListeners();
      return;
    }
    idx += 1;
    turn = 0;
    // Multiplayer inserts a hand-off screen so the next reader knows the
    // phone is theirs; solo goes straight to the card.
    sub = solo ? PartySub.pick : PartySub.pass;
    side = null;
    pred = 50;
    dragX = 0;
    revealT = 0;
    turnPicks = [];
    notifyListeners();
  }

  /// The qids consumed this session (rotated out of future pools).
  List<String> get playedQids => deck
      .take(stage == PartyStage.done ? deck.length : idx)
      .map((question) => question.qid)
      .toList();

  @override
  void dispose() {
    _revealTimer?.cancel();
    _flingTimer?.cancel();
    super.dispose();
  }
}
