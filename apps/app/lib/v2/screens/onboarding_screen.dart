import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';
import 'play_surface.dart' show PlaySurface;

/// ONBOARDING — two beats, ~30 seconds, on the REAL play surface:
///  1. Today's three World questions played with the real mechanic — swipe
///     card, fling physics, prediction meter ("the people in your life").
///  2. "3 ways to play" closer with room CTAs.
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
    context.go('/rooms');
  }

  void _skip() {
    ref.read(roomsControllerProvider).markOnboarded();
    context.go('/today');
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
        child: PlaySurface(session: session),
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
          : _CloserBeat(
              onCreate: () => _finish(homeAction: 'create'),
              onJoin: () => _finish(homeAction: 'join'),
              onDone: () => _finish(),
            ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 66, 26, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const V2Eyebrow('How it works · your people', letterSpacing: 1.8),
          const SizedBox(height: 26),
          Text(
            '3 ways to play',
            style: v2Serif(40, height: 1.04, letterSpacing: -0.8),
          ),
          const SizedBox(height: 12),
          Text(
            'How well do you know your people?',
            style: v2Sans(15, color: RtwV2Colors.subText, height: 1.45),
          ),
          const SizedBox(height: 142),
          const _PeopleRow(
            glyph: _WayGlyph.party,
            color: RtwV2Colors.clay,
            title: 'Party',
            body: 'In the room with you',
          ),
          const SizedBox(height: 26),
          const _PeopleRow(
            glyph: _WayGlyph.rooms,
            color: RtwV2Colors.blue,
            title: 'Rooms',
            body: 'Friends, family or coworkers\n3 questions every 24 hours',
          ),
          const SizedBox(height: 26),
          const _PeopleRow(
            glyph: _WayGlyph.world,
            color: RtwV2Colors.green,
            title: 'The World',
            body: 'Everyone, everywhere\n3 questions every 24 hours',
            badge: 'SOON',
          ),
          const SizedBox(height: 136),
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
