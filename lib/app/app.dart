import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/capture/photo_flow_controller.dart';
import '../features/capture/photo_guide_screen.dart';
import '../features/capture/photo_selection_screen.dart';
import '../features/capture/review_screen.dart';
import '../features/generation/task_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/avatar_detail_screen.dart';
import '../features/library/library_controller.dart';
import '../features/library/library_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/settings_screens.dart';
import '../features/share/share_preview_screen.dart';
import '../features/viewer/digital_twin_viewer.dart';
import 'shell.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Routes (IDs only; photos never travel through routes — PhotoFlowController owns them).
///
/// * `/welcome` — first launch only.
/// * Tabs: `/` 首页, `/library` 我的形象, `/settings` 设置.
/// * Full-screen over the tabs (nested under `/` so back returns to 首页):
///   `/create/guide|photos|review`, `/tasks/:id`, `/avatars/:id`, `/avatars/:id/share/:kind`, `/sample`.
/// * `/privacy`, `/help`, `/about`.
GoRouter createAppRouter({
  required bool Function() onboardingDone,
  ViewerBuilder? viewerBuilder,
  String initialLocation = '/',
}) {
  GoRoute fullScreen(String path, GoRouterWidgetBuilder builder) => GoRoute(
    path: path,
    parentNavigatorKey: rootNavigatorKey,
    builder: builder,
  );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    redirect: (BuildContext context, GoRouterState state) {
      final String location = state.matchedLocation;
      if (!onboardingDone() &&
          location != '/welcome' &&
          location != '/privacy') {
        return '/welcome';
      }
      if (onboardingDone() && location == '/welcome') {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/welcome',
        builder: (BuildContext context, GoRouterState state) =>
            const WelcomeScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell shell,
            ) => AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (BuildContext context, GoRouterState state) =>
                    const HomeScreen(),
                routes: <RouteBase>[
                  fullScreen(
                    'create/guide',
                    (BuildContext context, GoRouterState state) =>
                        const PhotoGuideScreen(),
                  ),
                  fullScreen(
                    'create/photos',
                    (BuildContext context, GoRouterState state) =>
                        const PhotoSelectionScreen(),
                  ),
                  fullScreen(
                    'create/review',
                    (BuildContext context, GoRouterState state) =>
                        const ReviewScreen(),
                  ),
                  fullScreen(
                    'tasks/:id',
                    (BuildContext context, GoRouterState state) =>
                        TaskScreen(recordId: state.pathParameters['id']!),
                  ),
                  fullScreen(
                    'sample',
                    (BuildContext context, GoRouterState state) =>
                        AvatarDetailScreen(
                          recordId: AvatarDetailScreen.sampleId,
                          viewerBuilder: viewerBuilder,
                        ),
                  ),
                  fullScreen(
                    'avatars/:id',
                    (BuildContext context, GoRouterState state) =>
                        AvatarDetailScreen(
                          recordId: state.pathParameters['id']!,
                          viewerBuilder: viewerBuilder,
                        ),
                  ),
                  fullScreen(
                    'avatars/:id/share/:kind',
                    (BuildContext context, GoRouterState state) =>
                        SharePreviewScreen(
                          recordId: state.pathParameters['id']!,
                          kind: state.pathParameters['kind'] == 'file'
                              ? ShareKind.file
                              : ShareKind.image,
                        ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/library',
                builder: (BuildContext context, GoRouterState state) =>
                    const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (BuildContext context, GoRouterState state) =>
                    const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/privacy',
        builder: (BuildContext context, GoRouterState state) =>
            const PrivacyScreen(),
      ),
      GoRoute(
        path: '/help',
        builder: (BuildContext context, GoRouterState state) =>
            const HelpScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (BuildContext context, GoRouterState state) =>
            const AboutScreen(),
      ),
    ],
  );
}

class HumanTwinApp extends ConsumerStatefulWidget {
  const HumanTwinApp({
    this.viewerBuilder,
    this.initialLocation = '/',
    super.key,
  });

  /// Test hook replacing the WebView model viewer.
  final ViewerBuilder? viewerBuilder;
  final String initialLocation;

  @override
  ConsumerState<HumanTwinApp> createState() => _HumanTwinAppState();
}

class _HumanTwinAppState extends ConsumerState<HumanTwinApp> {
  late final GoRouter _router = createAppRouter(
    onboardingDone: () => ref.read(appSettingsProvider).onboardingDone,
    viewerBuilder: widget.viewerBuilder,
    initialLocation: widget.initialLocation,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(photoFlowControllerProvider.notifier).retrieveLostData(),
        );
        unawaited(
          ref.read(libraryControllerProvider.notifier).resumeInterrupted(),
        );
      }
    });
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HumanTwin AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: const Locale('zh', 'CN'),
      routerConfig: _router,
    );
  }
}
