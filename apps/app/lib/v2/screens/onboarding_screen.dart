import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// ONBOARDING — three beats, ~20 seconds:
///  1. Answer today's three World questions (no preamble — playing is the
///     pitch). Falls back to bundled questions when no world day is live.
///  2. One teaching prediction (not recorded — The World is answer-only
///     until it unlocks).
///  3. "Who are your people?" closer with room CTAs.
/// Finishing locks the real answers to The World, so the intro produces
/// real data instead of a throwaway demo.
class OnboardingScreenV2 extends ConsumerStatefulWidget {
  const OnboardingScreenV2({super.key});

  @override
  ConsumerState<OnboardingScreenV2> createState() => _OnboardingScreenV2State();
}

enum _IntroStep { questions, predict, closer }

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
  _IntroStep step = _IntroStep.questions;
  int qIndex = 0;
  final Map<String, String> sides = {};
  int pred = 50;
  bool _worldWaitOver = false;
  bool _usingFallback = false;
  List<RoomDayQuestion>? _questions;

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
    final world = rooms.worldToday?.activeQuestions ?? const <RoomDayQuestion>[];
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

  void _pick(RoomDayQuestion question, String side) {
    setState(() {
      sides[question.qid] = side;
      if (qIndex + 1 < 3) {
        qIndex += 1;
      } else {
        step = _IntroStep.predict;
      }
    });
  }

  void _finish({String? homeAction}) {
    final rooms = ref.read(roomsControllerProvider);
    final questions = _questions;
    if (!_usingFallback && questions != null && questions.length == 3) {
      final picks = [
        for (final question in questions)
          if (sides[question.qid] != null)
            RoomPick(qid: question.qid, side: sides[question.qid]!),
      ];
      if (picks.length == 3) {
        unawaited(rooms.lockIntroWorldAnswers(picks));
      }
    }
    rooms.markOnboarded();
    rooms.pendingHomeAction = homeAction;
    context.go('/rooms');
  }

  void _skip() {
    ref.read(roomsControllerProvider).markOnboarded();
    context.go('/today');
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsControllerProvider);
    final questions = _resolveQuestions(rooms);

    return V2Scaffold(
      location: '/onboarding',
      showNav: false,
      child: questions == null
          ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: switch (step) {
                _IntroStep.questions => _QuestionBeat(
                  key: ValueKey('q$qIndex'),
                  question: questions[qIndex],
                  index: qIndex,
                  selected: sides[questions[qIndex].qid],
                  onPick: (side) => _pick(questions[qIndex], side),
                  onSkip: _skip,
                ),
                _IntroStep.predict => _PredictBeat(
                  key: const ValueKey('predict'),
                  question: questions[2],
                  side: sides[questions[2].qid] ?? 'a',
                  pred: pred,
                  onPred: (next) => setState(() => pred = next),
                  onLock: () => setState(() => step = _IntroStep.closer),
                  onSkip: _skip,
                ),
                _IntroStep.closer => _CloserBeat(
                  key: const ValueKey('closer'),
                  onCreate: () => _finish(homeAction: 'create'),
                  onJoin: () => _finish(homeAction: 'join'),
                  onDone: () => _finish(),
                ),
              },
            ),
    );
  }
}

class _IntroHeader extends StatelessWidget {
  const _IntroHeader({required this.label, this.onSkip});

  final String label;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        V2Eyebrow(label, letterSpacing: 1.8),
        if (onSkip != null)
          GestureDetector(
            onTap: onSkip,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'Skip',
                style: v2Sans(13, color: RtwV2Colors.muted, weight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

class _QuestionBeat extends StatelessWidget {
  const _QuestionBeat({
    super.key,
    required this.question,
    required this.index,
    required this.selected,
    required this.onPick,
    required this.onSkip,
  });

  final RoomDayQuestion question;
  final int index;
  final String? selected;
  final ValueChanged<String> onPick;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 66, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IntroHeader(label: 'How it works · ${index + 1} of 3', onSkip: onSkip),
          const SizedBox(height: 46),
          V2Eyebrow(question.tag.toUpperCase(), size: 10, color: RtwV2Colors.clay),
          const SizedBox(height: 14),
          Text(question.prompt, style: v2Serif(31, height: 1.12, letterSpacing: -0.5)),
          const SizedBox(height: 30),
          _OptionButton(
            label: question.optA,
            selected: selected == 'a',
            onTap: () => onPick('a'),
          ),
          const SizedBox(height: 10),
          _OptionButton(
            label: question.optB,
            selected: selected == 'b',
            onTap: () => onPick('b'),
          ),
          if (index == 0) ...[
            const SizedBox(height: 22),
            Text(
              'No wrong answers — take your side.',
              textAlign: TextAlign.center,
              style: v2Sans(13, color: RtwV2Colors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        decoration: BoxDecoration(
          color: selected ? RtwV2Colors.blue.withValues(alpha: 0.10) : RtwV2Colors.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? RtwV2Colors.blue : RtwV2Colors.borderStrong,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: v2Sans(
            16,
            color: selected ? RtwV2Colors.blueTextDeep : RtwV2Colors.inkSoft,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PredictBeat extends StatelessWidget {
  const _PredictBeat({
    super.key,
    required this.question,
    required this.side,
    required this.pred,
    required this.onPred,
    required this.onLock,
    required this.onSkip,
  });

  final RoomDayQuestion question;
  final String side;
  final int pred;
  final ValueChanged<int> onPred;
  final VoidCallback onLock;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final label = side == 'a' ? question.optA : question.optB;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 66, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IntroHeader(label: 'How it works · the game', onSkip: onSkip),
          const SizedBox(height: 46),
          Text('You said $label.', style: v2Sans(15, color: RtwV2Colors.subText)),
          const SizedBox(height: 10),
          Text(
            'What share of people would say $label too?',
            style: v2Serif(29, height: 1.14, letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Think of the people in your life — your group chat, your family, your coworkers.',
            style: v2Sans(14, color: RtwV2Colors.muted, height: 1.5),
          ),
          const SizedBox(height: 34),
          Center(
            child: Text.rich(
              TextSpan(
                text: '$pred',
                style: v2Serif(60, color: RtwV2Colors.blueTextDeep, letterSpacing: -1.5),
                children: [
                  TextSpan(
                    text: '%',
                    style: v2Serif(28, color: RtwV2Colors.blueTextDeep),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _PredictSlider(value: pred, onChanged: onPred),
          const SizedBox(height: 30),
          V2Button(
            'Lock it in →',
            onPressed: onLock,
            padding: const EdgeInsets.symmetric(vertical: 16),
            radius: 16,
          ),
          const SizedBox(height: 14),
          Text(
            'That’s the whole game — the closer your read, the higher your score.',
            textAlign: TextAlign.center,
            style: v2Sans(13, color: RtwV2Colors.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _PredictSlider extends StatelessWidget {
  const _PredictSlider({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  void _set(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    onChanged(((local.dx / box.size.width) * 100).round().clamp(0, 100));
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (trackContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => _set(trackContext, details.globalPosition),
        onTapDown: (details) => _set(trackContext, details.globalPosition),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: RtwV2Colors.hairline,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (value / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [RtwV2Colors.gradBlue, RtwV2Colors.gradBlueLight],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloserBeat extends StatelessWidget {
  const _CloserBeat({
    super.key,
    required this.onCreate,
    required this.onJoin,
    required this.onDone,
  });

  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 66, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _IntroHeader(label: 'How it works · your people'),
          const SizedBox(height: 46),
          Text(
            'Who are your people?',
            style: v2Serif(33, height: 1.1, letterSpacing: -0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'You decide whose minds you’re reading. Your answers just joined '
            'The World — start a room to read your own crew.',
            style: v2Sans(14.5, color: RtwV2Colors.subText, height: 1.55),
          ),
          const SizedBox(height: 26),
          const _PeopleRow(
            glyph: _WayGlyph.rooms,
            color: RtwV2Colors.blue,
            title: 'Rooms',
            body: 'Your group chat, family or team. Three calls a day, reveal tomorrow.',
          ),
          const SizedBox(height: 12),
          const _PeopleRow(
            glyph: _WayGlyph.world,
            color: RtwV2Colors.green,
            title: 'The World',
            body: 'Everyone on Earth. Predicting unlocks as the game grows.',
            badge: 'SOON',
          ),
          const SizedBox(height: 30),
          V2Button(
            'Start a room →',
            onPressed: onCreate,
            padding: const EdgeInsets.symmetric(vertical: 17),
            radius: 16,
            fontSize: 16,
          ),
          const SizedBox(height: 10),
          _GhostCta(label: "Join with a friend's code", onTap: onJoin),
          const SizedBox(height: 2),
          _GhostCta(label: 'Not now', muted: true, onTap: onDone),
        ],
      ),
    );
  }
}

class _GhostCta extends StatelessWidget {
  const _GhostCta({required this.label, required this.onTap, this.muted = false});

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

enum _WayGlyph { rooms, world }

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
      case _WayGlyph.rooms:
        // Two heads + shoulders.
        canvas.drawCircle(const Offset(7, 8), 2.6, stroke);
        canvas.drawCircle(const Offset(13, 8), 2.6, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(2.5, 15.5)
            ..relativeCubicTo(0, -2.2, 1.8, -3.5, 4.5, -3.5),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(13, 12)
            ..relativeCubicTo(2.7, 0, 4.5, 1.3, 4.5, 3.5),
          stroke,
        );
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: CustomPaint(
              size: const Size(20, 20),
              painter: _WayGlyphPainter(glyph: glyph, color: color),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: v2Sans(15, color: RtwV2Colors.inkSoft, weight: FontWeight.w700),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: RtwV2Colors.green.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badge!,
                          style: v2Mono(8.5, color: RtwV2Colors.green, letterSpacing: 1),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(body, style: v2Sans(13, color: RtwV2Colors.subText, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
