import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// WORLD LEADERBOARD — how you read all of humanity versus everyone you share
/// a room with, ranked by World Read Score. Scores sit level at 1500 until the
/// first World questions cross their thresholds and reveal.
class WorldLeaderboardScreen extends ConsumerStatefulWidget {
  const WorldLeaderboardScreen({super.key});

  @override
  ConsumerState<WorldLeaderboardScreen> createState() =>
      _WorldLeaderboardScreenState();
}

class _WorldLeaderboardScreenState
    extends ConsumerState<WorldLeaderboardScreen> {
  late Future<List<WorldLeaderRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(roomsControllerProvider).loadWorldLeaderboard();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.read(roomsControllerProvider).uid;
    return V2Scaffold(
      location: '/world/leaderboard',
      wideWidth: 760,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 54, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/rooms/$worldRoomId'),
                  child: Text(
                    '← The World',
                    style: v2Sans(14, color: RtwV2Colors.subText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const V2Eyebrow('World leaderboard', letterSpacing: 1.6),
            const SizedBox(height: 10),
            Text(
              'The world stage',
              style: v2Serif(30, height: 1.06, letterSpacing: -0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'How well you read all of humanity, against everyone you share a '
              'room with.',
              style: v2Sans(15, color: RtwV2Colors.subText, height: 1.5),
            ),
            const SizedBox(height: 22),
            FutureBuilder<List<WorldLeaderRow>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final rows = snapshot.data ?? const <WorldLeaderRow>[];
                if (rows.isEmpty) {
                  return _EmptyBoard();
                }
                return _Board(rows: rows, myUid: myUid);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.rows, required this.myUid});

  final List<WorldLeaderRow> rows;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              color: row.uid == myUid
                  ? RtwV2Colors.meterBlue.withValues(alpha: 0.08)
                  : null,
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text('#${row.rank}', style: v2Mono(13, letterSpacing: 0)),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: row.uid == myUid
                          ? RtwV2Colors.blue
                          : const Color(0xFFD8D2C5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      row.uid == myUid ? 'You' : row.displayName,
                      style: v2Sans(
                        15,
                        color: RtwV2Colors.inkSoft,
                        weight: row.uid == myUid ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  Text('${row.readScore}', style: v2Serif(17)),
                ],
              ),
            ),
            if (index < rows.length - 1) const V2Hairline(),
          ],
        ],
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        'No peers yet. Join or invite people into a room, and you\'ll see how '
        'your World reads stack up against theirs here.',
        style: v2Sans(14, color: const Color(0xFF5C584F), height: 1.5),
      ),
    );
  }
}
