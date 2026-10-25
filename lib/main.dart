import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/in_season_shell.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: RosterIQApp()));
}

class RosterIQApp extends StatelessWidget {
  const RosterIQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RosterIQ',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const _RootGate(),
    );
  }
}

/// Checks shared_preferences for the onboarding flag before deciding whether
/// to show [OnboardingScreen] or go straight to [InSeasonShell].
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    isOnboardingComplete().then((done) {
      if (mounted) setState(() => _onboardingDone = done);
    });
  }

  void _completeOnboarding() {
    if (mounted) setState(() => _onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      // Waiting for shared_preferences - show a blank/loading screen.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_onboardingDone == false) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }
    return const InSeasonShell();
  }
}
