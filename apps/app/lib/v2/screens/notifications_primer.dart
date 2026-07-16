import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _denied = false;
  String? _error;

  static bool get _canOpenSettings =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _enable() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(rtwControllerProvider);
    // Only turn on if it isn't already (this triggers the OS permission sheet).
    if (!controller.dailyReminder) {
      await controller.toggleReminder();
    }
    // Any failed enable stays on this screen. Permission denial gets the
    // Settings path; token or network failures remain retryable and visible
    // instead of silently advancing with reminders still off.
    if (mounted && !controller.dailyReminder) {
      setState(() {
        _busy = false;
        _denied = controller.notificationsDenied;
        _error = controller.lastError ?? 'Notifications could not be enabled.';
      });
      return;
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
              _denied
                  ? (_canOpenSettings
                        ? 'Notifications are off for Read the World. Turn them on in iOS Settings to get the nudge.'
                        : 'Notifications are off for Read the World. Turn them on in your device settings to get the nudge.')
                  : 'Get a nudge the moment new questions are live.',
              textAlign: TextAlign.center,
              style: v2Sans(16, color: RtwV2Colors.subText, height: 1.5),
            ),
            if (_error != null && !_denied) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: v2Sans(13, color: RtwV2Colors.danger, height: 1.45),
              ),
            ],
            const Spacer(),
            if (_denied && _canOpenSettings)
              V2Button(
                'Open iOS Settings',
                onPressed: () => launchUrl(Uri.parse('app-settings:')),
                padding: const EdgeInsets.symmetric(vertical: 18),
                radius: 16,
                fontSize: 16,
              )
            else if (!_denied)
              V2Button(
                _busy
                    ? 'Turning on…'
                    : _error == null
                    ? 'Turn on notifications'
                    : 'Try again',
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
