import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';
import 'play_surface.dart' show PlaySurface;

/// ONBOARDING — v2 prototype lines 641-763: welcome → practice-room intro →
/// Day 1 demo → next-day reveal → Day 2 demo → score payoff → World teaser.
/// The demo is entirely local; nothing writes to the server.
class OnboardingScreenV2 extends ConsumerStatefulWidget {
  const OnboardingScreenV2({super.key});

  @override
  ConsumerState<OnboardingScreenV2> createState() => _OnboardingScreenV2State();
}

enum _ObStep { welcome, roomIntro, day2Intro, day3, world }

/// Demo question days (prototype DEMO_DAYS — roomYes drives local scoring).
const _demoDays = <int, List<(String cat, String q, String optA, String optB, int roomYes)>>{
  1: [
    ('FOOD', 'Is a hot dog a sandwich?', 'Yes', 'No', 41),
    ('FOOD', 'Is pineapple on pizza good?', 'Yes', 'No', 58),
    ('FOOD', 'Is cereal a type of soup?', 'Yes', 'No', 19),
  ],
  2: [
    ('CULTURE', 'Is Die Hard a Christmas movie?', 'Yes', 'No', 63),
    ('EVERYDAY', 'Is it fine to wear socks with sandals?', 'Fine', 'Nope', 27),
    ('HONEST', 'Do you re-read your own texts after sending them?', 'Always', 'Never', 81),
  ],
};

const _demoFriends = ['Maya', 'Diego', 'Priya', 'Sam', 'Jordan', 'Robin', 'Theo'];

class _DemoRevealRow {
  const _DemoRevealRow({
    required this.cat,
    required this.q,
    required this.you,
    required this.pred,
    required this.roomYes,
    required this.score,
  });

  final String cat;
  final String q;
  final String you;
  final int pred;
  final int roomYes;
  final int score;
}

class _OnboardingScreenV2State extends ConsumerState<OnboardingScreenV2> {
  _ObStep step = _ObStep.welcome;
  List<_DemoRevealRow> day1Reveal = const [];
  List<_DemoRevealRow> day2Reveal = const [];
  int _awaitingDay = 0;

  int get day1Score => day1Reveal.fold(0, (sum, row) => sum + row.score);
  int get day2Score => day2Reveal.fold(0, (sum, row) => sum + row.score);

  List<RoomDayQuestion> _questionsFor(int day) => [
    for (final (index, entry) in _demoDays[day]!.indexed)
      RoomDayQuestion(
        qid: 'demo-$day-$index',
        prompt: entry.$2,
        optA: entry.$3,
        optB: entry.$4,
        tag: entry.$1,
        shape: 'TASTE',
        custom: false,
      ),
  ];

  void _startDay(int day) {
    _awaitingDay = day;
    ref.read(roomsControllerProvider).startDemoDay(day, _questionsFor(day));
  }

  /// Prototype demo scoring: 100 − |pred − actualForYourSide| × 1.3, floor 0.
  List<_DemoRevealRow> _scoreDay(int day, List<RoomPick> picks) {
    final questions = _demoDays[day]!;
    return [
      for (final (index, pick) in picks.indexed)
        () {
          final entry = questions[index];
          final sideA = pick.side == 'a';
          final actual = sideA ? entry.$5 : 100 - entry.$5;
          final pred = pick.prediction ?? 50;
          final score = (100 - ((pred - actual).abs() * 1.3).round()).clamp(0, 100);
          return _DemoRevealRow(
            cat: entry.$1,
            q: entry.$2,
            you: sideA ? entry.$3 : entry.$4,
            pred: pred,
            roomYes: entry.$5,
            score: score,
          );
        }(),
    ];
  }

  void _finish() {
    ref.read(roomsControllerProvider).enterToday();
    context.go('/today');
  }

  void _consumeDemoResult(RoomsController rooms) {
    if (_awaitingDay == 0 || rooms.play != null) return;
    final day = _awaitingDay;
    _awaitingDay = 0;
    final picks = rooms.takeDemoPicks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (picks == null || picks.isEmpty) {
        _finish(); // Skipped mid-demo.
        return;
      }
      setState(() {
        if (day == 1) {
          day1Reveal = _scoreDay(1, picks);
          step = _ObStep.day2Intro;
        } else {
          day2Reveal = _scoreDay(2, picks);
          step = _ObStep.day3;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsControllerProvider);
    final session = rooms.play;
    if (session != null && session.mode == 'demo' && !session.atEnd) {
      return V2Scaffold(
        location: '/onboarding',
        showNav: false,
        child: PlaySurface(session: session),
      );
    }
    _consumeDemoResult(rooms);

    return V2Scaffold(
      location: '/onboarding',
      showNav: false,
      backgroundColor: step == _ObStep.world ? RtwV2Colors.ink : RtwV2Colors.paper,
      child: switch (step) {
        _ObStep.welcome => _Welcome(
          onStart: () => setState(() => step = _ObStep.roomIntro),
          onSkip: _finish,
        ),
        _ObStep.roomIntro => _RoomIntro(
          onStartDay1: () => _startDay(1),
          onSkip: _finish,
        ),
        _ObStep.day2Intro => _DayRecap(
          dayNumber: 2,
          revealDayLabel: 'DAY 1 · THE REVEAL',
          intro:
              'While you were away, The Group Chat finished Day 1. Reveals '
              "always land the next day, here's how you read it.",
          rows: day1Reveal,
          footer: _DayScorePill(label: 'Day 1 read score', delta: '+$day1Score'),
          ctaLabel: 'Now play Day 2 →',
          onCta: () => _startDay(2),
          onSkip: _finish,
        ),
        _ObStep.day3 => _Day3(
          day1Reveal: day1Reveal,
          day2Reveal: day2Reveal,
          day1Score: day1Score,
          day2Score: day2Score,
          onNext: () => setState(() => step = _ObStep.world),
        ),
        _ObStep.world => _WorldTeaser(rooms: rooms, onDone: _finish),
      },
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart, required this.onSkip});

  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 74, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              text: 'read the world',
              style: v2Serif(25, letterSpacing: -0.7),
              children: [
                TextSpan(text: '.', style: v2Serif(25, color: RtwV2Colors.clay)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'How well can you read your people?',
            style: v2Serif(37, height: 1.05, letterSpacing: -0.8),
          ),
          const SizedBox(height: 14),
          Text(
            'Guess how the people around you really answer. Points are for the '
            'read, not the opinion.',
            style: v2Sans(15.5, color: RtwV2Colors.subText, height: 1.5),
          ),
          const SizedBox(height: 32),
          const V2Eyebrow('Three ways to play', letterSpacing: 1.8),
          const SizedBox(height: 14),
          const _WayToPlay(
            icon: Icons.groups_outlined,
            color: RtwV2Colors.blue,
            title: 'Rooms',
            body: 'Your crew, group chat or family. Three calls a day.',
          ),
          const SizedBox(height: 12),
          const _WayToPlay(
            icon: Icons.play_arrow_rounded,
            color: RtwV2Colors.clay,
            title: 'Party',
            body: 'Pass one phone around the table. Read the group out loud.',
          ),
          const SizedBox(height: 12),
          const _WayToPlay(
            icon: Icons.public,
            color: RtwV2Colors.green,
            title: 'The World',
            body: 'Everyone, one question, one day. Read the whole world.',
            badge: 'SOON',
          ),
          const SizedBox(height: 28),
          V2Button(
            'See how it works →',
            onPressed: onStart,
            padding: const EdgeInsets.symmetric(vertical: 18),
            radius: 16,
            fontSize: 16,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: Text(
                'Skip the intro',
                style: v2Sans(14, color: RtwV2Colors.muted, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WayToPlay extends StatelessWidget {
  const _WayToPlay({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.badge,
  });

  final IconData icon;
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
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: v2Sans(15, color: RtwV2Colors.inkSoft, weight: FontWeight.w700)),
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
                const SizedBox(height: 2),
                Text(body, style: v2Sans(13, color: RtwV2Colors.subText, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomIntro extends StatelessWidget {
  const _RoomIntro({required this.onStartDay1, required this.onSkip});

  final VoidCallback onStartDay1;
  final VoidCallback onSkip;

  static const _friendColors = [
    RtwV2Colors.clay,
    RtwV2Colors.blue,
    RtwV2Colors.green,
    RtwV2Colors.purple,
    RtwV2Colors.teal,
    Color(0xFF60892C),
    Color(0xFFB9454C),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 66, 26, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: RtwV2Colors.clay,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('DEMO', style: v2Mono(10, color: Colors.white, letterSpacing: 1.6)),
              ),
              const SizedBox(width: 8),
              const V2Eyebrow('A practice room', size: 11, letterSpacing: 1.4),
            ],
          ),
          const SizedBox(height: 20),
          Text('Meet a room, on us.', style: v2Serif(34, height: 1.08, letterSpacing: -0.6)),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              text: 'This is ',
              style: v2Sans(15.5, color: RtwV2Colors.subText, height: 1.55),
              children: [
                TextSpan(
                  text: 'The Group Chat',
                  style: v2Sans(15.5, color: const Color(0xFF3F3C35), weight: FontWeight.w700),
                ),
                const TextSpan(text: ', made-up players so you can learn the ropes. Nothing here is real.'),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: RtwV2Colors.card,
              border: Border.all(color: RtwV2Colors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 44,
                  child: Stack(
                    children: [
                      for (final (index, name) in _demoFriends.indexed)
                        Positioned(
                          left: index * 34.0,
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _friendColors[index % _friendColors.length],
                              shape: BoxShape.circle,
                              border: Border.all(color: RtwV2Colors.paper, width: 2),
                            ),
                            child: Text(
                              name.substring(0, 1),
                              style: v2Serif(18, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text.rich(
                  TextSpan(
                    text: '${_demoFriends.length + 1} players',
                    style: v2Sans(14, color: const Color(0xFF3F3C35), weight: FontWeight.w700, height: 1.5),
                    children: [
                      TextSpan(
                        text: ': Maya, Diego, Priya and the rest of your pretend crew.',
                        style: v2Sans(14, color: RtwV2Colors.subText, weight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text.rich(
            TextSpan(
              text: "Swipe to make your call, then predict how the room answered. We'll run ",
              style: v2Sans(15, color: const Color(0xFF5C584F), height: 1.6),
              children: [
                TextSpan(
                  text: 'three days',
                  style: v2Sans(15, color: const Color(0xFF3F3C35), weight: FontWeight.w700),
                ),
                const TextSpan(text: ' and reveal your Read Score.'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          V2Button(
            'Start Day 1 →',
            onPressed: onStartDay1,
            padding: const EdgeInsets.symmetric(vertical: 18),
            radius: 16,
            fontSize: 16,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: Text(
                'Skip the demo',
                style: v2Sans(14, color: RtwV2Colors.muted, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRecap extends StatelessWidget {
  const _DayRecap({
    required this.dayNumber,
    required this.revealDayLabel,
    required this.intro,
    required this.rows,
    required this.footer,
    required this.ctaLabel,
    required this.onCta,
    required this.onSkip,
  });

  final int dayNumber;
  final String revealDayLabel;
  final String intro;
  final List<_DemoRevealRow> rows;
  final Widget footer;
  final String ctaLabel;
  final VoidCallback onCta;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 58, 24, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: V2Eyebrow('A new day', size: 11, letterSpacing: 2)),
          const SizedBox(height: 12),
          Center(
            child: Text('Day $dayNumber', style: v2Serif(50, height: 1, letterSpacing: -1)),
          ),
          const SizedBox(height: 12),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Text(
                intro,
                textAlign: TextAlign.center,
                style: v2Sans(14.5, color: RtwV2Colors.subText, height: 1.55),
              ),
            ),
          ),
          const SizedBox(height: 26),
          V2Eyebrow(revealDayLabel, letterSpacing: 1.6),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _DemoRevealCard(row: row),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          footer,
          const SizedBox(height: 20),
          V2Button(
            ctaLabel,
            onPressed: onCta,
            padding: const EdgeInsets.symmetric(vertical: 18),
            radius: 16,
            fontSize: 16,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: Text(
                'Skip the demo',
                style: v2Sans(14, color: RtwV2Colors.muted, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoRevealCard extends StatelessWidget {
  const _DemoRevealCard({required this.row});

  final _DemoRevealRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              V2Eyebrow(row.cat, size: 9, color: RtwV2Colors.clay, letterSpacing: 1.4),
              Text('+${row.score}', style: v2Serif(20, color: RtwV2Colors.blueTextDeep)),
            ],
          ),
          const SizedBox(height: 7),
          Text(row.q, style: v2Serif(17, color: const Color(0xFF2C2A24), height: 1.25)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 12,
              color: const Color(0xFFE6E0D3),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (row.roomYes / 100).clamp(0.0, 1.0),
                child: Container(color: RtwV2Colors.clay),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  text: 'You said ',
                  style: v2Sans(12, color: RtwV2Colors.subText),
                  children: [
                    TextSpan(
                      text: row.you,
                      style: v2Sans(12, color: const Color(0xFF244D82), weight: FontWeight.w700),
                    ),
                    TextSpan(text: ' · guessed ${row.pred}%'),
                  ],
                ),
              ),
              Text('${row.roomYes}% said Yes', style: v2Sans(12, color: RtwV2Colors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayScorePill extends StatelessWidget {
  const _DayScorePill({required this.label, required this.delta});

  final String label;
  final String delta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: RtwV2Colors.meterBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: v2Sans(13, color: const Color(0xFF5C584F))),
          const SizedBox(width: 10),
          Text(delta, style: v2Serif(24, color: RtwV2Colors.blueTextDeep)),
        ],
      ),
    );
  }
}

class _Day3 extends StatelessWidget {
  const _Day3({
    required this.day1Reveal,
    required this.day2Reveal,
    required this.day1Score,
    required this.day2Score,
    required this.onNext,
  });

  final List<_DemoRevealRow> day1Reveal;
  final List<_DemoRevealRow> day2Reveal;
  final int day1Score;
  final int day2Score;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: V2Eyebrow('A new day', size: 11, letterSpacing: 2)),
          const SizedBox(height: 12),
          Center(child: Text('Day 3', style: v2Serif(50, height: 1, letterSpacing: -1))),
          const SizedBox(height: 12),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 290),
              child: Text(
                "Yesterday's results are in. Here's how you read Day 2.",
                textAlign: TextAlign.center,
                style: v2Sans(14.5, color: RtwV2Colors.subText, height: 1.55),
              ),
            ),
          ),
          const SizedBox(height: 26),
          const V2Eyebrow('Day 2 · The reveal', letterSpacing: 1.6),
          const SizedBox(height: 12),
          for (final row in day2Reveal) ...[
            _DemoRevealCard(row: row),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: RtwV2Colors.ink,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                const V2Eyebrow('Your read score', color: Color(0xFF8E887C), letterSpacing: 1.8),
                const SizedBox(height: 6),
                Text(
                  '${day1Score + day2Score}',
                  style: v2Serif(60, color: RtwV2Colors.onDarkPaper, height: 1),
                ),
                const SizedBox(height: 8),
                Text(
                  'two days of reads, all in the demo',
                  style: v2Sans(13, color: const Color(0xFFC7C1B3)),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        Text('DAY 1', style: v2Mono(9, color: const Color(0xFF8E887C), letterSpacing: 1)),
                        const SizedBox(height: 3),
                        Text('+$day1Score', style: v2Serif(22, color: RtwV2Colors.onDarkPaper)),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      color: RtwV2Colors.inkColorOption,
                    ),
                    Column(
                      children: [
                        Text('DAY 2', style: v2Mono(9, color: const Color(0xFF8E887C), letterSpacing: 1)),
                        const SizedBox(height: 3),
                        Text('+$day2Score', style: v2Serif(22, color: RtwV2Colors.onDarkPaper)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Every point came from reading the room right, not from your own '
            "opinion. That's the whole game.",
            style: v2Sans(13.5, color: RtwV2Colors.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          V2Button(
            'One more thing →',
            onPressed: onNext,
            padding: const EdgeInsets.symmetric(vertical: 18),
            radius: 16,
            fontSize: 16,
          ),
        ],
      ),
    );
  }
}

class _WorldTeaser extends StatelessWidget {
  const _WorldTeaser({required this.rooms, required this.onDone});

  final RoomsController rooms;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final players = rooms.worldRoom?.memberCount ?? 0;
    final goal = rooms.worldRoom?.worldGoal ?? 5000;
    final pct = goal > 0 ? ((players / goal) * 100).round() : 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 80, 26, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const V2Eyebrow('One more thing', size: 11, color: RtwV2Colors.onDarkBlue, letterSpacing: 1.8),
          const SizedBox(height: 16),
          Text(
            "Then there's the whole world.",
            style: v2Serif(40, color: RtwV2Colors.onDarkPaper, height: 1.04, letterSpacing: -0.8),
          ),
          const SizedBox(height: 14),
          Text(
            'Rooms are just the start. The World Room pits your read against '
            'all of humanity, and it opens once enough people are playing.',
            style: v2Sans(15, color: const Color(0xFFC7C1B3), height: 1.55),
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: _thousands(players),
                        style: v2Serif(26, color: RtwV2Colors.onDarkPaper),
                        children: [
                          TextSpan(
                            text: ' / ${_thousands(goal)}',
                            style: v2Serif(15, color: const Color(0xFF8E887C)),
                          ),
                        ],
                      ),
                    ),
                    Text('$pct%', style: v2Mono(11, color: RtwV2Colors.onDarkBlue, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    height: 9,
                    color: RtwV2Colors.inkColorOption,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (pct / 100).clamp(0.0, 1.0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [RtwV2Colors.gradBlue, RtwV2Colors.gradBlueLight],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    text: "You're player ",
                    style: v2Sans(13, color: const Color(0xFFC7C1B3), height: 1.5),
                    children: [
                      TextSpan(
                        text: '#${_thousands(players + 1)}',
                        style: v2Sans(13, color: RtwV2Colors.onDarkPaper, weight: FontWeight.w700),
                      ),
                      const TextSpan(
                        text: '. Every friend you bring gets the World closer for everyone.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          V2Button(
            'Enter Read the World →',
            background: RtwV2Colors.onDarkPaper,
            foreground: RtwV2Colors.ink,
            fontWeight: FontWeight.w700,
            padding: const EdgeInsets.symmetric(vertical: 17),
            radius: 16,
            fontSize: 16,
            onPressed: onDone,
          ),
        ],
      ),
    );
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
