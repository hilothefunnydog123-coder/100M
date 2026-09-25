import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'theme/theme.dart';
import 'ui/home/home_screen.dart';
import 'ui/setup/setup_screen.dart';

class JobwalkApp extends ConsumerWidget {
  const JobwalkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupDone = ref.watch(settingsProvider.select((s) => s.setupDone));
    return MaterialApp(
      title: 'Jobwalk',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: setupDone ? const HomeScreen() : const SetupScreen(),
    );
  }
}
