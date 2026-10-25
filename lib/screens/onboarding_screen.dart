import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kOnboardingKey = 'onboarding_complete';

/// Returns true if the onboarding has already been completed.
Future<bool> isOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingKey) ?? false;
}

Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingKey, true);
}

class OnboardingScreen extends StatefulWidget {
  /// Called when the user taps "Get started" on the last page.
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.sports_basketball,
      title: 'Your season, live',
      body: 'RosterIQ pulls this season\'s stats and the injury report every 30 minutes, '
          'and compares every player across the 9 categories.',
    ),
    _OnboardingPage(
      icon: Icons.emoji_events_outlined,
      title: 'Set up your league',
      body: 'Add your roster on My Team, then the other teams on League. '
          'Pick this week\'s opponent to see where you win and lose.',
    ),
    _OnboardingPage(
      icon: Icons.person_add_alt_1,
      title: 'Smarter pickups',
      body: 'Add/Drop ranks free agents by how much they fix your weakest categories, '
          'with games this week and injuries flagged.',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      markOnboardingComplete().then((_) => widget.onComplete());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: last ? null : () => markOnboardingComplete().then((_) => widget.onComplete()),
                child: Text(last ? '' : 'Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _pages[i],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Semantics(
                    label: 'Page ${_page + 1} of ${_pages.length}',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _page ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page ? colors.primary : colors.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: Text(last ? 'Get started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingPage({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 56, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 32),
          Text(title, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
