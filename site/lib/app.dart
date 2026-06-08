import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:synapse_runbooks/pages/home_page.dart';
import 'package:synapse_runbooks/pages/runbook_page.dart';
import 'package:synapse_runbooks/pages/onboarding_page.dart';
import 'package:synapse_runbooks/pages/doc_page.dart';
import 'package:synapse_runbooks/pages/search_page.dart';
import 'package:synapse_runbooks/pages/dashboard_page.dart';
import 'package:synapse_runbooks/pages/hub_page.dart';
import 'package:synapse_runbooks/widgets/sidebar.dart';

final _router = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchPage(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: '/hub',
          builder: (context, state) => const HubPage(),
        ),
        GoRoute(
          path: '/docs/:category/:slug',
          builder: (context, state) {
            final category = state.pathParameters['category']!;
            final slug = state.pathParameters['slug']!;
            return DocPage(category: category, slug: slug);
          },
        ),
        GoRoute(
          path: '/runbook/:slug',
          builder: (context, state) {
            final slug = state.pathParameters['slug']!;
            return RunbookPage(slug: slug);
          },
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingPage(),
        ),
      ],
    ),
  ],
);

class SynapseRunbooksApp extends StatelessWidget {
  const SynapseRunbooksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Synapse Docs',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFD97706),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansKrTextTheme(),
        scaffoldBackgroundColor: const Color(0xFFFAFAF9),
      ),
      routerConfig: _router,
    );
  }
}

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => context.go('/'),
          child: const Text('Synapse Docs'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.dashboard),
            onPressed: () => context.go('/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: '핸드오프 허브',
            onPressed: () => context.go('/hub'),
          ),
        ],
      ),
      drawer: isWide ? null : const Drawer(child: Sidebar()),
      body: Row(
        children: [
          if (isWide)
            const SizedBox(
              width: 280,
              child: Sidebar(),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
