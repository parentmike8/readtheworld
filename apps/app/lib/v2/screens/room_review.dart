import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../models_v2.dart';
import '../rooms_controller.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// Read-only review of the caller's submitted answers for the current day,
/// reached from "View or modify your answers". Editing is one tap away but
/// nothing changes until the reader chooses to edit [Mike].
class RoomReviewScreen extends ConsumerWidget {
  const RoomReviewScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsControllerProvider);
    final binding = rooms.bindingFor(roomId);
    final room = binding?.room;
    final isWorld = room?.isWorld ?? roomId == worldRoomId;
    final day = isWorld ? rooms.worldToday : binding?.today;
    final answer = binding?.myTodayAnswer;
    final roomName = room?.name ?? 'your room';

    // Nothing submitted yet — nothing to review; go answer instead.
    if (day == null || answer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/rooms/$roomId');
      });
      return V2Scaffold(
        location: '/rooms/$roomId/review',
        showNav: false,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final rows = <({RoomDayQuestion question, RoomPick pick})>[];
    for (final question in day.answerableQuestions) {
      final pick = answer.pickFor(question.qid);
      if (pick != null) rows.add((question: question, pick: pick));
    }

    return V2Scaffold(
      location: '/rooms/$roomId/review',
      showNav: false,
      wideWidth: 560,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, v2ScreenTopInset(context), 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/rooms/$roomId'),
                  child: Text(
                    '← $roomName',
                    style: v2Sans(14, color: RtwV2Colors.subText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            V2Eyebrow(
              'Your reads · $roomName',
              size: 11,
              color: RtwV2Colors.clay,
              letterSpacing: 1.6,
            ),
            const SizedBox(height: 10),
            Text(
              'Review your answers.',
              style: v2Serif(30, height: 1.06, letterSpacing: -0.5),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in rows) ...[
                      _ReviewCard(
                        question: row.question,
                        pick: row.pick,
                        room: room,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            V2Button(
              'Edit answers →',
              onPressed: () {
                rooms.startRoomPlay(roomId, entryRoute: '/rooms/$roomId/review');
                if (rooms.play != null) context.go('/today/play');
              },
              padding: const EdgeInsets.symmetric(vertical: 17),
              radius: 16,
              fontSize: 16,
            ),
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: () => context.go('/rooms/$roomId'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Done',
                    style: v2Sans(13, color: RtwV2Colors.subText),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.question,
    required this.pick,
    required this.room,
  });

  final RoomDayQuestion question;
  final RoomPick pick;
  final RtwRoom? room;

  @override
  Widget build(BuildContext context) {
    final sideA = pick.side == 'a';
    final sideLabel = sideA ? question.optA : question.optB;
    final sideColor = sideA ? RtwV2Colors.blue : RtwV2Colors.clay;
    final prediction = pick.prediction;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: RtwV2Colors.card,
        border: Border.all(color: RtwV2Colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V2Eyebrow(question.tag, letterSpacing: 1.2),
          const SizedBox(height: 8),
          Text(
            question.prompt,
            style: v2Serif(18, color: const Color(0xFF2C2A24), height: 1.28),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: sideColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'You said ',
                    style: v2Sans(13.5, color: RtwV2Colors.subText),
                    children: [
                      TextSpan(
                        text: sideLabel,
                        style: v2Sans(13.5, color: sideColor, weight: FontWeight.w700),
                      ),
                      if (prediction != null)
                        TextSpan(
                          text: '  @ $prediction% agree',
                          style: v2Sans(13.5, color: RtwV2Colors.muted),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
