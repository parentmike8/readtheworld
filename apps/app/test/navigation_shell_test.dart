import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:read_the_world/v2/models_v2.dart';
import 'package:read_the_world/v2/party_controller.dart';
import 'package:read_the_world/v2/widgets_v2.dart';

void main() {
  testWidgets('mobile shell keeps one bottom nav fixed across push and pop', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              V2NavigationShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: '/today',
              builder: (_, _) =>
                  const _TestPage(location: '/today', label: 'Today page'),
            ),
            GoRoute(
              path: '/rooms',
              builder: (_, _) => _TestPage(
                location: '/rooms',
                label: 'Rooms page',
                actionLabel: 'Open detail',
                onAction: (context) => context.push('/rooms/detail'),
              ),
            ),
            GoRoute(
              path: '/rooms/detail',
              pageBuilder: (context, state) => CustomTransitionPage<void>(
                key: state.pageKey,
                child: _TestPage(
                  location: '/rooms/detail',
                  label: 'Room detail',
                  actionLabel: 'Back',
                  showNav: false,
                  onAction: (context) => context.pop(),
                ),
                transitionsBuilder: (_, animation, _, child) => SlideTransition(
                  position: animation.drive(
                    Tween(begin: const Offset(1, 0), end: Offset.zero),
                  ),
                  child: child,
                ),
              ),
            ),
            GoRoute(
              path: '/party',
              builder: (_, _) =>
                  const _TestPage(location: '/party', label: 'Party page'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(V2BottomNav), findsOneWidget);
    final navTop = tester.getTopLeft(find.byType(V2BottomNav)).dy;

    await tester.tap(find.text('Open detail'));
    await tester.pump(const Duration(milliseconds: 100));

    // Both pages exist during the slide, but neither creates a second nav.
    expect(find.byType(V2BottomNav), findsOneWidget);
    expect(tester.getTopLeft(find.byType(V2BottomNav)).dy, navTop);

    await tester.pumpAndSettle();
    expect(find.text('Room detail'), findsOneWidget);
    expect(find.byType(V2BottomNav), findsOneWidget);
    expect(tester.getTopLeft(find.byType(V2BottomNav)).dy, navTop);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Rooms page'), findsOneWidget);
    expect(find.byType(V2BottomNav), findsOneWidget);
    expect(tester.getTopLeft(find.byType(V2BottomNav)).dy, navTop);
  });

  testWidgets('mobile shell hides navigation during an active Party game', (
    tester,
  ) async {
    final party = PartyController();
    final router = GoRouter(
      initialLocation: '/party',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              V2NavigationShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: '/party',
              builder: (_, _) =>
                  const _TestPage(location: '/party', label: 'Party setup'),
            ),
            GoRoute(
              path: '/today',
              builder: (_, _) =>
                  const _TestPage(location: '/today', label: 'Today page'),
            ),
            GoRoute(
              path: '/rooms',
              builder: (_, _) =>
                  const _TestPage(location: '/rooms', label: 'Rooms page'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partyControllerProvider.overrideWith(
            (_) => party,
            disposeNotifier: false,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(V2BottomNav), findsOneWidget);

    party.start(const [
      PartyQuestion(
        qid: 'party-1',
        prompt: 'Party question?',
        optA: 'Yes',
        optB: 'No',
        tag: 'Social',
        shape: 'TASTE',
        tier: 'work-safe',
      ),
    ]);
    await tester.pump();

    expect(party.stage, PartyStage.play);
    expect(find.byType(V2BottomNav), findsNothing);

    party.again();
    await tester.pump();

    expect(party.stage, PartyStage.setup);
    expect(find.byType(V2BottomNav), findsOneWidget);
  });

  testWidgets('shared bottom sheets cover the persistent navigation bar', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              V2NavigationShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: '/rooms',
              builder: (_, _) => _TestPage(
                location: '/rooms',
                label: 'Rooms page',
                actionLabel: 'Open sheet',
                onAction: (context) => showV2Sheet<void>(
                  context,
                  (_) => const SizedBox(
                    key: ValueKey('sheet-content'),
                    height: 220,
                    child: Center(child: Text('Sheet content')),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/today',
              builder: (_, _) =>
                  const _TestPage(location: '/today', label: 'Today page'),
            ),
            GoRoute(
              path: '/party',
              builder: (_, _) =>
                  const _TestPage(location: '/party', label: 'Party page'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    final navTop = tester.getTopLeft(find.byType(V2BottomNav)).dy;
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sheet-content')), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.getBottomRight(find.byType(BottomSheet)).dy,
      greaterThan(navTop),
    );
  });
}

class _TestPage extends StatelessWidget {
  const _TestPage({
    required this.location,
    required this.label,
    this.actionLabel,
    this.onAction,
    this.showNav = true,
  });

  final String location;
  final String label;
  final String? actionLabel;
  final ValueChanged<BuildContext>? onAction;
  final bool showNav;

  @override
  Widget build(BuildContext context) {
    return V2Scaffold(
      location: location,
      showNav: showNav,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => onAction?.call(context),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
