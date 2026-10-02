import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/library/library_controller.dart';
import 'theme/app_theme.dart';

/// Bottom navigation: 首页 · 我的形象 · 设置. Back on another tab returns to 首页 first.
class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool attention = ref.watch(
      libraryControllerProvider.select(
        (LibraryState s) => s.hasLibraryAttention,
      ),
    );
    return PopScope<Object?>(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && shell.currentIndex != 0) {
          shell.goBranch(0);
        }
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (int index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: <NavigationDestination>[
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: attention,
                backgroundColor: AppColors.warning,
                smallSize: 8,
                child: const Icon(Icons.account_box_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: attention,
                backgroundColor: AppColors.warning,
                smallSize: 8,
                child: const Icon(Icons.account_box_rounded),
              ),
              label: '我的形象',
              tooltip: attention ? '我的形象，有任务需要处理' : '我的形象',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}
