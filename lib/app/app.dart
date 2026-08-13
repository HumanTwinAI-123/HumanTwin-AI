import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/capture/photo_guide_screen.dart';
import '../features/capture/photo_flow_controller.dart';
import '../features/capture/photo_confirmation_screen.dart';
import '../features/capture/photo_selection_screen.dart';
import '../features/home/home_screen.dart';
import 'theme/app_theme.dart';

GoRouter createAppRouter() {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const HomeScreen(),
      ),
      GoRoute(
        path: '/photo-guide',
        builder: (BuildContext context, GoRouterState state) =>
            const PhotoGuideScreen(),
      ),
      GoRoute(
        path: '/photos',
        builder: (BuildContext context, GoRouterState state) =>
            const PhotoSelectionScreen(),
      ),
      GoRoute(
        path: '/photo-confirmation',
        builder: (BuildContext context, GoRouterState state) =>
            const PhotoConfirmationScreen(),
      ),
      GoRoute(
        path: '/processing',
        builder: (BuildContext context, GoRouterState state) =>
            const ProcessingPlaceholderScreen(),
      ),
    ],
  );
}

class HumanTwinApp extends ConsumerStatefulWidget {
  HumanTwinApp({super.key, GoRouter? router})
    : router = router ?? createAppRouter();

  final GoRouter router;

  @override
  ConsumerState<HumanTwinApp> createState() => _HumanTwinAppState();
}

class _HumanTwinAppState extends ConsumerState<HumanTwinApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(photoFlowControllerProvider.notifier).retrieveLostData(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HumanTwin AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: widget.router,
    );
  }
}
