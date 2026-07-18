import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import 'models_v2.dart';
import 'party_controller.dart';
import 'tokens_v2.dart';

/// Exact-size text helpers — the prototype styles each element in px, so v2
/// screens use these instead of the coarser app-wide TextTheme roles.
TextStyle v2Serif(
  double size, {
  Color color = RtwV2Colors.ink,
  FontWeight weight = FontWeight.w500,
  double? height,
  double? letterSpacing,
  FontStyle? fontStyle,
}) => GoogleFonts.newsreader(
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: height,
  letterSpacing: letterSpacing,
  fontStyle: fontStyle,
);

TextStyle v2Sans(
  double size, {
  Color color = RtwV2Colors.ink,
  FontWeight weight = FontWeight.w400,
  double? height,
  double? letterSpacing,
}) => GoogleFonts.hankenGrotesk(
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: height,
  letterSpacing: letterSpacing,
);

TextStyle v2Mono(
  double size, {
  Color color = RtwV2Colors.muted,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 1.4,
}) => GoogleFonts.ibmPlexMono(
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: letterSpacing,
);

/// Uppercased mono eyebrow (`IBM Plex Mono`, ls ~1.4-1.6).
class V2Eyebrow extends StatelessWidget {
  const V2Eyebrow(
    this.text, {
    super.key,
    this.size = 10,
    this.color = RtwV2Colors.muted,
    this.letterSpacing = 1.4,
  });

  final String text;
  final double size;
  final Color color;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: v2Mono(size, color: color, letterSpacing: letterSpacing),
  );
}

/// Room icon tile: rounded square, room color, serif initial at 0.42×size.
class RoomIcon extends StatelessWidget {
  const RoomIcon({
    super.key,
    required this.room,
    this.size = 46,
    this.radius = 14,
  });

  final RtwRoom room;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isWorld = room.isWorld;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isWorld
            ? RtwV2Colors.worldInk
            : RtwV2Colors.roomColor(room.colorToken),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: isWorld
          ? Icon(Icons.public, color: Colors.white, size: size * 0.5)
          : Text(
              room.initial,
              style: v2Serif(size * 0.42, color: Colors.white),
            ),
    );
  }
}

class V2QuestionReactionButtons extends StatelessWidget {
  const V2QuestionReactionButtons({
    super.key,
    required this.reaction,
    required this.onToggle,
  });

  final QuestionReaction? reaction;
  final ValueChanged<QuestionReaction> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QuestionReactionButton(
          reaction: QuestionReaction.liked,
          active: reaction == QuestionReaction.liked,
          onTap: onToggle,
        ),
        const SizedBox(width: 4),
        _QuestionReactionButton(
          reaction: QuestionReaction.disliked,
          active: reaction == QuestionReaction.disliked,
          onTap: onToggle,
        ),
      ],
    );
  }
}

class _QuestionReactionButton extends StatelessWidget {
  const _QuestionReactionButton({
    required this.reaction,
    required this.active,
    required this.onTap,
  });

  final QuestionReaction reaction;
  final bool active;
  final ValueChanged<QuestionReaction> onTap;

  @override
  Widget build(BuildContext context) {
    final liked = reaction == QuestionReaction.liked;
    final color = active
        ? (liked ? RtwV2Colors.blue : RtwV2Colors.clay)
        : RtwV2Colors.faint;
    return Semantics(
      button: true,
      selected: active,
      label: liked ? 'Like question' : 'Dislike question',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(reaction),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(
              liked
                  ? (active ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined)
                  : (active
                        ? Icons.thumb_down_alt
                        : Icons.thumb_down_alt_outlined),
              size: 18,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tier chip (mono 9, uppercase, tinted). Prototype hides it for `normal`.
class TierChip extends StatelessWidget {
  const TierChip({super.key, required this.tier});

  final RoomTier tier;

  Color get _color => switch (tier) {
    RoomTier.workSafe => RtwV2Colors.green,
    RoomTier.normal => RtwV2Colors.blue,
    RoomTier.mature => RtwV2Colors.clay,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        tier.label.toUpperCase(),
        style: v2Mono(9, color: _color, letterSpacing: 0.8),
      ),
    );
  }
}

/// Primary filled button (radius 14-16, Hanken 15-16 w600).
class V2Button extends StatelessWidget {
  const V2Button(
    this.label, {
    super.key,
    required this.onPressed,
    this.background = RtwV2Colors.blue,
    this.foreground = Colors.white,
    this.fontSize = 15,
    this.fontWeight = FontWeight.w600,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
    this.responsiveHeight = true,
    this.radius = 14,
    this.border,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsets padding;
  final bool responsiveHeight;
  final double radius;
  final BorderSide? border;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final effectivePadding = responsiveHeight
            ? _paddingForWidth(buttonWidth)
            : padding;

        return SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              backgroundColor: background,
              disabledBackgroundColor: background.withValues(alpha: 0.5),
              padding: effectivePadding,
              side: border,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
            child: _V2ArrowText(
              label,
              style: v2Sans(fontSize, color: foreground, weight: fontWeight),
              color: foreground,
              fontSize: fontSize,
            ),
          ),
        );
      },
    );
  }

  EdgeInsets _paddingForWidth(double width) {
    final currentVertical = padding.vertical / 2;
    final minVertical = switch (width) {
      >= 900 => 20.0,
      >= 640 => 18.0,
      >= 480 => 16.0,
      _ => currentVertical,
    };
    if (minVertical <= currentVertical) return padding;
    final extraVertical = minVertical - currentVertical;
    return EdgeInsets.fromLTRB(
      padding.left,
      padding.top + extraVertical,
      padding.right,
      padding.bottom + extraVertical,
    );
  }
}

class V2ArrowLabel extends StatelessWidget {
  const V2ArrowLabel(
    this.label, {
    super.key,
    required this.color,
    required this.fontSize,
    required this.weight,
  });

  final String label;
  final Color color;
  final double fontSize;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return _V2ArrowText(
      '$label →',
      style: v2Sans(fontSize, color: color, weight: weight),
      color: color,
      fontSize: fontSize,
    );
  }
}

class V2LeadingArrowLabel extends StatelessWidget {
  const V2LeadingArrowLabel(
    this.label, {
    super.key,
    required this.color,
    required this.fontSize,
    this.weight = FontWeight.w600,
    this.gap = 6,
  });

  final String label;
  final Color color;
  final double fontSize;
  final FontWeight weight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '← $label',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, fontSize * 0.04),
              child: V2InlineArrow(
                direction: V2ArrowDirection.left,
                color: color,
                fontSize: fontSize,
              ),
            ),
            SizedBox(width: gap),
            Text(
              label,
              textAlign: TextAlign.center,
              style: v2Sans(fontSize, color: color, weight: weight),
            ),
          ],
        ),
      ),
    );
  }
}

class _V2ArrowText extends StatelessWidget {
  const _V2ArrowText(
    this.label, {
    required this.style,
    required this.color,
    required this.fontSize,
  });

  final String label;
  final TextStyle style;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = _stripTrailingRightArrow(label);
    if (text == null) {
      return Text(label, style: style, textAlign: TextAlign.center);
    }

    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(text, style: style, textAlign: TextAlign.center),
            SizedBox(width: (fontSize * 0.35).clamp(5.0, 7.0)),
            Transform.translate(
              offset: Offset(0, fontSize * 0.03),
              child: V2InlineArrow(
                direction: V2ArrowDirection.right,
                color: color,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _stripTrailingRightArrow(String label) {
  final trimmed = label.trimRight();
  if (!trimmed.endsWith('→')) return null;
  return trimmed.substring(0, trimmed.length - 1).trimRight();
}

enum V2ArrowDirection { left, right }

class V2InlineArrow extends StatelessWidget {
  const V2InlineArrow({
    super.key,
    required this.direction,
    required this.color,
    required this.fontSize,
  });

  final V2ArrowDirection direction;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (fontSize * 0.95).clamp(13.0, 16.0),
      height: (fontSize * 0.56).clamp(7.5, 9.5),
      child: CustomPaint(
        painter: _V2InlineArrowPainter(
          direction: direction,
          color: color,
          strokeWidth: (fontSize * 0.09).clamp(1.25, 1.45),
        ),
      ),
    );
  }
}

class _V2InlineArrowPainter extends CustomPainter {
  const _V2InlineArrowPainter({
    required this.direction,
    required this.color,
    required this.strokeWidth,
  });

  final V2ArrowDirection direction;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final midY = size.height / 2;
    final headInset = size.width * 0.34;
    final headY = size.height * 0.38;
    final startX = strokeWidth / 2;
    final endX = size.width - strokeWidth / 2;
    final points = direction == V2ArrowDirection.right
        ? (tip: endX, tail: startX, headBase: endX - headInset)
        : (tip: startX, tail: endX, headBase: startX + headInset);

    final path = Path()
      ..moveTo(points.tail, midY)
      ..lineTo(points.tip, midY)
      ..moveTo(points.headBase, midY - headY)
      ..lineTo(points.tip, midY)
      ..lineTo(points.headBase, midY + headY);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _V2InlineArrowPainter oldDelegate) {
    return oldDelegate.direction != direction ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Prototype toggle: 46×28 track, 22px knob (or 44×26/20 in room settings).
class V2Toggle extends StatelessWidget {
  const V2Toggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.trackWidth = 46,
    this.trackHeight = 28,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final double trackWidth;
  final double trackHeight;

  @override
  Widget build(BuildContext context) {
    final knobSize = trackHeight - 6;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: trackWidth,
        height: trackHeight,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? RtwV2Colors.blue : RtwV2Colors.knobTrackOff,
          borderRadius: BorderRadius.circular(trackHeight / 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: knobSize,
            height: knobSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x38000000),
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom nav: Today / Rooms / Party (prototype exact — 18px glyphs,
/// 11px w600 labels, active #23211C, idle #B3AD9F).
class V2BottomNav extends StatelessWidget {
  const V2BottomNav({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final roomsActive = location.startsWith('/rooms');
    final todayActive = location == '/today' || location.startsWith('/today/');
    final partyActive = location.startsWith('/party');
    return Container(
      decoration: const BoxDecoration(
        color: RtwV2Colors.paper,
        border: Border(top: BorderSide(color: Color(0xFFE2DCD0))),
      ),
      padding: EdgeInsets.only(
        top: 11,
        bottom: math.max(24, MediaQuery.paddingOf(context).bottom),
      ),
      child: Row(
        children: [
          _NavItem(
            label: 'Today',
            active: todayActive,
            onTap: () => context.go('/today'),
            icon: (color) => Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
          _NavItem(
            label: 'Rooms',
            active: roomsActive,
            onTap: () => context.go('/rooms'),
            icon: (color) => _GridGlyph(color: color),
          ),
          _NavItem(
            label: 'Party',
            active: partyActive,
            onTap: () => context.go('/party'),
            icon: (color) => CustomPaint(
              size: const Size(18, 18),
              painter: _TrianglePainter(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.active,
    required this.onTap,
    required this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget Function(Color color) icon;

  @override
  Widget build(BuildContext context) {
    final color = active ? RtwV2Colors.inkSoft : RtwV2Colors.navIdle;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon(color),
            const SizedBox(height: 5),
            Text(
              label,
              style: v2Sans(
                11,
                color: color,
                weight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridGlyph extends StatelessWidget {
  const _GridGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // Prototype: 6px cells at x 2/10, y 2.5/10.5 in an 18px box — a tight
    // 14px grid with a 2px gutter, centered.
    Widget cell() => Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.6),
      ),
    );
    Widget row() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [cell(), const SizedBox(width: 2), cell()],
    );
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [row(), const SizedBox(height: 2), row()],
        ),
      ),
    );
  }
}

/// Prototype party glyph: sharp play triangle (M4 3l11 6-11 6z in 18px).
class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(4, 3)
      ..lineTo(15, 9)
      ..lineTo(4, 15)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// v2 page scaffold: phone-column surface centered on wide screens
/// (spec §8), optional bottom nav, prototype fade-up entrance.
/// Compact text-arrow back control from the v2 design mock.
class V2BackButton extends StatelessWidget {
  const V2BackButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8, right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            V2LeadingArrowLabel(
              label,
              color: RtwV2Colors.subText,
              fontSize: 14.5,
              weight: FontWeight.w600,
            ),
          ],
        ),
      ),
    );
  }
}

/// Top inset for full-screen v2 surfaces, matching the main tabs' margin so
/// content clears the status bar / dynamic island consistently.
double v2ScreenTopInset(BuildContext context) {
  final safeTop = MediaQuery.paddingOf(context).top;
  return safeTop > 40 ? safeTop + 16 : 60;
}

class V2Scaffold extends StatelessWidget {
  const V2Scaffold({
    super.key,
    required this.location,
    required this.child,
    this.showNav = true,
    this.backgroundColor = RtwV2Colors.paper,
    this.wideWidth = 560,
  });

  final String location;
  final Widget child;
  final bool showNav;
  final Color backgroundColor;

  /// Max content width on the wide (web-native) shell. Focused surfaces
  /// (play, onboarding) keep a narrow column; browsing surfaces (rooms
  /// home, room detail) go wide.
  final double wideWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 820;

    if (isWide) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Column(
          children: [
            if (showNav) V2TopNav(location: location),
            Expanded(
              child: _FadeUp(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wideWidth),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final persistentNavigation = _V2PersistentNavigationScope.active(context);
    final surfaceWidth = kIsWeb ? math.min(size.width, 393.0) : size.width;
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SizedBox(
        width: surfaceWidth,
        child: Column(
          children: [
            // Routed mobile pages get their motion from GoRouter. Replaying
            // the prototype fade-up inside a native slide made every push feel
            // like two animations fighting each other.
            Expanded(
              child: persistentNavigation ? child : _FadeUp(child: child),
            ),
            if (showNav && !persistentNavigation)
              V2BottomNav(location: location),
          ],
        ),
      ),
    );
  }
}

/// Persistent mobile application chrome for authenticated routes.
///
/// The nested Navigator supplied by [ShellRoute] is the body, while the tab
/// bar is mounted once below it. Pushes and pops therefore happen entirely
/// above the bar. Wide layouts retain their existing per-screen top nav.
class V2NavigationShell extends ConsumerStatefulWidget {
  const V2NavigationShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  @override
  ConsumerState<V2NavigationShell> createState() => _V2NavigationShellState();
}

class _V2NavigationShellState extends ConsumerState<V2NavigationShell> {
  late String _lastPrimaryLocation =
      _primaryLocation(widget.location) ?? '/rooms';

  @override
  void didUpdateWidget(V2NavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final primary = _primaryLocation(widget.location);
    if (primary != null) _lastPrimaryLocation = primary;
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 820) return widget.child;

    final activePartySession =
        widget.location.startsWith('/party') &&
        ref.watch(
          partyControllerProvider.select(
            (party) => party.stage != PartyStage.setup,
          ),
        );

    return _V2PersistentNavigationScope(
      child: Scaffold(
        backgroundColor: RtwV2Colors.paper,
        body: widget.child,
        bottomNavigationBar: activePartySession
            ? null
            : V2BottomNav(location: _lastPrimaryLocation),
      ),
    );
  }

  static String? _primaryLocation(String location) {
    if (location == '/today' || location.startsWith('/today/')) {
      return '/today';
    }
    if (location == '/rooms' || location.startsWith('/rooms/')) {
      return '/rooms';
    }
    if (location == '/party' || location.startsWith('/party/')) {
      return '/party';
    }
    return null;
  }
}

class _V2PersistentNavigationScope extends InheritedWidget {
  const _V2PersistentNavigationScope({required super.child});

  static bool active(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_V2PersistentNavigationScope>() !=
      null;

  @override
  bool updateShouldNotify(_V2PersistentNavigationScope oldWidget) => false;
}

/// Web-native top nav for the wide shell: wordmark, text tabs, avatar.
class V2TopNav extends ConsumerWidget {
  const V2TopNav({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(rtwControllerProvider);
    final initial = profile.displayName.isEmpty
        ? '?'
        : profile.displayName.substring(0, 1).toUpperCase();
    final todayActive = location == '/today' || location.startsWith('/today/');
    final roomsActive = location.startsWith('/rooms');
    final partyActive = location.startsWith('/party');

    Widget tab(String label, bool active, String route) => _TopNavTab(
      label: label,
      active: active,
      onTap: () => context.go(route),
    );

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: RtwV2Colors.paper,
        border: Border(bottom: BorderSide(color: Color(0xFFE2DCD0))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/rooms'),
                  behavior: HitTestBehavior.opaque,
                  child: Text.rich(
                    TextSpan(
                      text: 'read the world',
                      style: v2Serif(20, letterSpacing: -0.4),
                      children: [
                        TextSpan(
                          text: '.',
                          style: v2Serif(20, color: RtwV2Colors.clay),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 36),
                tab('Today', todayActive, '/today'),
                tab('Rooms', roomsActive, '/rooms'),
                tab('Party', partyActive, '/party'),
                const Spacer(),
                Semantics(
                  button: true,
                  label: 'Profile',
                  child: GestureDetector(
                    onTap: () => context.push('/profile'),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const [
                          RtwV2Colors.blue,
                          RtwV2Colors.clay,
                          RtwV2Colors.green,
                          RtwV2Colors.inkColorOption,
                        ][profile.avatarIndex % 4],
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initial,
                        textAlign: TextAlign.center,
                        style: v2Serif(16, color: Colors.white, height: 1.0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopNavTab extends StatelessWidget {
  const _TopNavTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: Text(
            label,
            style: v2Sans(
              15,
              color: active ? RtwV2Colors.inkSoft : RtwV2Colors.muted,
              weight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Prototype `rwFadeUp` — 500ms ease, 10px rise.
class _FadeUp extends StatelessWidget {
  const _FadeUp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: RtwV2Motion.pageFade,
      curve: Curves.ease,
      builder: (context, t, childWidget) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: childWidget,
        ),
      ),
      child: child,
    );
  }
}

/// Bottom sheet container matching the prototype (radius 28 top, paper bg,
/// drag handle, max height 88%). On wide screens it becomes a centered dialog.
Future<T?> showV2Sheet<T>(BuildContext context, WidgetBuilder builder) {
  final isWide = MediaQuery.sizeOf(context).width >= 820;
  if (isWide) {
    return showDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierColor: const Color(0x6B1C1A16),
      builder: (context) => Dialog(
        backgroundColor: RtwV2Colors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    backgroundColor: RtwV2Colors.paper,
    barrierColor: const Color(0x6B1C1A16),
    isDismissible: true,
    enableDrag: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 38),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 2, bottom: 20),
                decoration: BoxDecoration(
                  color: RtwV2Colors.knobTrackOff,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Builder(builder: builder),
          ],
        ),
      ),
    ),
  );
}

/// Section hairline used inside cards (`border-top:1px solid #EFEAE0`).
class V2Hairline extends StatelessWidget {
  const V2Hairline({super.key});

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: RtwV2Colors.hairline);
}

/// Count-first prediction readout. Smaller rooms are easier to reason about as
/// whole people; larger rooms keep percent primary while still showing count.
class PredictionReadout extends StatelessWidget {
  const PredictionReadout({
    super.key,
    required this.percent,
    required this.people,
    required this.sideLabel,
    required this.sideColor,
    this.prompt = 'How many will agree with you?',
    this.promptSize = 24,
    this.primarySize = 80,
    this.primaryHeight = 1,
    this.infinite = false,
    this.eyebrow,
    this.sideCaption,
    this.secondaryText,
  });

  static const countFirstThreshold = 25;

  final int percent;
  final int people;
  final String sideLabel;
  final Color sideColor;
  final String prompt;
  final double promptSize;
  final double primarySize;
  final double primaryHeight;
  final String? eyebrow;
  final String? sideCaption;
  final String? secondaryText;

  /// Solo / World: no fixed room size, so read the prediction as a share of
  /// everyone who answers rather than a count of the current room [Mike].
  final bool infinite;

  @override
  Widget build(BuildContext context) {
    final boundedPercent = percent < 0
        ? 0
        : percent > 100
        ? 100
        : percent;
    final boundedPeople = people < 0 ? 0 : people;
    final rawCount = ((boundedPercent / 100) * boundedPeople).round();
    final count = boundedPeople == 0
        ? 0
        : rawCount < 0
        ? 0
        : rawCount > boundedPeople
        ? boundedPeople
        : rawCount;
    final countPercent = boundedPeople == 0
        ? boundedPercent
        : ((count / boundedPeople) * 100).round();
    final percentPrimary = infinite || boundedPeople > countFirstThreshold;
    final primary = percentPrimary ? '$boundedPercent%' : '$count';
    final defaultSecondary = infinite
        ? 'of people who answer'
        : percentPrimary
        ? '$count of $boundedPeople players'
        : '$countPercent% of the room';
    final secondary = secondaryText ?? defaultSecondary;
    final predictionColor = RtwV2Colors.meterBlue;

    return Column(
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            textAlign: TextAlign.center,
            style: v2Mono(10, color: predictionColor, letterSpacing: 1.5),
          ),
          const SizedBox(height: 10),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            prompt,
            textAlign: TextAlign.center,
            style: v2Serif(
              promptSize,
              color: const Color(0xFF2C2A24),
              height: 1.28,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _PredictionPrimaryValue(
          primary: primary,
          people: boundedPeople,
          percentPrimary: percentPrimary,
          primarySize: primarySize,
          primaryHeight: primaryHeight,
          color: predictionColor,
        ),
        if ((sideCaption ?? 'Would pick “$sideLabel”').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            sideCaption ?? 'Would pick “$sideLabel”',
            textAlign: TextAlign.center,
            style: v2Sans(14, color: predictionColor, weight: FontWeight.w700),
          ),
        ],
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            secondary,
            textAlign: TextAlign.center,
            style: v2Sans(13, color: RtwV2Colors.muted),
          ),
        ],
      ],
    );
  }
}

class _PredictionPrimaryValue extends StatelessWidget {
  const _PredictionPrimaryValue({
    required this.primary,
    required this.people,
    required this.percentPrimary,
    required this.primarySize,
    required this.primaryHeight,
    required this.color,
  });

  final String primary;
  final int people;
  final bool percentPrimary;
  final double primarySize;
  final double primaryHeight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (percentPrimary) {
      return Text(
        primary,
        textAlign: TextAlign.center,
        style: v2Serif(primarySize, color: color, height: primaryHeight),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          primary,
          style: v2Serif(primarySize, color: color, height: primaryHeight),
        ),
        const SizedBox(width: 8),
        Text(
          'of $people',
          style: v2Serif(
            math.max(24, primarySize * 0.42),
            color: RtwV2Colors.subText,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class PredictionAgreementMeter extends StatelessWidget {
  const PredictionAgreementMeter({
    super.key,
    required this.percent,
    required this.people,
    required this.onUpdate,
    this.height = 72,
    this.radius = 18,
    this.infinite = false,
    this.showSelection = true,
  });

  static const notchThreshold = 15;
  static const countReadoutThreshold = PredictionReadout.countFirstThreshold;

  final int percent;
  final int people;
  final ValueChanged<double> onUpdate;
  final double height;
  final double radius;

  /// Solo / World: continuous 0-100 with percent guides and an "EVERYONE"
  /// end label instead of a fixed room headcount [Mike].
  final bool infinite;

  /// When false, the track stays visually empty until the user makes an
  /// explicit prediction. Other play surfaces keep their existing selected
  /// state by using the default value.
  final bool showSelection;

  @override
  Widget build(BuildContext context) {
    final boundedPercent = percent < 0
        ? 0
        : percent > 100
        ? 100
        : percent;
    final boundedPeople = people < 0 ? 0 : people;
    final fraction = showSelection ? boundedPercent / 100 : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void update(double localX) {
          if (width <= 0) return;
          onUpdate((localX / width).clamp(0.0, 1.0));
        }

        return Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragDown: (details) =>
                  update(details.localPosition.dx),
              onHorizontalDragUpdate: (details) =>
                  update(details.localPosition.dx),
              onTapUp: (details) => update(details.localPosition.dx),
              child: Container(
                height: height,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6E0D3),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Stack(
                  children: [
                    if (showSelection)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: fraction,
                          child: Container(
                            key: const ValueKey('prediction-meter-fill'),
                            height: height,
                            color: RtwV2Colors.meterBlue.withValues(
                              alpha: 0.85,
                            ),
                          ),
                        ),
                      ),
                    ..._meterMarks(
                      boundedPeople,
                      height,
                      !infinite && boundedPeople <= notchThreshold,
                      infinite: infinite,
                    ),
                    if (showSelection)
                      Align(
                        alignment: Alignment(fraction * 2 - 1, 0),
                        child: Container(
                          key: const ValueKey('prediction-meter-handle'),
                          width: 6,
                          height: math.min(30, height - 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x40000000),
                                offset: Offset(0, 1),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'NO ONE',
                  style: v2Mono(
                    10,
                    color: RtwV2Colors.muted,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  infinite
                      ? 'EVERYONE'
                      : boundedPeople <= countReadoutThreshold
                      ? 'ALL $boundedPeople'
                      : 'ALL',
                  style: v2Mono(
                    10,
                    color: RtwV2Colors.muted,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  List<Widget> _meterMarks(
    int people,
    double height,
    bool showPersonNotches, {
    bool infinite = false,
  }) {
    if (!infinite && people <= 1) return const [];
    final fractions = showPersonNotches
        ? [for (var index = 1; index < people; index++) index / people]
        : const [0.25, 0.5, 0.75];
    return [
      for (final fraction in fractions)
        Align(
          alignment: Alignment(fraction * 2 - 1, 0),
          child: Container(
            key: ValueKey(
              showPersonNotches
                  ? 'prediction-meter-person-notch'
                  : 'prediction-meter-guide',
            ),
            width: 2,
            height: showPersonNotches ? height * 0.50 : height * 0.42,
            decoration: BoxDecoration(
              color: RtwV2Colors.ink.withValues(
                alpha: showPersonNotches ? 0.14 : 0.10,
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
    ];
  }
}

/// Transitional stub for v2 routes whose screens are still being built.
/// Every instance disappears before the rebuild is called done.
class V2InProgressScreen extends StatelessWidget {
  const V2InProgressScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return V2Scaffold(
      location: location,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const V2Eyebrow('Read the World v2'),
            const SizedBox(height: 12),
            Text('This screen lands next.', style: v2Serif(24)),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => context.go('/rooms'),
              child: const V2LeadingArrowLabel(
                'Back to rooms',
                color: RtwV2Colors.blue,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
