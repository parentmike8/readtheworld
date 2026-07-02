import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models_v2.dart';
import 'tokens_v2.dart';

/// Pass-the-phone party state machine — a faithful port of the prototype's
/// party handlers. Entirely session-local: scores never touch the profile.
///
/// Per question: the reader (rotating by question index) swipes their call
/// and predicts the room; every other player just swipes a vote. The reveal
/// tallies the table and scores the reader's read.
enum PartyStage { setup, play, done }

enum PartySub { pick, predict, pass, reveal }

class PartyTurnPick {
  const PartyTurnPick({required this.side, this.prediction});

  final String side; // 'a' | 'b'
  final int? prediction;
}

class PartyController extends ChangeNotifier {
  PartyStage stage = PartyStage.setup;
  int players = 4;
  int rounds = 3;
  String topic = 'All';

  List<PartyQuestion> deck = [];
  int idx = 0;
  int turn = 0;
  PartySub sub = PartySub.pick;
  String? side;
  int pred = 50;
  double dragX = 0;
  bool dragging = false;
  List<PartyTurnPick> turnPicks = [];
  List<double> scores = [];
  double revealT = 0;
  Timer? _revealTimer;
  Timer? _flingTimer;
  bool _crossedCommit = false;

  bool get solo => players < 2;
  int get readerIndex => players > 0 ? idx % players : 0;
  int get currentPlayerIndex => players > 0 ? (readerIndex + turn) % players : 0;
  PartyQuestion? get card => idx >= 0 && idx < deck.length ? deck[idx] : null;

  void setPlayers(int value) {
    players = value.clamp(1, 20);
    notifyListeners();
  }

  void setRounds(int value) {
    rounds = value.clamp(1, 5);
    notifyListeners();
  }

  void setTopic(String value) {
    topic = value;
    notifyListeners();
  }

  List<PartyQuestion> poolFor(List<PartyQuestion> pool) => topic == 'All'
      ? pool
      : pool.where((question) => question.tag == topic).toList();

  void start(List<PartyQuestion> pool) {
    final filtered = poolFor(pool);
    if (filtered.isEmpty) return;
    final shuffled = [...filtered]..shuffle(math.Random());
    final total = rounds * players;
    deck = [for (var i = 0; i < total; i++) shuffled[i % shuffled.length]];
    scores = List.filled(players, 0);
    idx = 0;
    turn = 0;
    sub = PartySub.pick;
    side = null;
    pred = 50;
    dragX = 0;
    turnPicks = [];
    revealT = 0;
    stage = PartyStage.play;
    notifyListeners();
  }

  void again() {
    stage = PartyStage.setup;
    deck = [];
    idx = 0;
    turn = 0;
    turnPicks = [];
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
    dragX = (dragX + deltaX).clamp(-RtwV2Motion.dragClamp, RtwV2Motion.dragClamp);
    final crossed = dragX.abs() > RtwV2Motion.commitThreshold;
    if (crossed && !_crossedCommit) unawaited(HapticFeedback.selectionClick());
    _crossedCommit = crossed;
    notifyListeners();
  }

  void cardDragEnd(double velocityX) {
    if (!dragging) return;
    dragging = false;
    const flingVelocity = 700.0;
    final fastFling = velocityX.abs() > flingVelocity &&
        dragX.sign == velocityX.sign &&
        dragX.abs() > 12;
    if (dragX > RtwV2Motion.commitThreshold || (fastFling && velocityX > 0)) {
      _commit('a');
    } else if (dragX < -RtwV2Motion.commitThreshold || (fastFling && velocityX < 0)) {
      _commit('b');
    } else {
      dragX = 0;
      notifyListeners();
    }
  }

  void tapSide(String pickedSide) {
    if (sub != PartySub.pick) return;
    dragging = false;
    dragX = pickedSide == 'a' ? RtwV2Motion.flingDistance : -RtwV2Motion.flingDistance;
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
      pred = players <= 2 ? 100 : 50;
      notifyListeners();
      return;
    }
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

  void meterUpdate(double fraction) {
    if (sub != PartySub.predict) return;
    final raw = (fraction.clamp(0.0, 1.0) * 100).round();
    final next = side == 'a' ? 100 - raw : raw;
    // Prototype: snap to steps of 100/(players−1) — whole other-players.
    final step = 100 / math.max(1, players - 1);
    pred = ((next / step).round() * step).round().clamp(0, 100);
    notifyListeners();
  }

  void lockTurn() {
    unawaited(HapticFeedback.mediumImpact());
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
    final others = turnPicks.skip(1).toList();
    final agree = others.where((pick) => pick.side == reader.side).length;
    final actual = others.isEmpty ? 0 : ((agree / others.length) * 100).round();
    final score = math.max(
      0,
      100 - (((reader.prediction ?? 0) - actual).abs() * 1.3).round(),
    );
    scores[readerIndex] += score;
    sub = PartySub.reveal;
    revealT = 0;
    notifyListeners();
    _animateReveal();
  }

  void _animateReveal() {
    _revealTimer?.cancel();
    final start = DateTime.now();
    _revealTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().difference(start);
      final t = (elapsed.inMilliseconds / RtwV2Motion.partyReveal.inMilliseconds)
          .clamp(0.0, 1.0);
      revealT = 1 - math.pow(1 - t, 3).toDouble();
      notifyListeners();
      if (t >= 1) timer.cancel();
    });
  }

  int get tableYesPct {
    if (turnPicks.isEmpty) return 0;
    final yes = turnPicks.where((pick) => pick.side == 'a').length;
    return ((yes / turnPicks.length) * 100).round();
  }

  int get readerRevealScore {
    final reader = turnPicks.isEmpty ? null : turnPicks.first;
    if (reader == null) return 0;
    final others = turnPicks.skip(1).toList();
    final agree = others.where((pick) => pick.side == reader.side).length;
    final actual = others.isEmpty ? 0 : ((agree / others.length) * 100).round();
    return math.max(0, 100 - (((reader.prediction ?? 0) - actual).abs() * 1.3).round());
  }

  void next() {
    if (idx + 1 >= deck.length) {
      stage = PartyStage.done;
      notifyListeners();
      return;
    }
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
    sub = PartySub.pick;
    side = null;
    pred = 50;
    dragX = 0;
    revealT = 0;
    turnPicks = [];
    notifyListeners();
  }

  /// The qids consumed this session (rotated out of future pools).
  List<String> get playedQids =>
      deck.take(stage == PartyStage.done ? deck.length : idx).map((question) => question.qid).toList();

  @override
  void dispose() {
    _revealTimer?.cancel();
    _flingTimer?.cancel();
    super.dispose();
  }
}
