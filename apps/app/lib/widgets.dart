import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'theme/tokens.dart';

class RtwLogo extends StatelessWidget {
  const RtwLogo({
    super.key,
    this.center = false,
    this.onDark = false,
    this.size,
  });

  final bool center;
  final bool onDark;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(
      color: onDark ? RtwColors.paper : RtwColors.ink,
      fontSize: size,
    );
    return Text.rich(
      TextSpan(
        text: 'read the world',
        children: [
          TextSpan(
            text: '.',
            style: style.copyWith(color: RtwColors.clay),
          ),
        ],
      ),
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: style,
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.fontSize});

  final String text;
  final Color? color;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        color: color ?? RtwColors.muted,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class RtwButton extends StatelessWidget {
  const RtwButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.fullWidth = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool fullWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 18)],
      ],
    );
    final style = ElevatedButton.styleFrom(
      elevation: 0,
      minimumSize: Size(fullWidth ? double.infinity : 0, compact ? 46 : 54),
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 13 : 17,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RtwRadii.button),
        side: BorderSide(
          color: secondary ? RtwColors.borderStrong : RtwColors.blue,
          width: secondary ? 1.5 : 1,
        ),
      ),
      backgroundColor: secondary ? RtwColors.card : RtwColors.blue,
      foregroundColor: secondary ? RtwColors.ink : Colors.white,
      disabledBackgroundColor: RtwColors.borderStrong,
      disabledForegroundColor: RtwColors.muted,
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
    return ElevatedButton(onPressed: onPressed, style: style, child: child);
  }
}

class RtwCard extends StatelessWidget {
  const RtwCard({
    super.key,
    required this.child,
    this.padding,
    this.dark = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? RtwColors.ink : RtwColors.card,
        border: Border.all(color: dark ? RtwColors.ink : RtwColors.border),
        borderRadius: BorderRadius.circular(RtwRadii.card),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(22),
        child: child,
      ),
    );
  }
}

class AnswerTile extends StatelessWidget {
  const AnswerTile({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final RtwOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(RtwRadii.tile),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: BoxConstraints(minHeight: isWide ? 66 : 82),
            padding: EdgeInsets.symmetric(
              horizontal: 22,
              vertical: isWide ? 18 : 20,
            ),
            decoration: BoxDecoration(
              color: selected ? RtwColors.blueTint : RtwColors.card,
              borderRadius: BorderRadius.circular(RtwRadii.tile),
              border: Border.all(
                color: selected ? RtwColors.blue : RtwColors.borderStrong,
                width: selected ? 1.7 : 1.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      fontSize: isWide ? 22 : 26,
                      color: selected ? RtwColors.blue : RtwColors.ink,
                    ),
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 130),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: RtwColors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
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

class PredictionSlider extends StatelessWidget {
  const PredictionSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.showLabels = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    void update(BoxConstraints constraints, Offset localPosition) {
      final width = constraints.maxWidth;
      final next = ((localPosition.dx / width) * 100).round().clamp(0, 100);
      onChanged(next);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => update(constraints, details.localPosition),
          onHorizontalDragUpdate: (details) =>
              update(constraints, details.localPosition),
          child: SizedBox(
            height: showLabels ? 74 : 52,
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: RtwColors.borderStrong,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: value / 100,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: RtwColors.blue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (constraints.maxWidth * value / 100 - 18).clamp(
                          0,
                          constraints.maxWidth - 36,
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: RtwColors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: RtwColors.card, width: 4),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x2E28241C),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showLabels)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SliderLabel('HARDLY ANYONE'),
                      _SliderLabel('HALF'),
                      _SliderLabel('NEARLY ALL'),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SliderLabel extends StatelessWidget {
  const _SliderLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        fontSize: 10,
        letterSpacing: 0.5,
        color: RtwColors.muted,
      ),
    );
  }
}

class SpectrumBar extends StatelessWidget {
  const SpectrumBar({
    super.key,
    required this.worldShare,
    required this.guess,
    this.progress = 1,
    this.height = 64,
  });

  final int worldShare;
  final int guess;
  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final guessLeft = width * guess / 100;
        final fillWidth = width * worldShare / 100 * progress;
        return SizedBox(
          height: height + 44,
          child: Stack(
            children: [
              Positioned(
                top: 30,
                left: (guessLeft - 38).clamp(0, width - 76),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: RtwColors.blueTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Eyebrow('YOU $guess%', color: RtwColors.blue),
                ),
              ),
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    children: [
                      Container(height: height, color: const Color(0xFFE6E0D3)),
                      Container(
                        width: fillWidth,
                        height: height,
                        color: RtwColors.clay,
                      ),
                      Positioned.fill(
                        left: 16,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'THE WORLD',
                            style: Theme.of(context).textTheme.labelSmall!
                                .copyWith(
                                  color: RtwColors.card,
                                  fontSize: 10,
                                  letterSpacing: 1.6,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 55,
                bottom: 0,
                left: guessLeft.clamp(0, width - 3),
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: RtwColors.blue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SectionRule extends StatelessWidget {
  const SectionRule({super.key, this.top = 0, this.bottom = 0});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: const Divider(height: 1, thickness: 1, color: RtwColors.border),
    );
  }
}

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    required this.location,
    this.maxWidth = 780,
    this.showBottomNav = true,
  });

  final Widget child;
  final String location;
  final double maxWidth;
  final bool showBottomNav;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 820;
    final mobileWidth = math.min(size.width, 393.0);
    final appSurface = ColoredBox(
      color: RtwColors.paper,
      child: SizedBox(width: isWide ? maxWidth : mobileWidth, child: child),
    );
    return Scaffold(
      backgroundColor: kIsWeb && !isWide
          ? RtwColors.deviceBackdrop
          : RtwColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (isWide) _TopNav(location: location),
            Expanded(
              child: Align(
                alignment: kIsWeb && !isWide
                    ? Alignment.topCenter
                    : isWide
                    ? Alignment.topCenter
                    : Alignment.topLeft,
                child: appSurface,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWide || !showBottomNav
          ? null
          : _BottomNav(location: location),
    );
  }
}

class _TopNav extends StatelessWidget {
  const _TopNav({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: const BoxDecoration(
        color: RtwColors.paper,
        border: Border(bottom: BorderSide(color: RtwColors.border)),
      ),
      child: Row(
        children: [
          const RtwLogo(size: 21),
          const SizedBox(width: 22),
          _NavPill(
            label: 'Today',
            glyph: _NavGlyph.today,
            path: '/today',
            active: location.startsWith('/today') || location == '/reveal',
          ),
          const SizedBox(width: 8),
          _NavPill(
            label: 'History',
            glyph: _NavGlyph.history,
            path: '/history',
            active: location == '/history' || location == '/party',
          ),
          const SizedBox(width: 8),
          _NavPill(
            label: 'Insights',
            glyph: _NavGlyph.insights,
            path: '/insights',
            active: location == '/insights',
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: RtwColors.clay,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '7-DAY STREAK',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 20),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go('/account'),
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: RtwColors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    'A',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
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

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.label,
    required this.glyph,
    required this.path,
    required this.active,
  });

  final String label;
  final _NavGlyph glyph;
  final String path;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => context.go(path),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: active ? const Color(0x0F211F1A) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            _NavGlyphIcon(
              glyph,
              size: 15,
              color: active ? RtwColors.ink : RtwColors.faint,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: active ? RtwColors.ink : RtwColors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobileWidth = math.min(size.width, 393.0);
    const navHeight = 84.0;
    final current = location == '/history' || location == '/party'
        ? 1
        : location == '/insights'
        ? 2
        : 0;
    final navSurface = Container(
      width: mobileWidth,
      height: navHeight,
      decoration: const BoxDecoration(
        color: RtwColors.paper,
        border: Border(top: BorderSide(color: Color(0xFFE2DCD0))),
      ),
      child: Row(
        children: [
          _BottomItem(
            index: 0,
            selectedIndex: current,
            glyph: _NavGlyph.today,
            label: 'Today',
            onTap: () => context.go('/today'),
          ),
          _BottomItem(
            index: 1,
            selectedIndex: current,
            glyph: _NavGlyph.history,
            label: 'History',
            onTap: () => context.go('/history'),
          ),
          _BottomItem(
            index: 2,
            selectedIndex: current,
            glyph: _NavGlyph.insights,
            label: 'Insights',
            onTap: () => context.go('/insights'),
          ),
        ],
      ),
    );
    final isWide = size.width >= 820;
    return Container(
      height: navHeight,
      color: kIsWeb && !isWide ? RtwColors.deviceBackdrop : RtwColors.paper,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: kIsWeb && !isWide
              ? Alignment.topCenter
              : Alignment.topLeft,
          child: navSurface,
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.index,
    required this.selectedIndex,
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final int index;
  final int selectedIndex;
  final _NavGlyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = index == selectedIndex;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavGlyphIcon(
                glyph,
                size: 18,
                color: active ? RtwColors.ink : RtwColors.faint,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: active ? RtwColors.ink : RtwColors.faint,
                  fontSize: 11,
                  letterSpacing: 0.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NavGlyph { today, history, insights }

class _NavGlyphIcon extends StatelessWidget {
  const _NavGlyphIcon(this.glyph, {required this.size, required this.color});

  final _NavGlyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _NavGlyphPainter(glyph: glyph, color: color),
    );
  }
}

class _NavGlyphPainter extends CustomPainter {
  const _NavGlyphPainter({required this.glyph, required this.color});

  final _NavGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 18;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    RRect rect(double x, double y, double width, double height, double radius) {
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(x * scale, y * scale, width * scale, height * scale),
        Radius.circular(radius * scale),
      );
    }

    switch (glyph) {
      case _NavGlyph.today:
        canvas.drawCircle(Offset(9 * scale, 9 * scale), 5 * scale, paint);
      case _NavGlyph.history:
        canvas
          ..drawRRect(rect(2, 3, 14, 2.8, 1.4), paint)
          ..drawRRect(rect(2, 7.6, 14, 2.8, 1.4), paint)
          ..drawRRect(rect(2, 12.2, 9, 2.8, 1.4), paint);
      case _NavGlyph.insights:
        canvas
          ..drawRRect(rect(2, 9, 3.4, 7, 1), paint)
          ..drawRRect(rect(7.3, 5, 3.4, 11, 1), paint)
          ..drawRRect(rect(12.6, 2, 3.4, 14, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_NavGlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.color != color;
  }
}

String compactCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).round()}K';
  return value.toString();
}
