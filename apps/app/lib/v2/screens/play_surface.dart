import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rooms = ref.read(roomsControllerProvider);
      if (rooms.play?.mode != 'today') rooms.enterToday();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsControllerProvider);
    final session = rooms.play;
    final todaySwipe = session != null && session.mode == 'today' && !session.atEnd;
    return V2Scaffold(
      location: '/today',
      child: todaySwipe
          ? PlaySurface(session: session)
          : _CaughtUp(count: rooms.caughtUpCount),
    );
  }
}

/// Single-room play (`/today/play`) — entered from Room Detail / Rooms home.
class RoomPlayScreen extends ConsumerWidget {
  const RoomPlayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsControllerProvider);
    final session = rooms.play;
    if (session != null && !session.atEnd) {
      return V2Scaffold(
        location: '/today/play',
        showNav: false,
        child: PlaySurface(session: session),
      );
    }
    if (rooms.summaryRoomId != null) {
      return V2Scaffold(
        location: '/today/play',
        showNav: false,
        child: _RoundSummary(roomId: rooms.summaryRoomId!),
      );
    }
    // Deep link with no active session: send home.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/rooms');
    });
    return const V2Scaffold(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsControllerProvider);
    final card = session.card;
    if (card == null) return const SizedBox.shrink();
    final todayMode = session.mode == 'today';
    final isIntro = card.intro;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 54, 22, 26),
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
                        PlayStage.pick => _PickStage(session: session, card: card, rooms: rooms),
                        PlayStage.predict => _PredictStage(session: session, card: card, rooms: rooms),
                        PlayStage.answerSaved => _AnswerSavedStage(session: session, card: card, rooms: rooms),
                        PlayStage.reveal => const SizedBox.shrink(),
                      },
              ),
            ),
          ),
        ],
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
    final questionCards = session.deck.where((deckCard) => !deckCard.intro).length;
    final answered = session.deck.take(session.idx).where((deckCard) => !deckCard.intro).length;
    final overall = '${(answered + (card.intro ? 0 : 1)).clamp(1, questionCards)} / $questionCards';
    final color = card.isWorld ? RtwV2Colors.worldInk : RtwV2Colors.roomColor(card.roomColorToken);
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
                          card.roomName.isEmpty ? '?' : card.roomName.substring(0, 1),
                          style: v2Serif(13, color: Colors.white),
                        ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.roomName,
                      style: v2Sans(14, color: RtwV2Colors.inkSoft, weight: FontWeight.w700, height: 1.1),
                    ),
                    Text(
                      card.intro
                          ? '${card.roomTotal} questions'
                          : '${card.indexInRoom + 1} of ${card.roomTotal}',
                      style: v2Mono(9, color: RtwV2Colors.muted, letterSpacing: 0.8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Text(overall, style: v2Mono(11, color: RtwV2Colors.muted, letterSpacing: 1)),
      ],
    );
  }
}

class _RoomModeHeader extends StatelessWidget {
  const _RoomModeHeader({required this.session, required this.card, required this.rooms});

  final PlaySession session;
  final TodayDeckCard card;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () {
            rooms.exitPlay();
            context.go('/rooms/${card.roomId}');
          },
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
                Text('×', style: v2Sans(15, color: const Color(0xFF5C584F), height: 1)),
                const SizedBox(width: 6),
                Text(
                  'Exit',
                  style: v2Sans(14, color: const Color(0xFF5C584F), weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        Text(
          card.roomName.toUpperCase(),
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
  const _IntroCard({required this.session, required this.card, required this.rooms});

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
    final badgeColor =
        card.isWorld ? RtwV2Colors.worldInk : RtwV2Colors.roomColor(card.roomColorToken);

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasReveal) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: GestureDetector(
                onTap: () => context.go('/rooms/${card.roomId}/reveal?from=today'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                            style: v2Mono(9, color: const Color(0xFF8E887C), letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'See how it moved your score',
                            style: v2Sans(13, color: RtwV2Colors.onDarkPaper, weight: FontWeight.w600),
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
                          Text('›', style: v2Serif(16, color: const Color(0xFF8E887C))),
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
                      style: v2Mono(9, color: const Color(0xFFAEA894), weight: FontWeight.w600, letterSpacing: 2),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: rooms.continueFromIntro,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
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
                          style: v2Mono(10, color: RtwV2Colors.muted, letterSpacing: 1.8),
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
                              ? const Icon(Icons.public, size: 30, color: Colors.white)
                              : Text(
                                  card.roomName.isEmpty ? '?' : card.roomName.substring(0, 1),
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
                          style: v2Sans(12, color: RtwV2Colors.blue, weight: FontWeight.w600),
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
String revealLabelFor(String? dailyKey) {
  if (dailyKey == null) return "YESTERDAY'S REVEAL";
  final date = DateTime.tryParse(dailyKey);
  if (date == null) return "YESTERDAY'S REVEAL";
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(date.year, date.month, date.day)).inDays;
  if (diff <= 1) return "YESTERDAY'S REVEAL";
  const weekdays = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
  if (diff < 7) return "${weekdays[date.weekday - 1]}'S REVEAL";
  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  return '${months[date.month - 1]} ${date.day} REVEAL';
}

// ── PICK STAGE ──────────────────────────────────────────────────────────

class _PickStage extends StatelessWidget {
  const _PickStage({required this.session, required this.card, required this.rooms});

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

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Rotated side labels behind the card.
                Positioned(
                  left: -4,
                  top: 0,
                  bottom: 0,
                  width: 52,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        question.optB,
                        maxLines: 1,
                        style: v2Serif(
                          30,
                          color: RtwV2Colors.clay.withValues(alpha: 0.16 + noOn * 0.72),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -4,
                  top: 0,
                  bottom: 0,
                  width: 52,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: Text(
                        question.optA,
                        maxLines: 1,
                        style: v2Serif(
                          30,
                          color: RtwV2Colors.blue.withValues(alpha: 0.16 + yesOn * 0.72),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onHorizontalDragStart: (_) => rooms.cardDragStart(),
                  onHorizontalDragUpdate: (details) => rooms.cardDragUpdate(details.delta.dx),
                  onHorizontalDragEnd: (details) =>
                      rooms.cardDragEnd(details.velocity.pixelsPerSecond.dx),
                  child: AnimatedContainer(
                    duration: session.dragging ? Duration.zero : RtwV2Motion.cardSettle,
                    curve: _settleCurve,
                    transform: Matrix4.identity()
                      ..translateByDouble(dx, 0, 0, 1)
                      ..rotateZ(dx * RtwV2Motion.tiltFactor * 3.14159 / 180),
                    transformAlignment: Alignment.center,
                    constraints: const BoxConstraints(maxWidth: 320, minHeight: 320),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: RtwV2Colors.card,
                      border: Border.all(color: borderColor, width: 1.5),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(40, 40, 40, 0.08 + dx.abs() / 800),
                          offset: const Offset(0, 12),
                          blurRadius: 38,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question.tag.toUpperCase(),
                          style: v2Mono(10, color: RtwV2Colors.clay, letterSpacing: 1.8),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 208),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Text(
                                question.prompt,
                                style: v2Serif(26, height: 1.18, letterSpacing: -0.3),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: () => rooms.tapSide('b'),
                                child: Text(
                                  '← ${question.optB}',
                                  style: v2Sans(
                                    15,
                                    color: dx < -RtwV2Motion.borderTintThreshold
                                        ? RtwV2Colors.clay
                                        : const Color(0xFF4A463E),
                                    weight: FontWeight.w700,
                                    height: 1.22,
                                  ),
                                ),
                              ),
                            ),
                            const Icon(Icons.sync_alt, size: 18, color: Color(0xFFCFC8B7)),
                            Flexible(
                              child: GestureDetector(
                                onTap: () => rooms.tapSide('a'),
                                child: Text(
                                  '${question.optA} →',
                                  textAlign: TextAlign.right,
                                  style: v2Sans(
                                    15,
                                    color: dx > RtwV2Motion.borderTintThreshold
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
                  style: v2Sans(13, color: RtwV2Colors.subText, weight: FontWeight.w700),
                ),
                const TextSpan(text: ', right for '),
                TextSpan(
                  text: question.optA,
                  style: v2Sans(13, color: RtwV2Colors.subText, weight: FontWeight.w700),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ── PREDICT STAGE ───────────────────────────────────────────────────────

class _PredictStage extends StatelessWidget {
  const _PredictStage({required this.session, required this.card, required this.rooms});

  final PlaySession session;
  final TodayDeckCard card;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final question = card.question!;
    final sideA = session.side == 'a';
    final sideLabel = sideA ? question.optA : question.optB;
    final otherLabel = sideA ? question.optB : question.optA;
    final sideColor = sideA ? RtwV2Colors.blue : RtwV2Colors.clay;
    final pred = session.pred;
    final others = (card.roomMembers - 1).clamp(0, 1 << 31);
    final saveLabel = _saveLabel(session, card);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.tag.toUpperCase(),
          style: v2Mono(11, color: RtwV2Colors.clay, letterSpacing: 1.6),
        ),
        const SizedBox(height: 11),
        Text(question.prompt, style: v2Serif(27, height: 1.18, letterSpacing: -0.4)),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: sideColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                text: 'You said ',
                style: v2Sans(14, color: RtwV2Colors.subText),
                children: [
                  TextSpan(
                    text: sideLabel,
                    style: v2Sans(14, color: sideColor, weight: FontWeight.w700),
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  'What share of the rest of ${session.mode == 'today' ? card.roomName : 'the room'} also said “$sideLabel”?',
                  textAlign: TextAlign.center,
                  style: v2Serif(22, color: const Color(0xFF2C2A24), height: 1.28, letterSpacing: -0.2),
                ),
              ),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(
                  text: '$pred',
                  style: v2Serif(80, color: sideColor, height: 1),
                  children: [
                    TextSpan(text: '%', style: v2Serif(34, color: sideColor)),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '≈ ${(pred / 100 * others).round()} of $others people',
                textAlign: TextAlign.center,
                style: v2Sans(13, color: RtwV2Colors.muted),
              ),
              const SizedBox(height: 28),
              _EdgeMeter(session: session, sideLabel: sideLabel, rooms: rooms),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    sideA ? 'NEARLY ALL' : 'NEARLY NONE',
                    style: v2Mono(10, color: RtwV2Colors.muted, letterSpacing: 0.5),
                  ),
                  Text(
                    sideA ? 'NEARLY NONE' : 'NEARLY ALL',
                    style: v2Mono(10, color: RtwV2Colors.muted, letterSpacing: 0.5),
                  ),
                ],
              ),
              if (session.armSwitch)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.9, end: 1),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.ease,
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: Opacity(opacity: (scale - 0.9) * 10, child: child),
                    ),
                    child: Text(
                      'Release to switch to $otherLabel',
                      textAlign: TextAlign.center,
                      style: v2Sans(12, color: RtwV2Colors.clay, weight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
        V2Button(
          saveLabel,
          onPressed: () => rooms.lockCurrent(),
          padding: const EdgeInsets.symmetric(vertical: 18),
          radius: 16,
          fontSize: 16,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: rooms.changeAnswer,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '← Change my answer',
              textAlign: TextAlign.center,
              style: v2Sans(13, color: RtwV2Colors.subText),
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
    return isLast ? 'Save · all done →' : 'Save · next →';
  }
  return isLast ? 'Save answers →' : 'Save · next →';
}

/// The edge meter: fill docks to the picked side (side A → right), dragging
/// toward the far edge shrinks the share; hitting ≤2 arms a side flip.
class _EdgeMeter extends StatelessWidget {
  const _EdgeMeter({required this.session, required this.sideLabel, required this.rooms});

  final PlaySession session;
  final String sideLabel;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final sideA = session.side == 'a';
    final pred = session.pred;
    final fillColor = sideA
        ? RtwV2Colors.meterBlue.withValues(alpha: 0.85)
        : RtwV2Colors.meterClay.withValues(alpha: 0.9);
    final inverseColor = sideA
        ? RtwV2Colors.meterClay.withValues(alpha: 0.10)
        : RtwV2Colors.meterBlue.withValues(alpha: 0.10);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void update(double localX) => rooms.meterUpdate(localX / width);
        final handleFraction = (sideA ? (100 - pred) : pred) / 100;
        return GestureDetector(
          onHorizontalDragDown: (details) => update(details.localPosition.dx),
          onHorizontalDragUpdate: (details) => update(details.localPosition.dx),
          onHorizontalDragEnd: (_) => rooms.meterRelease(),
          onHorizontalDragCancel: rooms.meterRelease,
          onTapUp: (details) {
            update(details.localPosition.dx);
            rooms.meterRelease();
          },
          child: Container(
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFE6E0D3),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: sideA ? Alignment.centerLeft : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: (100 - pred) / 100,
                    child: Container(height: 72, color: inverseColor),
                  ),
                ),
                Align(
                  alignment: sideA ? Alignment.centerRight : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: pred / 100,
                    child: Container(height: 72, color: fillColor),
                  ),
                ),
                Align(
                  alignment: sideA ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      sideLabel.toUpperCase(),
                      style: v2Mono(12, color: Colors.white, letterSpacing: 1.5),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment(handleFraction * 2 - 1, 0),
                  child: Container(
                    width: 6,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40000000),
                          offset: Offset(0, 1),
                          blurRadius: 4,
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
    );
  }
}

// ── ANSWER SAVED (solo / locked world) ──────────────────────────────────

class _AnswerSavedStage extends ConsumerWidget {
  const _AnswerSavedStage({required this.session, required this.card, required this.rooms});

  final PlaySession session;
  final TodayDeckCard card;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final question = card.question!;
    final sideA = session.side == 'a';
    final sideLabel = sideA ? question.optA : question.optB;
    final sideColor = sideA ? RtwV2Colors.blue : RtwV2Colors.clay;
    final isWorld = session.answerSavedReason == 'world';
    final threshold = question.threshold ?? 1000;
    final answers = (rooms.worldToday?.answerCounts[question.qid] ?? 0) + 1;
    final pct = (answers / threshold).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.tag.toUpperCase(),
          style: v2Mono(11, color: RtwV2Colors.clay, letterSpacing: 1.6),
        ),
        const SizedBox(height: 11),
        Text(question.prompt, style: v2Serif(27, height: 1.18, letterSpacing: -0.4)),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: sideColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text.rich(
              TextSpan(
                text: 'You said ',
                style: v2Sans(14, color: RtwV2Colors.subText),
                children: [
                  TextSpan(
                    text: sideLabel,
                    style: v2Sans(14, color: sideColor, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: RtwV2Colors.blue.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 24, color: RtwV2Colors.blue),
                ),
                const SizedBox(height: 16),
                if (isWorld) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      'Saved. Predicting opens once this question crosses ${_formatThousands(threshold)} answers.',
                      textAlign: TextAlign.center,
                      style: v2Serif(22, color: const Color(0xFF2C2A24), height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            height: 8,
                            color: const Color(0xFFE6E0D3),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: pct,
                              child: Container(color: RtwV2Colors.blue),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_formatThousands(answers)} / ${_formatThousands(threshold)} world answers',
                          style: v2Sans(12.5, color: RtwV2Colors.muted),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      'Saved. No one else here yet, so no prediction to make.',
                      textAlign: TextAlign.center,
                      style: v2Serif(22, color: const Color(0xFF2C2A24), height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      "Invite someone into this room and you'll both start predicting each other.",
                      textAlign: TextAlign.center,
                      style: v2Sans(13.5, color: RtwV2Colors.faint, height: 1.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        V2Button(
          _saveLabel(session, card),
          onPressed: () => rooms.lockCurrent(answerOnly: true),
          padding: const EdgeInsets.symmetric(vertical: 18),
          radius: 16,
          fontSize: 16,
        ),
      ],
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
void _showRoomSwitchSheet(BuildContext context, WidgetRef ref, PlaySession session) {
  showV2Sheet(context, (sheetContext) {
    return Consumer(builder: (context, ref, _) {
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
        (block) => live.idx >= block.start && live.idx < block.start + block.size,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        ? const Icon(Icons.public, size: 17, color: Colors.white)
                        : Text(
                            card.roomName.isEmpty ? '?' : card.roomName.substring(0, 1),
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
                    style: v2Sans(12, color: RtwV2Colors.muted, weight: FontWeight.w600),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing],
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
                final order = movable.map((block) => block.first.roomId).toList();
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
    });
  });
}

// ── CAUGHT UP ───────────────────────────────────────────────────────────

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
              'Your calls are in across $label. The reveals land tomorrow, so '
              'check each room to see how you read it.',
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
    final roomName = rooms.bindingFor(roomId)?.room?.name ?? 'your room';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V2Eyebrow('Round complete · $roomName', size: 11, color: RtwV2Colors.clay, letterSpacing: 1.6),
          const SizedBox(height: 12),
          Text(
            "That's your three in.",
            style: v2Serif(34, height: 1.06, letterSpacing: -0.6),
          ),
          const SizedBox(height: 14),
          Text(
            "Your calls are locked. You'll see how $roomName answered, and how "
            'it moves your Read Score, tomorrow.',
            style: v2Sans(15, color: RtwV2Colors.subText, height: 1.55),
          ),
          const SizedBox(height: 24),
          Container(
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
                  child: const Icon(Icons.schedule, size: 20, color: RtwV2Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Come back tomorrow for the reveal and your accuracy.',
                    style: v2Sans(13.5, color: const Color(0xFF5C584F), height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: RtwV2Colors.ink,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text.rich(
              TextSpan(
                text: 'Every friend you bring gets the World closer to unlocking. ',
                style: v2Sans(13, color: const Color(0xFFC7C1B3), height: 1.5),
                children: [
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () => showInviteSheet(context, rooms, roomId),
                      child: Text(
                        'Invite →',
                        style: v2Sans(13, color: RtwV2Colors.onDarkBlue, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          V2Button(
            'Back to $roomName',
            onPressed: () {
              rooms.dismissSummary();
              context.go('/rooms/$roomId');
            },
            padding: const EdgeInsets.symmetric(vertical: 17),
            radius: 16,
            fontSize: 16,
          ),
        ],
      ),
    );
  }
}
