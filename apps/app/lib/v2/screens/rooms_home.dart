import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../sheets/room_sheets.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// ROOMS (home) — v2 prototype lines 30-112.
class RoomsHomeScreen extends ConsumerWidget {
  const RoomsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsControllerProvider);
    final profile = ref.watch(rtwControllerProvider);
    final visible = rooms.visibleRooms;

    return V2Scaffold(
      location: '/rooms',
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          22,
          _topPadding(context),
          22,
          30,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Wordmark(),
                _AvatarButton(
                  initial: profile.displayName.isEmpty
                      ? '?'
                      : profile.displayName.substring(0, 1).toUpperCase(),
                  avatarIndex: profile.avatarIndex,
                  onTap: () => context.go('/profile'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _WorldHero(rooms: rooms),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const V2Eyebrow('Your rooms', size: 11, letterSpacing: 1.6),
                GestureDetector(
                  onTap: () => showCreateRoomSheet(context, ref),
                  child: Text(
                    '+ New room',
                    style: v2Sans(13, color: RtwV2Colors.blue, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (visible.isEmpty && !rooms.loadingRooms)
              _EmptyRooms(onCreate: () => showCreateRoomSheet(context, ref))
            else
              Column(
                children: [
                  for (final binding in visible) ...[
                    _RoomCard(binding: binding),
                    if (binding != visible.last) const SizedBox(height: 12),
                  ],
                ],
              ),
            const SizedBox(height: 14),
            _JoinDashedButton(onTap: () => showJoinRoomSheet(context, ref)),
          ],
        ),
      ),
    );
  }

  double _topPadding(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return safeTop > 40 ? safeTop + 16 : 60;
  }
}

class _Wordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'read the world',
        style: v2Serif(21, letterSpacing: -0.5),
        children: [
          TextSpan(text: '.', style: v2Serif(21, color: RtwV2Colors.clay)),
        ],
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    required this.initial,
    required this.avatarIndex,
    required this.onTap,
  });

  final String initial;
  final int avatarIndex;
  final VoidCallback onTap;

  static const _avatarColors = [
    RtwV2Colors.blue,
    RtwV2Colors.clay,
    RtwV2Colors.green,
    RtwV2Colors.inkColorOption,
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _avatarColors[avatarIndex % _avatarColors.length],
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: v2Sans(16, color: Colors.white, weight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// World room hero — ink card, blue radial glow, live progress to the goal.
class _WorldHero extends StatelessWidget {
  const _WorldHero({required this.rooms});

  final RoomsController rooms;

  @override
  Widget build(BuildContext context) {
    final world = rooms.worldRoom;
    final players = world?.memberCount ?? 0;
    final goal = world?.worldGoal ?? 5000;
    final pct = goal > 0 ? ((players / goal) * 100).round() : 0;
    final remaining = (goal - players).clamp(0, goal);
    final unlocked = rooms.worldPredictionsUnlocked;

    return GestureDetector(
      onTap: () => context.go('/rooms/$worldRoomId'),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: RtwV2Colors.ink,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            // radial-gradient(120% 90% at 80% -10%, blue 55%, transparent 60%)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.6, -1.2),
                    radius: 1.2,
                    colors: [
                      RtwV2Colors.gradBlue.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.6],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const V2Eyebrow(
                        'The World',
                        color: RtwV2Colors.onDarkBlue,
                        letterSpacing: 1.6,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          unlocked ? 'OPEN' : 'OPEN · ANSWER ONLY',
                          style: v2Mono(10, color: const Color(0xFFB8B2A4), letterSpacing: 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Read all of humanity.',
                    style: v2Serif(
                      28,
                      color: RtwV2Colors.onDarkPaper,
                      height: 1.06,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    unlocked
                        ? 'Predicting is live. Read the whole world, one question at a time.'
                        : 'Answering is always open. Predicting unlocks once the game hits ${_formatCount(goal)} players.',
                    style: v2Sans(13.5, color: const Color(0xFFC7C1B3), height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: _formatCount(players),
                          style: v2Serif(26, color: RtwV2Colors.onDarkPaper),
                          children: [
                            TextSpan(
                              text: ' / ${_formatCount(goal)}',
                              style: v2Serif(15, color: const Color(0xFF8E887C)),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$pct% there',
                        style: v2Mono(11, color: RtwV2Colors.onDarkBlue, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      height: 9,
                      color: RtwV2Colors.inkColorOption,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (pct / 100).clamp(0.0, 1.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [RtwV2Colors.gradBlue, RtwV2Colors.gradBlueLight],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!unlocked) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_formatCount(remaining)} more players to unlock predicting.',
                      style: v2Sans(12, color: const Color(0xFF8E887C)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  V2Button(
                    'Answer world questions →',
                    background: Colors.white,
                    foreground: RtwV2Colors.ink,
                    fontWeight: FontWeight.w700,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    onPressed: () {
                      rooms.startRoomPlay(worldRoomId);
                      if (rooms.play != null) context.go('/today/play');
                    },
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => showInviteSheet(context, rooms, worldRoomId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Invite friends to help unlock predicting',
                        textAlign: TextAlign.center,
                        style: v2Sans(
                          13,
                          color: const Color(0xFF9EC7FE), // oklch(0.82 0.09 256)
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatCount(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

class _RoomCard extends ConsumerWidget {
  const _RoomCard({required this.binding});

  final RoomBinding binding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = binding.room!;
    final played = binding.played;
    final isSolo = room.isSolo;
    final streak = binding.me?.streak ?? 0;
    final rank = _rankLabel(binding);
    final sub = isSolo
        ? 'Just you, for now'
        : '${room.memberCount} members · $streak day streak';
    final statusLabel = played
        ? '✓ Locked in'
        : isSolo
            ? "Answer today's 3 →"
            : "Play today's 3 →";

    return GestureDetector(
      // Prototype openRoom: an unseen reveal shows once before the detail.
      onTap: () => context.go(
        binding.hasUnseenReveal ? '/rooms/${room.id}/reveal' : '/rooms/${room.id}',
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: RtwV2Colors.card,
          border: Border.all(color: RtwV2Colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Row(
              children: [
                RoomIcon(room: room),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              room.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: v2Serif(19),
                            ),
                          ),
                          if (room.tier != RoomTier.normal) ...[
                            const SizedBox(width: 8),
                            TierChip(tier: room.tier),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(sub, style: v2Sans(12.5, color: RtwV2Colors.muted)),
                    ],
                  ),
                ),
                if (!played && !binding.todaySeen) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: RtwV2Colors.blue,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      'NEW',
                      style: v2Mono(9, color: Colors.white, weight: FontWeight.w600, letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text('›', style: v2Serif(15, color: RtwV2Colors.faint)),
              ],
            ),
            const SizedBox(height: 15),
            const V2Hairline(),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: played
                      ? null
                      : () {
                          final rooms = ref.read(roomsControllerProvider);
                          rooms.startRoomPlay(room.id);
                          if (rooms.play != null) context.go('/today/play');
                        },
                  child: Text(
                    statusLabel,
                    style: v2Sans(
                      13,
                      color: played ? RtwV2Colors.green : RtwV2Colors.blue,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                if (rank != null)
                  Text(rank, style: v2Mono(11, color: RtwV2Colors.muted, letterSpacing: 0.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _rankLabel(RoomBinding binding) {
    final room = binding.room!;
    if (room.isSolo || room.isWorld) return null;
    return null; // Rank is computed on Room Detail from the members stream.
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RtwV2Colors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.grid_view_rounded, size: 20, color: RtwV2Colors.blue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No rooms yet', style: v2Serif(19)),
                    const SizedBox(height: 3),
                    Text(
                      "Start a room for your crew, or join with a friend's code.",
                      style: v2Sans(13, color: RtwV2Colors.subText, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          V2Button('Create your first room →', onPressed: onCreate),
        ],
      ),
    );
  }
}

class _JoinDashedButton extends StatelessWidget {
  const _JoinDashedButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          alignment: Alignment.center,
          child: Text(
            'Have a code? Join a room',
            style: v2Sans(14, color: const Color(0xFF5C584F), weight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = RtwV2Colors.knobTrackOff
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
