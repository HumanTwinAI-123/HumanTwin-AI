import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/capture/photo_guide_screen.dart';
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
    ],
  );
}

class HumanTwinApp extends StatelessWidget {
  HumanTwinApp({super.key, GoRouter? router})
    : router = router ?? createAppRouter();

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HumanTwin AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
