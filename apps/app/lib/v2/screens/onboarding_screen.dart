import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// ONBOARDING: three beats, about 30 seconds, using a focused teaching surface:
///  1. Today's three World questions with the real swipe and prediction
///     mechanics, without the surrounding gameplay controls.
///  2. Lightweight scoring explainer.
///  3. "3 ways to play" closer with room CTAs.
/// Finishing locks the answer sides to The World (predictions in the intro
/// are the lesson, not data — The World is answer-only until it unlocks),
/// so the first 30 seconds produce real world answers, not a demo.
class OnboardingScreenV2 extends ConsumerStatefulWidget {
  const OnboardingScreenV2({super.key});

  @override
  ConsumerState<OnboardingScreenV2> createState() => _OnboardingScreenV2State();
}

/// Crowd-pleasers for when there's no live world day (offline, first boot
/// before curation). Answers to these are local-only.
const _fallbackQuestions = [
  RoomDayQuestion(
    qid: 'intro-hotdog',
    prompt: 'Is a hot dog a sandwich?',
    optA: 'Yes',
    optB: 'No',
    tag: 'Food',
    shape: 'TASTE',
    custom: false,
  ),
  RoomDayQuestion(
    qid: 'intro-early',
    prompt: 'Would you rather always be 10 minutes early or never rushed?',
    optA: 'Early',
    optB: 'Never rushed',
    tag: 'Lifestyle',
    shape: 'TASTE',
    custom: false,
  ),
  RoomDayQuestion(
    qid: 'intro-texts',
    prompt: 'Do you re-read your own texts after sending them?',
    optA: 'Always',
    optB: 'Never',
    tag: 'Honest',
    shape: 'HABIT',
    custom: false,
  ),
];

class _OnboardingScreenV2State extends ConsumerState<OnboardingScreenV2> {
  bool _started = false;
  bool _sawIntroSession = false;
  bool _worldWaitOver = false;
  bool _usingFallback = false;
  bool _sawScoringBeat = false;
  List<RoomDayQuestion>? _questions;
  List<RoomPick>? _picks;

  @override
  void initState() {
    super.initState();
    // Give the world day stream a beat to arrive before falling back.
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _worldWaitOver = true);
    });
  }

  List<RoomDayQuestion>? _resolveQuestions(RoomsController rooms) {
    if (_questions != null) return _questions;
    final world =
        rooms.worldToday?.activeQuestions ?? const <RoomDayQuestion>[];
    if (world.length >= 3) {
      _questions = world.take(3).toList();
      _usingFallback = false;
      return _questions;
    }
    if (!rooms.firebaseReady || _worldWaitOver) {
      _questions = _fallbackQuestions;
      _usingFallback = true;
      return _questions;
    }
    return null; // still waiting on the stream
  }

  void _startIntro(RoomsController rooms, List<RoomDayQuestion> questions) {
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rooms.startIntroSession(questions);
    });
  }

  /// The intro session ended: picks mean the closer, none means Skip.
  /// Only fires once the running session has actually been observed —
  /// _startIntro launches post-frame, so a rebuild in that gap must not
  /// read "no session, no picks" as a skip.
  void _consumeIntroResult(RoomsController rooms) {
    if (!_sawIntroSession || _picks != null || rooms.play != null) return;
    final picks = rooms.takeIntroPicks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (picks == null || picks.isEmpty) {
        _skip();
      } else {
        setState(() => _picks = picks);
      }
    });
  }

  void _finish({String? homeAction}) {
    final rooms = ref.read(roomsControllerProvider);
    final picks = _picks ?? const <RoomPick>[];
    if (!_usingFallback && picks.length == 3) {
      // Sides only: The World is answer-only until it unlocks, and the
      // intro's predictions are the lesson, not data.
      unawaited(
        rooms.lockIntroWorldAnswers([
          for (final pick in picks) RoomPick(qid: pick.qid, side: pick.side),
        ]),
      );
    }
    rooms.markOnboarded();
    rooms.pendingHomeAction = homeAction;
    // Mobile: end onboarding on the notifications primer (once), then rooms.
    context.go(kIsWeb ? '/rooms' : '/notifications');
  }

  void _skip() {
    ref.read(roomsControllerProvider).markOnboarded();
    context.go(kIsWeb ? '/today' : '/notifications');
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsControllerProvider);
    final session = rooms.play;

    if (session != null && session.mode == 'intro' && !session.atEnd) {
      _sawIntroSession = true;
      return V2Scaffold(
        location: '/onboarding',
        showNav: false,
        child: _IntroPlaySurface(session: session, rooms: rooms),
      );
    }

    final questions = _resolveQuestions(rooms);
    if (questions != null && !_started) _startIntro(rooms, questions);
    _consumeIntroResult(rooms);

    return V2Scaffold(
      location: '/onboarding',
      showNav: false,
      child: _picks == null
          ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : !_sawScoringBeat
          ? _ScoringBeat(onNext: () => setState(() => _sawScoringBeat = true))
          : _CloserBeat(
              onCreate: () => _finish(homeAction: 'create'),
              onJoin: () => _finish(homeAction: 'join'),
              onDone: () => _finish(),
            ),
    );
  }
}

class _IntroPlaySurface extends StatelessWidget {
  const _IntroPlaySurface({required this.session, required this.rooms});

  final PlaySession session;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final card = session.card;
    final question = card?.question;
    if (card == null || question == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(26, v2ScreenTopInset(context), 26, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IntroTopBar(
            current: card.indexInRoom + 1,
            total: card.roomTotal,
            onSkip: rooms.exitPlay,
          ),
          const SizedBox(height: 18),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey('intro-${session.idx}-${session.stage}'),
                child: switch (session.stage) {
                  PlayStage.pick => _IntroQuestionStep(
                    session: session,
                    question: question,
                    rooms: rooms,
                  ),
                  PlayStage.predict => _IntroPredictionStep(
                    session: session,
                    question: question,
                    rooms: rooms,
                  ),
                  _ => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroTopBar extends StatelessWidget {
  const _IntroTopBar({
    required this.current,
    required this.total,
    required this.onSkip,
  });

  final int current;
  final int total;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: onSkip,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Text(
              'Skip',
              style: v2Sans(
                14,
                color: RtwV2Colors.subText,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Text(
          '$current OF $total',
          style: v2Mono(10, color: RtwV2Colors.muted, letterSpacing: 1.4),
        ),
      ],
    );
  }
}

class _IntroQuestionStep extends StatelessWidget {
  const _IntroQuestionStep({
    required this.session,
    required this.question,
    required this.rooms,
  });

  final PlaySession session;
  final RoomDayQuestion question;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final cardHeight = compact ? 290.0 : 330.0;
        final cardWidth = constraints.maxWidth < 330
            ? constraints.maxWidth
            : 330.0;
        final dx = session.dragX;
        final borderColor = dx > RtwV2Motion.borderTintThreshold
            ? RtwV2Colors.blue
            : dx < -RtwV2Motion.borderTintThreshold
            ? RtwV2Colors.clay
            : RtwV2Colors.borderStrong;
        return Column(
          children: [
            const Spacer(),
            GestureDetector(
              onTapUp: (details) => rooms.commitSide(
                details.localPosition.dx < cardWidth / 2 ? 'b' : 'a',
              ),
              onHorizontalDragStart: (_) => rooms.cardDragStart(),
              onHorizontalDragUpdate: (details) =>
                  rooms.cardDragUpdate(details.delta.dx),
              onHorizontalDragEnd: (details) =>
                  rooms.cardDragEnd(details.velocity.pixelsPerSecond.dx),
              child: AnimatedContainer(
                duration: session.dragging
                    ? Duration.zero
                    : RtwV2Motion.cardSettle,
                curve: Curves.easeOutCubic,
                transform: Matrix4.identity()
                  ..translateByDouble(dx, 0, 0, 1)
                  ..rotateZ(dx * RtwV2Motion.tiltFactor * 3.14159 / 180),
                transformAlignment: Alignment.center,
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 330),
                height: cardHeight,
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                decoration: BoxDecoration(
                  color: RtwV2Colors.card,
                  border: Border.all(color: borderColor, width: 1.5),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14282828),
                      offset: Offset(0, 12),
                      blurRadius: 34,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          question.prompt,
                          textAlign: TextAlign.center,
                          style: v2Serif(
                            compact ? 28 : 31,
                            height: 1.13,
                            letterSpacing: -0.45,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '← ${question.optB}',
                            textAlign: TextAlign.left,
                            style: v2Sans(
                              13,
                              color: RtwV2Colors.clayTextDeep,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${question.optA} →',
                            textAlign: TextAlign.right,
                            style: v2Sans(
                              13,
                              color: RtwV2Colors.blueTextDeep,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: compact ? 20 : 26),
            Text(
              'Swipe to choose',
              style: v2Sans(13, color: RtwV2Colors.subText),
            ),
            const Spacer(),
          ],
        );
      },
    );
  }
}

class _IntroPredictionStep extends StatelessWidget {
  const _IntroPredictionStep({
    required this.session,
    required this.question,
    required this.rooms,
  });

  final PlaySession session;
  final RoomDayQuestion question;
  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final sideLabel = session.side == 'a' ? question.optA : question.optB;
    final isLast = session.idx + 1 >= session.deck.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 650;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'YOUR ANSWER: $sideLabel',
              textAlign: TextAlign.center,
              style: v2Mono(
                10,
                color: RtwV2Colors.blueTextDeep,
                letterSpacing: 1.2,
                weight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            const Center(
              child: V2Eyebrow('Now make a prediction', letterSpacing: 1.5),
            ),
            const SizedBox(height: 10),
            Text(
              'What % of all people do you think will also choose “$sideLabel”?',
              textAlign: TextAlign.center,
              style: v2Serif(
                compact ? 25 : 29,
                height: 1.18,
                letterSpacing: -0.35,
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Text(
              '${session.pred}%',
              textAlign: TextAlign.center,
              style: v2Serif(
                compact ? 68 : 82,
                color: RtwV2Colors.meterBlue,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This is your prediction. Results come later.',
              textAlign: TextAlign.center,
              style: v2Sans(13, color: RtwV2Colors.subText),
            ),
            const Spacer(),
            PredictionAgreementMeter(
              percent: session.pred,
              people: 0,
              onUpdate: rooms.meterUpdate,
              height: compact ? 64 : 72,
              infinite: true,
            ),
            SizedBox(height: compact ? 14 : 20),
            V2Button(
              rooms.submitting
                  ? 'Submitting...'
                  : isLast
                  ? 'Lock in ${session.pred}% →'
                  : 'Lock in ${session.pred}% · next →',
              onPressed: rooms.submitting
                  ? null
                  : () => unawaited(rooms.lockCurrent()),
              padding: const EdgeInsets.symmetric(vertical: 17),
              radius: 16,
              fontSize: 16,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: rooms.changeAnswer,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Change my answer',
                  textAlign: TextAlign.center,
                  style: v2Sans(13, color: RtwV2Colors.subText),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScoringBeat extends StatelessWidget {
  const _ScoringBeat({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final topPadding = compact ? 38.0 : 66.0;
        const bottomPadding = 34.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(26, topPadding, 26, bottomPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - topPadding - bottomPadding)
                  .clamp(0, double.infinity),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const V2Eyebrow('How scoring works', letterSpacing: 1.8),
                  SizedBox(height: compact ? 18 : 26),
                  Text(
                    'Closer predictions score more.',
                    style: v2Serif(40, height: 1.04, letterSpacing: -0.8),
                  ),
                  const Spacer(),
                  const _ScoreExample(),
                  const Spacer(),
                  Text(
                    'This tutorial was practice. Nothing was scored.',
                    textAlign: TextAlign.center,
                    style: v2Sans(13, color: RtwV2Colors.subText, height: 1.35),
                  ),
                  SizedBox(height: compact ? 20 : 28),
                  V2Button(
                    'Continue →',
                    onPressed: onNext,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    radius: 16,
                    fontSize: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScoreExample extends StatelessWidget {
  const _ScoreExample();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const V2Eyebrow('Example round', letterSpacing: 1.5),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: _ScoreValue(
                  label: 'YOUR PREDICTION',
                  value: '60%',
                  color: RtwV2Colors.blue,
                ),
              ),
              Container(width: 1, height: 54, color: RtwV2Colors.border),
              const Expanded(
                child: _ScoreValue(
                  label: 'ACTUAL RESULT',
                  value: '57%',
                  color: RtwV2Colors.clay,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: RtwV2Colors.meterBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.adjust_rounded,
                  size: 18,
                  color: RtwV2Colors.blueTextDeep,
                ),
                const SizedBox(width: 8),
                Text(
                  'Only 3 points apart',
                  style: v2Sans(
                    13,
                    color: RtwV2Colors.blueTextDeep,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Your prediction is compared with the real result.',
            textAlign: TextAlign.center,
            style: v2Sans(13, color: RtwV2Colors.subText),
          ),
        ],
      ),
    );
  }
}

class _ScoreValue extends StatelessWidget {
  const _ScoreValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: v2Mono(9, color: RtwV2Colors.muted, letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        Text(value, style: v2Serif(36, color: color, height: 1)),
      ],
    );
  }
}

class _CloserBeat extends StatelessWidget {
  const _CloserBeat({
    required this.onCreate,
    required this.onJoin,
    required this.onDone,
  });

  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 760;
        final topPadding = compact ? 34.0 : 54.0;
        const bottomPadding = 24.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(26, topPadding, 26, bottomPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - topPadding - bottomPadding)
                  .clamp(0, double.infinity),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const V2Eyebrow(
                    'How it works · your people',
                    letterSpacing: 1.8,
                  ),
                  SizedBox(height: compact ? 18 : 24),
                  Text(
                    '3 ways to play',
                    style: v2Serif(40, height: 1.04, letterSpacing: -0.8),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'How well do you know your people?',
                    style: v2Sans(15, color: RtwV2Colors.subText, height: 1.45),
                  ),
                  Spacer(flex: compact ? 1 : 2),
                  const _PeopleRow(
                    glyph: _WayGlyph.party,
                    color: RtwV2Colors.clay,
                    title: 'Party',
                    body: 'In the room with you',
                  ),
                  SizedBox(height: compact ? 18 : 22),
                  const _PeopleRow(
                    glyph: _WayGlyph.rooms,
                    color: RtwV2Colors.blue,
                    title: 'Rooms',
                    body:
                        'Friends, family or coworkers\n3 questions every 24 hours',
                  ),
                  SizedBox(height: compact ? 18 : 22),
                  const _PeopleRow(
                    glyph: _WayGlyph.world,
                    color: RtwV2Colors.green,
                    title: 'The World',
                    body: 'Everyone, everywhere\n3 questions every 24 hours',
                    badge: 'SOON',
                  ),
                  Spacer(flex: compact ? 1 : 2),
                  V2Button(
                    'Start a room →',
                    onPressed: onCreate,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    radius: 16,
                    fontSize: 16,
                  ),
                  const SizedBox(height: 6),
                  _GhostCta(label: "Join with a friend's code", onTap: onJoin),
                  _GhostCta(label: 'Not now', muted: true, onTap: onDone),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GhostCta extends StatelessWidget {
  const _GhostCta({
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: v2Sans(
            14,
            color: muted ? RtwV2Colors.muted : RtwV2Colors.blueTextDeep,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

enum _WayGlyph { party, rooms, world }

/// Prototype welcome-row icons (20px SVGs, stroke 1.5, round caps).
class _WayGlyphPainter extends CustomPainter {
  const _WayGlyphPainter({required this.glyph, required this.color});

  final _WayGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    switch (glyph) {
      case _WayGlyph.party:
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawPath(
          Path()
            ..moveTo(5, 4)
            ..lineTo(16, 10)
            ..lineTo(5, 16)
            ..close(),
          fill,
        );
      case _WayGlyph.rooms:
        for (final offset in const [
          Offset(4, 4),
          Offset(12, 4),
          Offset(4, 12),
          Offset(12, 12),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(offset.dx, offset.dy, 5, 5),
              const Radius.circular(1.4),
            ),
            stroke,
          );
        }
      case _WayGlyph.world:
        // Globe: circle, equator, meridian lens.
        canvas.drawCircle(const Offset(10, 10), 7.5, stroke);
        canvas.drawLine(const Offset(2.5, 10), const Offset(17.5, 10), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(10, 2.5)
            ..relativeCubicTo(2, 2.2, 3, 4.7, 3, 7.5)
            ..relativeCubicTo(0, 2.8, -1, 5.3, -3, 7.5)
            ..relativeCubicTo(-2, -2.2, -3, -4.7, -3, -7.5)
            ..relativeCubicTo(0, -2.8, 1, -5.3, 3, -7.5)
            ..close(),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_WayGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

class _PeopleRow extends StatelessWidget {
  const _PeopleRow({
    required this.glyph,
    required this.color,
    required this.title,
    required this.body,
    this.badge,
  });

  final _WayGlyph glyph;
  final Color color;
  final String title;
  final String body;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 46,
          child: Center(
            child: CustomPaint(
              size: const Size(22, 22),
              painter: _WayGlyphPainter(glyph: glyph, color: color),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: v2Serif(
                        29,
                        color: RtwV2Colors.inkSoft,
                        height: 1.05,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: RtwV2Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge!,
                        style: v2Mono(
                          9.5,
                          color: RtwV2Colors.green,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              Text(
                body,
                style: v2Mono(
                  12.5,
                  color: RtwV2Colors.subText,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
