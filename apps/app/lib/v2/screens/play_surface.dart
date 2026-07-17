import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../countdown.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../sheets/room_sheets.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// Prototype cubic-bezier(.2,.8,.3,1) — the card settle curve.
const _settleCurve = Cubic(0.2, 0.8, 0.3, 1);

/// TODAY — swipe deck across all unplayed rooms, or the caught-up state
/// (prototype "PLAY" + "TODAY caught up" sections).
class TodayScreenV2 extends ConsumerStatefulWidget {
  const TodayScreenV2({super.key});

  @override
  ConsumerState<TodayScreenV2> createState() => _TodayScreenV2State();
}

class _TodayScreenV2State extends ConsumerState<TodayScreenV2> {
  bool _enterTodayScheduled = false;
  String? _lastEntryFingerprint;

  @override
  void initState() {
    super.initState();
    _scheduleEnterToday();
  }

  void _scheduleEnterToday() {
    if (_enterTodayScheduled) return;
    _enterTodayScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _enterTodayScheduled = false;
      if (!mounted) return;
      final rooms = ref.read(roomsControllerProvider);
      final fingerprint = rooms.todayEntryFingerprint;
      if (rooms.play?.mode == 'today' ||
          rooms.preparingPlay ||
          _lastEntryFingerprint == fingerprint) {
        return;
      }
      _lastEntryFingerprint = fingerprint;
      await rooms.enterToday();
      if (mounted) {
        _lastEntryFingerprint = rooms.todayEntryFingerprint;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsControllerProvider);
    final session = rooms.play;
    if (session?.mode != 'today' && !rooms.preparingPlay) {
      _scheduleEnterToday();
    }
    final todaySwipe =
        session != null && session.mode == 'today' && !session.atEnd;
    return V2Scaffold(
      wideWidth: 600,
      location: '/today',
      child: todaySwipe
          ? PlaySurface(session: session)
          : rooms.preparingPlay || rooms.loadingRooms
          ? const Center(child: CircularProgressIndicator())
          : rooms.lastError != null
          ? _TodayLoadError(
              message: rooms.lastError!,
              onRetry: () {
                _lastEntryFingerprint = null;
                _scheduleEnterToday();
              },
            )
          : _CaughtUp(count: rooms.caughtUpCount),
    );
  }
}

/// Single-room play (`/today/play`) — entered from Room Detail / Rooms home.
class RoomPlayScreen extends ConsumerStatefulWidget {
  const RoomPlayScreen({super.key});

  @override
  ConsumerState<RoomPlayScreen> createState() => _RoomPlayScreenState();
}

class _RoomPlayScreenState extends ConsumerState<RoomPlayScreen> {
  // One-shot guard: without a session or summary this screen navigates away,
  // but it can rebuild several times during that transition. Firing the exit
  // navigation more than once let a stale (cleared) exit route fall through to
  // /rooms, overriding the intended destination.
  bool _exiting = false;

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsControllerProvider);
    final session = rooms.play;
    if (session != null && !session.atEnd) {
      _exiting = false;
      return V2Scaffold(
        wideWidth: 600,
        location: '/today/play',
        showNav: false,
        child: PlaySurface(session: session),
      );
    }
    if (rooms.summaryRoomId != null) {
      _exiting = false;
      return V2Scaffold(
        wideWidth: 600,
        location: '/today/play',
        showNav: false,
        child: _RoundSummary(roomId: rooms.summaryRoomId!),
      );
    }
    if (!_exiting) {
      _exiting = true;
      final exitRoute = rooms.pendingPlayExitRoute;
      // Return to wherever play was entered from (recorded entry route).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        rooms.clearPendingPlayExit();
        context.go(
          exitRoute != null && exitRoute.isNotEmpty ? exitRoute : '/rooms',
        );
      });
    }
    return const V2Scaffold(
      wideWidth: 600,
      location: '/today/play',
      showNav: false,
      child: SizedBox.shrink(),
    );
  }
}

// ── PLAY SURFACE ─────────────────────────────────────────────────────────

class PlaySurface extends ConsumerWidget {
  const PlaySurface({super.key, required this.session});

  final PlaySession session;

  /// Web-native keys: ←/→ pick a side, arrows nudge the meter (shift ×5),
  /// Enter saves or continues.
  KeyEventResult _onKey(RoomsController rooms, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (session.isRoomIntro) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.arrowRight) {
        rooms.continueFromIntro();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    switch (session.stage) {
      case PlayStage.pick:
        if (key == LogicalKeyboardKey.arrowRight) {
          rooms.commitSide('a');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          rooms.commitSide('b');
          return KeyEventResult.handled;
        }
      case PlayStage.predict:
        if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowRight) {
          rooms.nudgePred(shift ? 5 : 1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowLeft) {
          rooms.nudgePred(shift ? -5 : -1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter) {
          unawaited(rooms.lockCurrent());
          return KeyEventResult.handled;
        }
      // answerSaved is a dead stage — nothing sets it since every room took
      // on predictions (the enum value lives on in models_v2 for now).
      case PlayStage.answerSaved:
      case PlayStage.reveal:
        break;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsControllerProvider);
    final card = session.card;
    if (card == null) return const SizedBox.shrink();
    final todayMode = session.mode == 'today';
    final isIntro = card.intro;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _onKey(rooms, event),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, v2ScreenTopInset(context), 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (todayMode)
              _TodayBanner(session: session, card: card)
            else if (!isIntro)
              _RoomModeHeader(session: session, card: card, rooms: rooms),
            if (!isIntro) ...[
              const SizedBox(height: 16),
              _ProgressDots(card: card, session: session),
            ],
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey('q${session.idx}-${session.stage}'),
                  child: isIntro
                      ? _IntroCard(session: session, card: card, rooms: rooms)
                      : switch (session.stage) {
                          PlayStage.pick => _PickStage(
                            session: session,
                            card: card,
                            rooms: rooms,
                          ),
                          PlayStage.predict => _PredictStage(
                            session: session,
                            card: card,
                            rooms: rooms,
                          ),
                          // answerSaved is a dead stage — nothing sets it
                          // since every room took on predictions.
                          PlayStage.answerSaved ||
                          PlayStage.reveal => const SizedBox.shrink(),
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayBanner extends ConsumerWidget {
  const _TodayBanner({required this.session, required this.card});

  final PlaySession session;
  final TodayDeckCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionCards = session.deck
        .where((deckCard) => !deckCard.intro)
        .length;
    final answered = session.deck
        .take(session.idx)
        .where((deckCard) => !deckCard.intro)
        .length;
    final overall =
        '${(answered + (card.intro ? 0 : 1)).clamp(1, questionCards)} / $questionCards';
    final color = card.isWorld
        ? RtwV2Colors.worldInk
        : RtwV2Colors.roomColor(card.roomColorToken);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => _showRoomSwitchSheet(context, ref, session),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: RtwV2Colors.card,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: card.isWorld
                      ? const Icon(Icons.public, size: 13, color: Colors.white)
                      : Text(
                          card.roomName.isEmpty
                              ? '?'
                              : card.roomName.substring(0, 1),
                          style: v2Serif(13, color: Colors.white),
                        ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.roomName,
                      style: v2Sans(
                        14,
                        color: RtwV2Colors.inkSoft,
                        weight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      card.intro
                          ? '${card.roomTotal} questions'
                          : '${card.indexInRoom + 1} of ${card.roomTotal}',
                      style: v2Mono(
                        9,
                        color: RtwV2Colors.muted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Text(
          overall,
          style: v2Mono(11, color: RtwV2Colors.muted, letterSpacing: 1),
        ),
      ],
    );
  }
}

class _RoomModeHeader extends StatelessWidget {
  const _RoomModeHeader({
    required this.session,
    required this.card,
    required this.rooms,
  });

  final PlaySession session;
  final TodayDeckCard card;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => rooms.exitPlay(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: RtwV2Colors.card,
              border: Border.all(color: const Color(0xFFDCD6C9)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '×',
                  style: v2Sans(15, color: const Color(0xFF5C584F), height: 1),
                ),
                const SizedBox(width: 6),
                Text(
                  session.mode == 'intro' ? 'Skip' : 'Exit',
                  style: v2Sans(
                    14,
                    color: const Color(0xFF5C584F),
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          session.mode == 'intro'
              ? 'HOW IT WORKS · ${card.indexInRoom + 1} OF ${card.roomTotal}'
              : card.roomName.toUpperCase(),
          style: v2Mono(11, color: RtwV2Colors.muted, letterSpacing: 1.4),
        ),
      ],
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.card, required this.session});

  final TodayDeckCard card;
  final PlaySession session;

  @override
  Widget build(BuildContext context) {
    final total = card.roomTotal;
    final current = card.indexInRoom;
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: i < current
                    ? RtwV2Colors.blue
                    : i == current
                    ? RtwV2Colors.meterBlue.withValues(alpha: 0.45)
                    : const Color(0xFFE1DBCE),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

// ── INTRO CARD ──────────────────────────────────────────────────────────

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.session,
    required this.card,
    required this.rooms,
  });

  final PlaySession session;
  final TodayDeckCard card;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final binding = rooms.bindingFor(card.roomId);
    final hasReveal = binding?.hasUnseenReveal ?? false;
    final delta = binding?.me?.lastDelta ?? 0;
    final introOrd = session.deck
        .take(session.idx + 1)
        .where((deckCard) => deckCard.intro)
        .length;
    final introRooms = session.deck.where((deckCard) => deckCard.intro).length;
    final badgeColor = card.isWorld
        ? RtwV2Colors.worldInk
        : RtwV2Colors.roomColor(card.roomColorToken);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasReveal) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: GestureDetector(
                onTap: () =>
                    context.go('/rooms/${card.roomId}/reveal?from=today'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: RtwV2Colors.ink,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            revealLabelFor(binding?.room?.lastClosedDailyKey),
                            style: v2Mono(
                              9,
                              color: const Color(0xFF8E887C),
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'See how it moved your score',
                            style: v2Sans(
                              13,
                              color: RtwV2Colors.onDarkPaper,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            '${delta >= 0 ? '+' : ''}$delta',
                            style: v2Mono(
                              16,
                              color: delta >= 0
                                  ? RtwV2Colors.deltaUpBright
                                  : RtwV2Colors.deltaDownBright,
                              weight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '›',
                            style: v2Serif(16, color: const Color(0xFF8E887C)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -20,
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEE9DE),
                      border: Border.all(color: RtwV2Colors.border),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      'NEW QUESTIONS',
                      style: v2Mono(
                        9,
                        color: const Color(0xFFAEA894),
                        weight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: rooms.continueFromIntro,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 30,
                    ),
                    decoration: BoxDecoration(
                      color: RtwV2Colors.card,
                      border: Border.all(color: RtwV2Colors.border, width: 1.5),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A282828),
                          offset: Offset(0, 12),
                          blurRadius: 38,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'NEXT UP · ROOM $introOrd OF $introRooms',
                          style: v2Mono(
                            10,
                            color: RtwV2Colors.muted,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: card.isWorld
                              ? const Icon(
                                  Icons.public,
                                  size: 30,
                                  color: Colors.white,
                                )
                              : Text(
                                  card.roomName.isEmpty
                                      ? '?'
                                      : card.roomName.substring(0, 1),
                                  style: v2Serif(32, color: Colors.white),
                                ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          card.roomName,
                          textAlign: TextAlign.center,
                          style: v2Serif(30, height: 1.05, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${card.roomTotal} questions',
                          style: v2Sans(13, color: RtwV2Colors.subText),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Tap to start →',
                          style: v2Sans(
                            12,
                            color: RtwV2Colors.blue,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reveal chip label per prototype: yesterday / weekday / date.
///
/// Daily keys are US-Eastern calendar dates (the rollover timezone), so the
/// day-diff must use today's ET date too — device-local dates put readers
/// east of ET a day ahead and mislabel yesterday's reveal.
String revealLabelFor(String? dailyKey, {DateTime? nowUtc}) {
  if (dailyKey == null) return "YESTERDAY'S REVEAL";
  final date = DateTime.tryParse(dailyKey);
  if (date == null) return "YESTERDAY'S REVEAL";
  final now = (nowUtc ?? DateTime.now()).toUtc();
  final etWall = now.subtract(easternUtcOffset(now));
  final today = DateTime.utc(etWall.year, etWall.month, etWall.day);
  final diff = today
      .difference(DateTime.utc(date.year, date.month, date.day))
      .inDays;
  if (diff <= 1) return "YESTERDAY'S REVEAL";
  const weekdays = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];
  if (diff < 7) return "${weekdays[date.weekday - 1]}'S REVEAL";
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return '${months[date.month - 1]} ${date.day} REVEAL';
}

// ── PICK STAGE ──────────────────────────────────────────────────────────

bool _tapHitsReactionButtons(
  Offset position,
  BoxConstraints constraints, {
  required double cardHeight,
}) {
  final cardWidth = math.min(320.0, constraints.maxWidth);
  final cardLeft = (constraints.maxWidth - cardWidth) / 2;
  final cardTop = (constraints.maxHeight - cardHeight) / 2;
  return Rect.fromLTWH(
    cardLeft + cardWidth - 136,
    cardTop + 12,
    124,
    48,
  ).contains(position);
}

class _CustomQuestionAttribution extends StatelessWidget {
  const _CustomQuestionAttribution({required this.question});

  final RoomDayQuestion question;

  @override
  Widget build(BuildContext context) {
    if (!question.custom) return const SizedBox.shrink();
    final name = question.authorName?.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Text(
        'SUBMITTED BY ${name == null || name.isEmpty ? 'A ROOM MEMBER' : name.toUpperCase()}',
        style: v2Mono(9.5, color: RtwV2Colors.muted, letterSpacing: 1.1),
      ),
    );
  }
}

class _PickStage extends StatelessWidget {
  const _PickStage({
    required this.session,
    required this.card,
    required this.rooms,
  });

  final PlaySession session;
  final TodayDeckCard card;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final question = card.question!;
    final dx = session.dragX;
    final yesOn = (dx / RtwV2Motion.zoneOpacityRamp).clamp(0.0, 1.0);
    final noOn = (-dx / RtwV2Motion.zoneOpacityRamp).clamp(0.0, 1.0);
    final borderColor = dx > RtwV2Motion.borderTintThreshold
        ? RtwV2Colors.blue
        : dx < -RtwV2Motion.borderTintThreshold
        ? RtwV2Colors.clay
        : RtwV2Colors.border;
    final reaction = rooms.reactionForQuestion(question.qid);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  key: const ValueKey('play-pick-zone'),
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    if (_tapHitsReactionButtons(
                      details.localPosition,
                      constraints,
                      cardHeight: 320,
                    )) {
                      return;
                    }
                    rooms.tapSide(
                      details.localPosition.dx < constraints.maxWidth / 2
                          ? 'b'
                          : 'a',
                    );
                  },
                  child: SizedBox.expand(
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Rotated side labels behind the card.
                        Positioned(
                          left: -38,
                          top: 0,
                          bottom: 0,
                          width: 72,
                          child: IgnorePointer(
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: Text(
                                  question.optB,
                                  maxLines: 1,
                                  style: v2Serif(
                                    32,
                                    color: RtwV2Colors.clay.withValues(
                                      alpha: 0.22 + noOn * 0.58,
                                    ),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -38,
                          top: 0,
                          bottom: 0,
                          width: 72,
                          child: IgnorePointer(
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: -1,
                                child: Text(
                                  question.optA,
                                  maxLines: 1,
                                  style: v2Serif(
                                    32,
                                    color: RtwV2Colors.blue.withValues(
                                      alpha: 0.22 + yesOn * 0.58,
                                    ),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onHorizontalDragStart: (_) => rooms.cardDragStart(),
                          onHorizontalDragUpdate: (details) =>
                              rooms.cardDragUpdate(details.delta.dx),
                          onHorizontalDragEnd: (details) => rooms.cardDragEnd(
                            details.velocity.pixelsPerSecond.dx,
                          ),
                          child: AnimatedContainer(
                            duration: session.dragging
                                ? Duration.zero
                                : RtwV2Motion.cardSettle,
                            curve: _settleCurve,
                            transform: Matrix4.identity()
                              ..translateByDouble(dx, 0, 0, 1)
                              ..rotateZ(
                                dx * RtwV2Motion.tiltFactor * 3.14159 / 180,
                              ),
                            transformAlignment: Alignment.center,
                            constraints: const BoxConstraints(maxWidth: 320),
                            height: 320,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: RtwV2Colors.card,
                              border: Border.all(
                                color: borderColor,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Color.fromRGBO(
                                    40,
                                    40,
                                    40,
                                    0.08 + dx.abs() / 800,
                                  ),
                                  offset: const Offset(0, 12),
                                  blurRadius: 38,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        question.tag.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: v2Mono(
                                          10,
                                          color: RtwV2Colors.clay,
                                          letterSpacing: 1.8,
                                        ),
                                      ),
                                    ),
                                    V2QuestionReactionButtons(
                                      reaction: reaction,
                                      onToggle: (next) => unawaited(
                                        rooms.toggleQuestionReaction(
                                          question.qid,
                                          next,
                                        ),
                                      ),
                                    ),
                                    if (question.custom) ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        tooltip: 'Report this question',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.flag_outlined,
                                          size: 18,
                                          color: RtwV2Colors.danger,
                                        ),
                                        onPressed: () => showFlagSheet(
                                          context,
                                          rooms,
                                          card.roomId,
                                          question,
                                          canBlockAuthor:
                                              rooms
                                                  .bindingFor(card.roomId)
                                                  ?.me
                                                  ?.isCreator ??
                                              false,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: SingleChildScrollView(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            question.prompt,
                                            style: v2Serif(
                                              26,
                                              height: 1.18,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          _CustomQuestionAttribution(
                                            question: question,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => rooms.tapSide('b'),
                                        child: Text(
                                          '← ${question.optB}',
                                          style: v2Sans(
                                            15,
                                            color:
                                                dx <
                                                    -RtwV2Motion
                                                        .borderTintThreshold
                                                ? RtwV2Colors.clay
                                                : const Color(0xFF4A463E),
                                            weight: FontWeight.w700,
                                            height: 1.22,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 56,
                                      child: Icon(
                                        Icons.sync_alt,
                                        size: 18,
                                        color: Color(0xFFCFC8B7),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => rooms.tapSide('a'),
                                        child: Text(
                                          '${question.optA} →',
                                          textAlign: TextAlign.right,
                                          style: v2Sans(
                                            15,
                                            color:
                                                dx >
                                                    RtwV2Motion
                                                        .borderTintThreshold
                                                ? RtwV2Colors.blue
                                                : const Color(0xFF4A463E),
                                            weight: FontWeight.w700,
                                            height: 1.22,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text.rich(
            TextSpan(
              text: 'Swipe left for ',
              style: v2Sans(13, color: RtwV2Colors.faint),
              children: [
                TextSpan(
                  text: question.optB,
                  style: v2Sans(
                    13,
                    color: RtwV2Colors.subText,
                    weight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ', right for '),
                TextSpan(
                  text: question.optA,
                  style: v2Sans(
                    13,
                    color: RtwV2Colors.subText,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        if (rooms.canGoBack)
          Center(
            child: GestureDetector(
              onTap: rooms.goBack,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: const V2LeadingArrowLabel(
                  'Back to the last question',
                  color: RtwV2Colors.subText,
                  fontSize: 13,
                  weight: FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── PREDICT STAGE ───────────────────────────────────────────────────────

class _PredictStage extends StatelessWidget {
  const _PredictStage({
    required this.session,
    required this.card,
    required this.rooms,
  });

  final PlaySession session;
  final TodayDeckCard card;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final question = card.question!;
    final sideA = session.side == 'a';
    final sideLabel = sideA ? question.optA : question.optB;
    final sideColor = sideA ? RtwV2Colors.blue : RtwV2Colors.clay;
    final pred = session.pred;
    final others = (card.roomMembers - 1).clamp(0, 1 << 31);
    // Solo and The World read the prediction as a share of everyone who
    // answers, not a headcount of a fixed room.
    final infinite = session.mode == 'intro' || card.isWorld || others <= 0;
    final saveLabel = _saveLabel(session, card);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.tag.toUpperCase(),
          style: v2Mono(11, color: RtwV2Colors.clay, letterSpacing: 1.6),
        ),
        const SizedBox(height: 11),
        Text(
          question.prompt,
          style: v2Serif(27, height: 1.18, letterSpacing: -0.4),
        ),
        _CustomQuestionAttribution(question: question),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: sideColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                text: session.mode == 'intro' ? 'Your answer: ' : 'You said ',
                style: v2Sans(14, color: RtwV2Colors.subText),
                children: [
                  TextSpan(
                    text: sideLabel,
                    style: v2Sans(
                      14,
                      color: sideColor,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PredictionReadout(
                percent: pred,
                people: others,
                sideLabel: sideLabel,
                sideColor: sideColor,
                eyebrow: session.mode == 'intro'
                    ? 'NEXT: MAKE A PREDICTION'
                    : null,
                prompt: session.mode == 'intro'
                    ? 'What % of people do you think will also choose “$sideLabel”?'
                    : 'How many will agree with you?',
                sideCaption: session.mode == 'intro'
                    ? 'This is your prediction. Results come later.'
                    : null,
                secondaryText: session.mode == 'intro' ? '' : null,
                infinite: infinite,
              ),
              const SizedBox(height: 28),
              PredictionAgreementMeter(
                percent: pred,
                people: others,
                onUpdate: rooms.meterUpdate,
                infinite: infinite,
              ),
            ],
          ),
        ),
        V2Button(
          rooms.submitting ? 'Submitting...' : saveLabel,
          onPressed: rooms.submitting
              ? null
              : () => unawaited(rooms.lockCurrent()),
          padding: const EdgeInsets.symmetric(vertical: 18),
          radius: 16,
          fontSize: 16,
        ),
        _PlaySubmitError(error: rooms.lastError),
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: rooms.changeAnswer,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const V2LeadingArrowLabel(
                'Change my answer',
                color: RtwV2Colors.subText,
                fontSize: 13,
                weight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _saveLabel(PlaySession session, TodayDeckCard card) {
  final isLast = session.idx + 1 >= session.deck.length;
  if (session.mode == 'today') {
    return isLast ? 'Submit · all done →' : 'Submit · next →';
  }
  if (session.mode == 'intro') {
    return isLast
        ? 'Lock in ${session.pred}% →'
        : 'Lock in ${session.pred}% · next →';
  }
  return isLast ? 'Submit answers →' : 'Submit · next →';
}

class _PlaySubmitError extends StatelessWidget {
  const _PlaySubmitError({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final message = error;
    if (message == null || message.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: v2Sans(13, color: RtwV2Colors.danger, weight: FontWeight.w600),
      ),
    );
  }
}

String _formatThousands(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

// ── ROOM SWITCH SHEET (today banner tap) ────────────────────────────────

/// Room-switch sheet: jump to an upcoming block, or drag upcoming blocks
/// into a new order (prototype drag reorder — only rooms after the current
/// one move).
void _showRoomSwitchSheet(
  BuildContext context,
  WidgetRef ref,
  PlaySession session,
) {
  showV2Sheet(context, (sheetContext) {
    return Consumer(
      builder: (context, ref, _) {
        final rooms = ref.watch(roomsControllerProvider);
        final live = rooms.play;
        if (live == null || live.mode != 'today') {
          return const SizedBox.shrink();
        }
        final deck = live.deck;
        final blocks = <({TodayDeckCard first, int start, int size})>[];
        var i = 0;
        while (i < deck.length) {
          final roomId = deck[i].roomId;
          var j = i;
          while (j < deck.length && deck[j].roomId == roomId) {
            j++;
          }
          blocks.add((first: deck[i], start: i, size: j - i));
          i = j;
        }
        final currentBlock = blocks.indexWhere(
          (block) =>
              live.idx >= block.start && live.idx < block.start + block.size,
        );
        final fixed = blocks.sublist(0, currentBlock + 1);
        final movable = blocks.sublist(currentBlock + 1);

        Widget rowFor(
          ({TodayDeckCard first, int start, int size}) block, {
          required bool isCurrent,
          required bool isPast,
          Widget? trailing,
          Key? key,
        }) {
          final card = block.first;
          return GestureDetector(
            key: key,
            onTap: !isCurrent && !isPast
                ? () {
                    rooms.jumpToDeckIndex(block.start);
                    Navigator.of(sheetContext).pop();
                  }
                : null,
            child: Opacity(
              opacity: isPast ? 0.55 : 1,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? RtwV2Colors.meterBlue.withValues(alpha: 0.08)
                      : RtwV2Colors.card,
                  border: Border.all(
                    color: isCurrent ? Colors.transparent : RtwV2Colors.border,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: card.isWorld
                            ? RtwV2Colors.worldInk
                            : RtwV2Colors.roomColor(card.roomColorToken),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: card.isWorld
                          ? const Icon(
                              Icons.public,
                              size: 17,
                              color: Colors.white,
                            )
                          : Text(
                              card.roomName.isEmpty
                                  ? '?'
                                  : card.roomName.substring(0, 1),
                              style: v2Serif(15, color: Colors.white),
                            ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(child: Text(card.roomName, style: v2Serif(17))),
                    Text(
                      isCurrent
                          ? 'Playing now'
                          : isPast
                          ? 'Done'
                          : '${block.size - 1} questions',
                      style: v2Sans(
                        12,
                        color: RtwV2Colors.muted,
                        weight: FontWeight.w600,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const V2Eyebrow('Today\u2019s rooms'),
            const SizedBox(height: 14),
            for (final (index, block) in fixed.indexed)
              rowFor(
                block,
                isCurrent: index == currentBlock,
                isPast: index < currentBlock,
              ),
            if (movable.isNotEmpty) ...[
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  final order = movable
                      .map((block) => block.first.roomId)
                      .toList();
                  if (newIndex > oldIndex) newIndex -= 1;
                  final moved = order.removeAt(oldIndex);
                  order.insert(newIndex, moved);
                  rooms.reorderTodayBlocks(order);
                },
                children: [
                  for (final (index, block) in movable.indexed)
                    ReorderableDragStartListener(
                      key: ValueKey('switch-${block.first.roomId}'),
                      index: index,
                      child: rowFor(
                        block,
                        isCurrent: false,
                        isPast: false,
                        trailing: const Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: RtwV2Colors.faint,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Drag to reorder what comes next.',
                style: v2Sans(12, color: RtwV2Colors.faint),
              ),
            ],
          ],
        );
      },
    );
  });
}

// ── CAUGHT UP ───────────────────────────────────────────────────────────

class _TodayLoadError extends StatelessWidget {
  const _TodayLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 70, 26, 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: RtwV2Colors.muted,
          ),
          const SizedBox(height: 20),
          Text(
            'Could not refresh today.',
            textAlign: TextAlign.center,
            style: v2Serif(31, height: 1.08, letterSpacing: -0.5),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: v2Sans(14.5, color: RtwV2Colors.subText, height: 1.5),
            ),
          ),
          const SizedBox(height: 26),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: V2Button(
              'Try again',
              onPressed: onRetry,
              padding: const EdgeInsets.symmetric(vertical: 16),
              radius: 16,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 room' : '$count rooms';
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 70, 26, 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 66,
            height: 66,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: RtwV2Colors.meterBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 30, color: RtwV2Colors.blue),
          ),
          const SizedBox(height: 22),
          Text(
            "You're all caught up.",
            textAlign: TextAlign.center,
            style: v2Serif(34, height: 1.08, letterSpacing: -0.6),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              'Your reads are in across $label.',
              textAlign: TextAlign.center,
              style: v2Sans(15, color: RtwV2Colors.subText, height: 1.55),
            ),
          ),
          const SizedBox(height: 28),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: V2Button(
              'See your rooms →',
              onPressed: () => context.go('/rooms'),
              padding: const EdgeInsets.symmetric(vertical: 16),
              radius: 16,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ── ROUND SUMMARY (room mode) ───────────────────────────────────────────

class _RoundSummary extends ConsumerWidget {
  const _RoundSummary({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsControllerProvider);
    final binding = rooms.bindingFor(roomId);
    final room = binding?.room;
    final roomName = room?.name ?? 'your room';
    final isWorld = room?.isWorld ?? roomId == worldRoomId;
    final entryRoute = rooms.playEntryRoute;
    final returnsToHistory = entryRoute?.endsWith('/history') ?? false;
    final day = isWorld ? rooms.worldToday : binding?.today;
    final answer = binding?.myTodayAnswer;
    final worldGoal = _formatThousands(room?.worldGoal ?? 5000);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  V2Eyebrow(
                    roomName,
                    size: 11,
                    color: RtwV2Colors.clay,
                    letterSpacing: 1.6,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your reads are in.',
                    style: v2Serif(34, height: 1.06, letterSpacing: -0.6),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isWorld
                        ? 'Saved for The World.'
                        : 'Editable until the reveal.',
                    style: v2Sans(15, color: RtwV2Colors.subText, height: 1.55),
                  ),
                  const SizedBox(height: 24),
                  if (day != null && answer != null) ...[
                    _RoundAnswerSummary(
                      day: day,
                      answer: answer,
                      onReview: () =>
                          rooms.dismissSummaryTo('/rooms/$roomId/review'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (isWorld)
                    _WorldSummaryCard(goal: worldGoal)
                  else
                    const _RevealSummaryCard(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showInviteSheet(context, rooms, roomId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: RtwV2Colors.ink,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bring friends in to unlock World scoring.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: v2Sans(
                        13,
                        color: const Color(0xFFC7C1B3),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const V2ArrowLabel(
                    'Invite',
                    color: RtwV2Colors.onDarkBlue,
                    fontSize: 13,
                    weight: FontWeight.w700,
                  ),
                ],
              ),
            ),
          ),
          V2Button(
            returnsToHistory ? 'Back' : 'Back to $roomName',
            onPressed: () => rooms.dismissSummaryTo(
              returnsToHistory ? entryRoute! : '/rooms/$roomId',
            ),
            padding: const EdgeInsets.symmetric(vertical: 17),
            radius: 16,
            fontSize: 16,
          ),
        ],
      ),
    );
  }
}

class _RevealSummaryCard extends StatelessWidget {
  const _RevealSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RtwV2Colors.meterBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule,
                  size: 20,
                  color: RtwV2Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RevealCountdown(
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: RtwV2Colors.blue,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'See how the room answered, then get your score.',
                      style: v2Sans(
                        12.5,
                        color: RtwV2Colors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorldSummaryCard extends StatelessWidget {
  const _WorldSummaryCard({required this.goal});

  final String goal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: RtwV2Colors.meterBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.public, size: 20, color: RtwV2Colors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'World scoring',
                  style: v2Sans(
                    16,
                    color: RtwV2Colors.blue,
                    weight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Unlocks once $goal players join.',
                  style: v2Sans(12.5, color: RtwV2Colors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAnswerSummary extends StatelessWidget {
  const _RoundAnswerSummary({
    required this.day,
    required this.answer,
    required this.onReview,
  });

  final RoomDay day;
  final RoomAnswer answer;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final rows = <({RoomDayQuestion question, RoomPick pick})>[];
    for (final question in day.activeQuestions) {
      final pick = answer.pickFor(question.qid);
      if (pick != null) rows.add((question: question, pick: pick));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final answeredLabel = rows.length == 1
        ? '1 answered'
        : '${rows.length} answered';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V2Eyebrow(answeredLabel, letterSpacing: 1.4),
          const SizedBox(height: 12),
          for (var index = 0; index < rows.length; index++) ...[
            _RoundAnswerRow(
              question: rows[index].question,
              pick: rows[index].pick,
            ),
            if (index < rows.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          V2Button(
            'Review answers',
            onPressed: onReview,
            background: RtwV2Colors.card,
            foreground: RtwV2Colors.inkSoft,
            border: const BorderSide(color: RtwV2Colors.border),
            padding: const EdgeInsets.symmetric(vertical: 13),
            radius: 14,
            fontSize: 14,
          ),
        ],
      ),
    );
  }
}

class _RoundAnswerRow extends StatelessWidget {
  const _RoundAnswerRow({required this.question, required this.pick});

  final RoomDayQuestion question;
  final RoomPick pick;

  @override
  Widget build(BuildContext context) {
    final sideA = pick.side == 'a';
    final sideLabel = sideA ? question.optA : question.optB;
    final sideColor = sideA ? RtwV2Colors.blue : RtwV2Colors.clay;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: sideColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            question.prompt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: v2Sans(
              13,
              color: const Color(0xFF3B3831),
              height: 1.25,
              weight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 112),
          child: Text(
            sideLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: v2Sans(
              13,
              color: sideColor,
              weight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
