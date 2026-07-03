import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';
import 'play_surface.dart' show revealLabelFor;

/// ROOM REVEAL — one-time animated score reveal on first open after close
/// (prototype lines 114-151; 1500ms ease-out-cubic, staggered rows).
class RoomRevealScreen extends ConsumerStatefulWidget {
  const RoomRevealScreen({super.key, required this.roomId, this.fromToday = false});

  final String roomId;
  final bool fromToday;

  @override
  ConsumerState<RoomRevealScreen> createState() => _RoomRevealScreenState();
}

class _RoomRevealScreenState extends ConsumerState<RoomRevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: RtwV2Motion.roomReveal,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  RoomRevealData? reveal;
  bool _loading = false;
  String? _attemptedKey;

  Future<void> _load(String dailyKey) async {
    _loading = true;
    _attemptedKey = dailyKey;
    final rooms = ref.read(roomsControllerProvider);
    final data = await rooms.loadRoomReveal(widget.roomId);
    _loading = false;
    if (!mounted) return;
    setState(() => reveal = data);
    if (data == null) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
    unawaited(rooms.markRevealSeen(widget.roomId));
  }

  void _syncLoad(String? lastClosedDailyKey) {
    if (lastClosedDailyKey == null || _loading) return;
    if (_attemptedKey == lastClosedDailyKey) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(lastClosedDailyKey);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    if (widget.fromToday) {
      context.go('/today');
    } else {
      context.go('/rooms/${widget.roomId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsControllerProvider);
    final binding = rooms.bindingFor(widget.roomId);
    final room = binding?.room;
    final me = binding?.me;
    final data = reveal;
    _syncLoad(room?.lastClosedDailyKey);

    return V2Scaffold(
      wideWidth: 640,
      location: '/rooms/${widget.roomId}/reveal',
      showNav: false,
      backgroundColor: RtwV2Colors.ink,
      child: data == null || room == null
          ? const Center(
              child: CircularProgressIndicator(color: RtwV2Colors.onDarkPaper),
            )
          : AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final t = _t.value;
                final delta = me?.lastDelta ?? 0;
                final finalScore = me?.roomScore ?? 1500;
                final curScore = ((finalScore - delta) + delta * t).round();
                final deltaIn = t > 0.45;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          RoomIcon(room: room, size: 48),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_whenWord(data.dailyKey)} IN',
                                style: v2Mono(10, color: const Color(0xFF8E887C), letterSpacing: 1.8),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                room.name,
                                style: v2Serif(23, color: RtwV2Colors.onDarkPaper, height: 1.1),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Text(
                        'YOUR READ SCORE',
                        textAlign: TextAlign.center,
                        style: v2Mono(11, color: const Color(0xFF8E887C), letterSpacing: 2),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _thousands(curScore),
                            style: v2Serif(72, color: RtwV2Colors.onDarkPaper, height: 1),
                          ),
                          const SizedBox(width: 12),
                          AnimatedOpacity(
                            opacity: deltaIn ? 1 : 0,
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              '${delta >= 0 ? '+' : ''}$delta',
                              style: v2Mono(
                                16,
                                color: delta >= 0
                                    ? RtwV2Colors.deltaUpBright
                                    : RtwV2Colors.deltaDownBright,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "FROM ${_whenWord(data.dailyKey)}'S CALLS",
                        textAlign: TextAlign.center,
                        style: v2Mono(10, color: const Color(0xFF8E887C), letterSpacing: 1),
                      ),
                      const SizedBox(height: 36),
                      Text(
                        'HOW YOU READ IT',
                        style: v2Mono(10, color: const Color(0xFF8E887C), letterSpacing: 1.6),
                      ),
                      const SizedBox(height: 12),
                      for (final (index, question) in data.day.activeQuestions.indexed) ...[
                        _RevealQuestionRow(
                          question: question,
                          day: data.day,
                          answer: data.myAnswer,
                          // Stagger: local = clamp((t - 0.35 - i*0.14) / 0.4, 0, 1)
                          local: ((t - 0.35 - index * 0.14) / 0.4).clamp(0.0, 1.0),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 16),
                      V2Button(
                        "Today's questions are ready →",
                        background: RtwV2Colors.onDarkPaper,
                        foreground: RtwV2Colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        radius: 16,
                        onPressed: _continue,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _whenWord(String dailyKey) {
    final label = revealLabelFor(dailyKey);
    return label.replaceAll("'S REVEAL", '').replaceAll(' REVEAL', '');
  }
}

String _thousands(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

class _RevealQuestionRow extends StatelessWidget {
  const _RevealQuestionRow({
    required this.question,
    required this.day,
    required this.answer,
    required this.local,
  });

  final RoomDayQuestion question;
  final RoomDay day;
  final RoomAnswer? answer;
  final double local;

  @override
  Widget build(BuildContext context) {
    final result = day.resultFor(question.qid);
    final pick = answer?.pickFor(question.qid);
    if (result == null) return const SizedBox.shrink();
    final youLabel = pick == null
        ? '—'
        : pick.side == 'a'
            ? question.optA
            : question.optB;
    final roomPct = pick == null || pick.side == 'a' ? result.aPct : 100 - result.aPct;
    final guess = pick?.prediction;
    final score = answer?.accuracies[question.qid];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2825), // oklch(0.28 0.008 60)
        border: Border.all(color: const Color(0xFF3C3733)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                question.tag.toUpperCase(),
                style: v2Mono(10, color: const Color(0xFF8E887C), letterSpacing: 1.2),
              ),
              if (score != null)
                Text.rich(
                  TextSpan(
                    text: '${(score * local).round()}',
                    style: v2Mono(11, color: const Color(0xFFE8A686), letterSpacing: 0),
                    children: [
                      TextSpan(
                        text: '/100',
                        style: v2Mono(11, color: const Color(0xFF6E695E), letterSpacing: 0),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            question.prompt,
            style: v2Serif(17, color: RtwV2Colors.onDarkPaper, height: 1.28),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: const Color(0xFF47413D)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: ((roomPct * local) / 100).clamp(0.0, 1.0),
                      child: Container(color: RtwV2Colors.clay),
                    ),
                  ),
                  if (guess != null)
                    Align(
                      alignment: Alignment((guess / 100).clamp(0.0, 1.0) * 2 - 1, 0),
                      child: Opacity(
                        opacity: local,
                        child: Container(width: 2, color: RtwV2Colors.onDarkPaper),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  text: 'You said ',
                  style: v2Sans(12, color: const Color(0xFFB8B2A5)),
                  children: [
                    TextSpan(
                      text: youLabel,
                      style: v2Sans(12, color: RtwV2Colors.onDarkPaper, weight: FontWeight.w700),
                    ),
                    if (guess != null) TextSpan(text: ' · guessed $guess%'),
                  ],
                ),
              ),
              Text('Room $roomPct%', style: v2Sans(12, color: const Color(0xFF8E887C))),
            ],
          ),
        ],
      ),
    );
  }
}
