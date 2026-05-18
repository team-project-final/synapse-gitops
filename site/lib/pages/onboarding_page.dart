import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:synapse_runbooks/models/runbook.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  List<RunbookIndex> _steps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSteps();
  }

  Future<void> _loadSteps() async {
    final jsonStr = await rootBundle.loadString('assets/runbooks/index.json');
    final list = json.decode(jsonStr) as List;
    final all = list
        .map((e) => RunbookIndex.fromJson(e as Map<String, dynamic>))
        .toList();

    final onboarding =
        all.where((r) => r.category == RunbookCategory.onboarding).toList();
    final steps =
        all.where((r) => r.category == RunbookCategory.steps).toList();

    setState(() {
      _steps = [...onboarding, ...steps];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '온보딩 워크스루',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '새 팀원을 위한 환경 구축 가이드. 위에서 아래로 순서대로 진행하세요.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Stepper(
            currentStep: 0,
            controlsBuilder: (context, details) => const SizedBox.shrink(),
            steps: [
              for (var i = 0; i < _steps.length; i++)
                Step(
                  title: InkWell(
                    onTap: () => context.go('/runbook/${_steps[i].slug}'),
                    child: Text(_steps[i].title),
                  ),
                  subtitle: _steps[i].duration != null
                      ? Text(_steps[i].duration!)
                      : null,
                  content: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_steps[i].target != null)
                          Text('대상: ${_steps[i].target!}'),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              context.go('/runbook/${_steps[i].slug}'),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('런북 열기'),
                        ),
                      ],
                    ),
                  ),
                  isActive: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
