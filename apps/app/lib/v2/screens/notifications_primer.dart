import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../tokens_v2.dart';
import '../widgets_v2.dart';

/// One-time primer nudging new (mobile) readers to enable notifications right
/// after onboarding. Concise, not framed as a "daily reminder" chore [Mike].
class NotificationsPrimerScreen extends ConsumerStatefulWidget {
  const NotificationsPrimerScreen({super.key});

  @override
  ConsumerState<NotificationsPrimerScreen> createState() =>
      _NotificationsPrimerScreenState();
}

class _NotificationsPrimerScreenState
    extends ConsumerState<NotificationsPrimerScreen> {
  bool _busy = false;

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = ref.read(rtwControllerProvider);
    // Only turn on if it isn't already (this triggers the OS permission sheet).
    if (!controller.dailyReminder) {
      await controller.toggleReminder();
    }
    _finish();
  }

  void _finish() {
    ref.read(roomsControllerProvider).markNotifPrimerSeen();
    if (mounted) context.go('/rooms');
  }

  @override
  Widget build(BuildContext context) {
    return V2Scaffold(
      location: '/notifications',
      showNav: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(28, v2ScreenTopInset(context), 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RtwV2Colors.meterBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 32,
                  color: RtwV2Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Don't miss a read.",
              textAlign: TextAlign.center,
              style: v2Serif(32, height: 1.08, letterSpacing: -0.6),
            ),
            const SizedBox(height: 14),
            Text(
              'Get a nudge the moment new questions are live.',
              textAlign: TextAlign.center,
              style: v2Sans(16, color: RtwV2Colors.subText, height: 1.5),
            ),
            const Spacer(),
            V2Button(
              _busy ? 'Turning on…' : 'Turn on notifications',
              onPressed: _busy ? null : () => unawaited(_enable()),
              padding: const EdgeInsets.symmetric(vertical: 18),
              radius: 16,
              fontSize: 16,
            ),
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: _busy ? null : _finish,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Maybe later',
                    style: v2Sans(14, color: RtwV2Colors.subText),
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
