import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../rooms_controller.dart';
import '../sheets/room_sheets.dart';
import '../widgets_v2.dart';

/// Full-screen room history (calendar + category + question cards). A route so
/// the World's answer flow can push over it and Exit can pop straight back.
class RoomHistoryScreen extends ConsumerWidget {
  const RoomHistoryScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsControllerProvider);
    final binding = rooms.bindingFor(roomId);
    final room = binding?.room;
    final isWorld = roomId == worldRoomId;
    if (room == null) {
      if (!rooms.loadingRooms && !isWorld) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/rooms');
        });
      }
      return V2Scaffold(
        location: '/rooms/$roomId/history',
        showNav: false,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return V2Scaffold(
      location: '/rooms/$roomId/history',
      showNav: false,
      wideWidth: 760,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, v2ScreenTopInset(context), 22, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                V2BackButton(
                  label: room.name,
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.go('/rooms/$roomId'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RoomHistoryView(rooms: rooms, room: room, asScreen: true),
          ],
        ),
      ),
    );
  }
}
