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
///  1. Three fixed practice questions with the real swipe and prediction
///     mechanics, without the surrounding gameplay controls.
///  2. Lightweight scoring explainer.
///  3. "3 ways to play" closer with room CTAs.
/// The entire intro is practice. It uses the real interaction model without
/// submitting answers or predictions to a live room.
class OnboardingScreenV2 extends ConsumerStatefulWidget {
  const OnboardingScreenV2({super.key});

  @override
  ConsumerState<OnboardingScreenV2> createState() => _OnboardingScreenV2State();
}

/// A fixed, local-only practice deck. These never depend on the current World
/// day, and the answers and predictions are never written to Firestore.
const _tutorialQuestions = [
  RoomDayQuestion(
    qid: 'tutorial-money-happiness',
    prompt: 'Can money buy happiness?',
    optA: 'Yes',
    optB: 'No',
    tag: 'Money',
    shape: 'BELIEF',
    custom: false,
  ),
  RoomDayQuestion(
    qid: 'tutorial-kind-lie',
    prompt: "Is it ever okay to lie to protect someone's feelings?",
    optA: 'Yes',
    optB: 'No',
    tag: 'Ethics',
    shape: 'GREY',
    custom: false,
  ),
  RoomDayQuestion(
    qid: 'tutorial-no-social-media',
    prompt: 'Would the world be better without social media?',
    optA: 'Yes',
    optB: 'No',
    tag: 'Technology',
    shape: 'BELIEF',
    custom: false,
  ),
];

class _OnboardingScreenV2State extends ConsumerState<OnboardingScreenV2> {
  bool _started = false;
  bool _sawIntroSession = false;
  bool _sawScoringBeat = false;
  List<RoomPick>? _picks;

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

    if (!_started) _startIntro(rooms, _tutorialQuestions);
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
      padding: EdgeInsets.fromLTRB(26, v2ScreenTopInset(context) + 8, 26, 26),
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

class _IntroQuestionStep extends StatefulWidget {
  const _IntroQuestionStep({
    required this.session,
    required this.question,
    required this.rooms,
  });

  final PlaySession session;
  final RoomDayQuestion question;
  final RoomsController rooms;

  @override
  State<_IntroQuestionStep> createState() => _IntroQuestionStepState();
}

class _IntroQuestionStepState extends State<_IntroQuestionStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cueController;
  late final Animation<double> _cueOffset;
  bool _startedCue = false;
  bool _interacted = false;

  @override
  void initState() {
    super.initState();
    _cueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _cueOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -18,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -18,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 18,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 18,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 25,
      ),
    ]).animate(_cueController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startedCue) return;
    _startedCue = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _cueController.value = 1;
    } else {
      unawaited(_cueController.repeat(count: 2));
    }
  }

  void _stopCue() {
    if (_interacted) return;
    setState(() => _interacted = true);
    _cueController
      ..stop()
      ..value = 1;
  }

  @override
  void dispose() {
    _cueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final cardHeight = compact ? 290.0 : 330.0;
        final cardWidth = constraints.maxWidth < 330
            ? constraints.maxWidth
            : 330.0;
        return AnimatedBuilder(
          animation: _cueController,
          builder: (context, _) {
            final cueDx = _interacted ? 0.0 : _cueOffset.value;
            final dx = widget.session.dragX + cueDx;
            final borderColor = dx > RtwV2Motion.borderTintThreshold
                ? RtwV2Colors.blue
                : dx < -RtwV2Motion.borderTintThreshold
                ? RtwV2Colors.clay
                : RtwV2Colors.borderStrong;
            final cueStrength = (cueDx.abs() / 18).clamp(0.0, 1.0);
            return Column(
              children: [
                const Spacer(),
                GestureDetector(
                  onTapUp: (details) {
                    _stopCue();
                    widget.rooms.commitSide(
                      details.localPosition.dx < cardWidth / 2 ? 'b' : 'a',
                    );
                  },
                  onHorizontalDragStart: (_) {
                    _stopCue();
                    widget.rooms.cardDragStart();
                  },
                  onHorizontalDragUpdate: (details) =>
                      widget.rooms.cardDragUpdate(details.delta.dx),
                  onHorizontalDragEnd: (details) => widget.rooms.cardDragEnd(
                    details.velocity.pixelsPerSecond.dx,
                  ),
                  child: AnimatedContainer(
                    duration: widget.session.dragging
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
                              widget.question.prompt,
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
                                '← ${widget.question.optB}',
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
                                '${widget.question.optA} →',
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
                SizedBox(height: compact ? 18 : 24),
                Semantics(
                  label: 'Swipe left or right to choose your answer',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(-7 * cueStrength, 0),
                        child: Text(
                          '←',
                          style: v2Sans(
                            30,
                            color: cueDx < -2
                                ? RtwV2Colors.clayTextDeep
                                : RtwV2Colors.subText,
                            weight: FontWeight.w400,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Swipe left or right',
                        style: v2Sans(
                          14,
                          color: RtwV2Colors.subText,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Transform.translate(
                        offset: Offset(7 * cueStrength, 0),
                        child: Text(
                          '→',
                          style: v2Sans(
                            30,
                            color: cueDx > 2
                                ? RtwV2Colors.blueTextDeep
                                : RtwV2Colors.subText,
                            weight: FontWeight.w400,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            );
          },
        );
      },
    );
  }
}

class _IntroPredictionStep extends StatefulWidget {
  const _IntroPredictionStep({
    required this.session,
    required this.question,
    required this.rooms,
  });

  final PlaySession session;
  final RoomDayQuestion question;
  final RoomsController rooms;

  @override
  State<_IntroPredictionStep> createState() => _IntroPredictionStepState();
}

class _IntroPredictionStepState extends State<_IntroPredictionStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cueController;
  late final Animation<double> _cueOffset;
  bool _startedCue = false;
  bool _selected = false;

  @override
  void initState() {
    super.initState();
    _cueController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _cueOffset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -24,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -24,
          end: 24,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 24,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 25,
      ),
    ]).animate(_cueController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startedCue) return;
    _startedCue = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _cueController.value = 1;
    } else {
      unawaited(_cueController.repeat(count: 2));
    }
  }

  void _updatePrediction(double fraction) {
    if (!_selected) {
      setState(() => _selected = true);
      _cueController
        ..stop()
        ..value = 1;
    }
    widget.rooms.meterUpdate(fraction);
  }

  @override
  void dispose() {
    _cueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sideLabel = widget.session.side == 'a'
        ? widget.question.optA
        : widget.question.optB;
    final isLast = widget.session.idx + 1 >= widget.session.deck.length;
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
              _selected ? '${widget.session.pred}%' : '-',
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
            Text(
              'Drag to make your prediction',
              textAlign: TextAlign.center,
              style: v2Sans(
                14,
                color: RtwV2Colors.subText,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _cueController,
                builder: (context, child) => Center(
                  child: Transform.translate(
                    offset: Offset(_selected ? 0 : _cueOffset.value, 0),
                    child: child,
                  ),
                ),
                child: Text(
                  '↓',
                  style: v2Sans(
                    30,
                    color: RtwV2Colors.subText,
                    weight: FontWeight.w400,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            PredictionAgreementMeter(
              percent: widget.session.pred,
              people: 0,
              onUpdate: _updatePrediction,
              height: compact ? 64 : 72,
              infinite: true,
              showSelection: _selected,
            ),
            SizedBox(height: compact ? 14 : 20),
            V2Button(
              widget.rooms.submitting
                  ? 'Submitting...'
                  : !_selected
                  ? 'Choose a prediction'
                  : isLast
                  ? 'Lock in ${widget.session.pred}% →'
                  : 'Lock in ${widget.session.pred}% · next →',
              onPressed: widget.rooms.submitting || !_selected
                  ? null
                  : () => unawaited(widget.rooms.lockCurrent()),
              padding: const EdgeInsets.symmetric(vertical: 17),
              radius: 16,
              fontSize: 16,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: widget.rooms.changeAnswer,
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

class _ScoringBeat extends StatefulWidget {
  const _ScoringBeat({required this.onNext});

  final VoidCallback onNext;

  @override
  State<_ScoringBeat> createState() => _ScoringBeatState();
}

class _ScoringBeatState extends State<_ScoringBeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;
  bool _startedReveal = false;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startedReveal) return;
    _startedReveal = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _revealController.value = 1;
    } else {
      unawaited(_revealController.forward());
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 780;
        final topPadding = v2ScreenTopInset(context) + (compact ? 8.0 : 14.0);
        final bottomPadding = compact ? 24.0 : 34.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(26, topPadding, 26, bottomPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - topPadding - bottomPadding)
                  .clamp(0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const V2Eyebrow('How scoring works', letterSpacing: 1.8),
                    SizedBox(height: compact ? 18 : 26),
                    _TimedReveal(
                      animation: _revealController,
                      start: 0,
                      end: 0.18,
                      child: Text(
                        'Closer predictions score more.',
                        style: v2Serif(
                          compact ? 34 : 40,
                          height: 1.04,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 14 : 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ScoreExample(
                        animation: _revealController,
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 12 : 24),
                      _TimedReveal(
                        animation: _revealController,
                        start: 0.76,
                        end: 0.94,
                        child: Text(
                          "It's not about being right.\nIt's about reading the room.",
                          textAlign: TextAlign.center,
                          style: v2Serif(
                            compact ? 21 : 26,
                            height: 1.16,
                            letterSpacing: -0.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'This tutorial was practice. Nothing was scored.',
                      textAlign: TextAlign.center,
                      style: v2Sans(
                        13,
                        color: RtwV2Colors.subText,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 28),
                    V2Button(
                      'Continue →',
                      onPressed: widget.onNext,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      radius: 16,
                      fontSize: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScoreExample extends StatelessWidget {
  const _ScoreExample({required this.animation, required this.compact});

  final Animation<double> animation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final resultProgress = _intervalProgress(animation.value, 0.2, 0.44);
        final predictionProgress = _intervalProgress(
          animation.value,
          0.42,
          0.66,
        );
        final differenceProgress = _intervalProgress(
          animation.value,
          0.62,
          0.8,
        );
        return Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 20,
            compact ? 15 : 20,
            compact ? 16 : 20,
            compact ? 14 : 18,
          ),
          decoration: BoxDecoration(
            color: RtwV2Colors.card,
            border: Border.all(color: RtwV2Colors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              const V2Eyebrow('Example round', letterSpacing: 1.5),
              SizedBox(height: compact ? 9 : 14),
              Opacity(
                opacity: resultProgress,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - resultProgress)),
                  child: Text.rich(
                    TextSpan(
                      style: v2Sans(
                        15,
                        color: RtwV2Colors.ink,
                        weight: FontWeight.w600,
                      ),
                      children: const [
                        TextSpan(
                          text: '65%',
                          style: TextStyle(
                            color: RtwV2Colors.clayTextDeep,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(text: ' of people chose Yes'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              SizedBox(height: compact ? 10 : 14),
              SizedBox(
                height: compact ? 70 : 78,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 42,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6E0D3),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.65 * resultProgress,
                          child: Container(
                            color: RtwV2Colors.clay.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Align(
                        alignment: const Alignment(-0.5, -1),
                        child: Opacity(
                          opacity: predictionProgress,
                          child: Container(
                            width: 4,
                            height: 52,
                            decoration: BoxDecoration(
                              color: RtwV2Colors.blue,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Align(
                        alignment: const Alignment(-0.5, 0),
                        child: Opacity(
                          opacity: predictionProgress,
                          child: SizedBox(
                            width: 116,
                            child: Text(
                              'You predicted 25%',
                              textAlign: TextAlign.center,
                              style: v2Mono(
                                9,
                                color: RtwV2Colors.blueTextDeep,
                                weight: FontWeight.w600,
                                letterSpacing: 0.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 3 : 8),
              Opacity(
                opacity: differenceProgress,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - differenceProgress)),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: compact ? 8 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: RtwV2Colors.clay.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '40 points apart',
                          style: v2Sans(
                            13,
                            color: RtwV2Colors.clayTextDeep,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                      Text(
                        'Your Read Score rises or falls based on how your prediction ranks in the room.',
                        textAlign: TextAlign.center,
                        style: v2Sans(
                          13,
                          color: RtwV2Colors.subText,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimedReveal extends StatelessWidget {
  const _TimedReveal({
    required this.animation,
    required this.start,
    required this.end,
    required this.child,
  });

  final Animation<double> animation;
  final double start;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = _intervalProgress(animation.value, start, end);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }
}

double _intervalProgress(double value, double start, double end) {
  final raw = ((value - start) / (end - start)).clamp(0.0, 1.0);
  return Curves.easeOutCubic.transform(raw);
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
        final topPadding = v2ScreenTopInset(context) + (compact ? 8.0 : 14.0);
        const bottomPadding = 24.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(26, topPadding, 26, bottomPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - topPadding - bottomPadding)
                  .clamp(0, double.infinity),
            ),
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
                SizedBox(height: compact ? 24 : 38),
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
                SizedBox(height: compact ? 24 : 38),
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
