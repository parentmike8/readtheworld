import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _deferredInviteChannel = MethodChannel(
  'today.readtheworld.app/deferred_invite',
);

class DeferredInviteCheck {
  const DeferredInviteCheck({required this.available, this.code});

  final bool available;
  final String? code;
}

String? roomInviteCodeFromDeferredText(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final bareCode = value.toUpperCase();
  if (RegExp(r'^[A-Z0-9-]{4,32}$').hasMatch(bareCode)) return bareCode;

  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  String? candidate;
  if (uri.host.toLowerCase() == 'rtw.codes' && uri.pathSegments.isNotEmpty) {
    candidate = uri.pathSegments.first;
  } else if (uri.host.toLowerCase() == 'app.readtheworld.today' &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments.first == 'join') {
    candidate = uri.pathSegments[1];
  }
  final normalized = candidate?.trim().toUpperCase();
  return normalized != null && RegExp(r'^[A-Z0-9-]{4,32}$').hasMatch(normalized)
      ? normalized
      : null;
}

Future<DeferredInviteCheck> checkDeferredInvite() async {
  if (kIsWeb) return const DeferredInviteCheck(available: false);
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final raw = await _deferredInviteChannel.invokeMethod<String>(
        'getInstallReferrer',
      );
      final code = roomInviteCodeFromDeferredText(raw);
      return DeferredInviteCheck(available: code != null, code: code);
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final available =
          await _deferredInviteChannel.invokeMethod<bool>('hasInvite') ?? false;
      return DeferredInviteCheck(available: available);
    }
  } catch (error) {
    debugPrint('Deferred invite check skipped: $error');
  }
  return const DeferredInviteCheck(available: false);
}

Future<String?> readDeferredInvite() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
  try {
    final raw = await _deferredInviteChannel.invokeMethod<String>(
      'readClipboardInvite',
    );
    return roomInviteCodeFromDeferredText(raw);
  } catch (error) {
    debugPrint('Deferred invite paste skipped: $error');
    return null;
  }
}

Future<void> markDeferredInviteConsumed(String code) async {
  if (kIsWeb) return;
  try {
    await _deferredInviteChannel.invokeMethod<void>('markConsumed', {
      'code': code.trim().toUpperCase(),
    });
  } catch (error) {
    debugPrint('Deferred invite cleanup skipped: $error');
  }
}
