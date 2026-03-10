import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

// ── Insights State ─────────────────────────────────────────────────────────────
class InsightsState extends ChangeNotifier {
  LoadingStatus status = LoadingStatus.loading;
  String? errorMessage;
  InsightResponse? insights;

  final _api = ApiClient();

  Future<void> load(AnalysisResult analysis) async {
    status = LoadingStatus.loading;
    notifyListeners();

    try {
      insights = await _api.getInsights(analysis);
      status = LoadingStatus.success;
    } on Exception catch (e) {
      errorMessage = parseApiError(e);
      status = LoadingStatus.error;
    }

    notifyListeners();
  }
}

enum LoadingStatus { loading, success, error }

// ── Insights Screen ────────────────────────────────────────────────────────────
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final analysis =
        ModalRoute.of(context)!.settings.arguments as AnalysisResult;

    return ChangeNotifierProvider(
      create: (_) => InsightsState()..load(analysis),
      child: const _InsightsView(),
    );
  }
}

class _InsightsView extends StatelessWidget {
  const _InsightsView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InsightsState>();

    return Scaffold(
      appBar: AppBar(title: const Text('KI-Analyse')),
      body: switch (state.status) {
        LoadingStatus.loading => _LoadingView(),
        LoadingStatus.error => _ErrorView(message: state.errorMessage!),
        LoadingStatus.success => _SuccessView(insights: state.insights!),
      },
    );
  }
}

// ── Loading ────────────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'KI analysiert deine Finanzen…',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Das lokale Sprachmodell arbeitet.\nEinen Moment Geduld.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ── Error ──────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.expense, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Success ────────────────────────────────────────────────────────────────────
class _SuccessView extends StatelessWidget {
  final InsightResponse insights;
  const _SuccessView({required this.insights});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Zusammenfassung ──────────────────────────────────────────────────
        _SectionCard(
          icon: Icons.auto_awesome,
          iconColor: AppColors.accent,
          title: 'Zusammenfassung',
          child: Text(
            insights.summary,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  fontSize: 14,
                ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Warnungen ────────────────────────────────────────────────────────
        if (insights.warnings.isNotEmpty) ...[
          _SectionCard(
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.warning,
            title: 'Achtung',
            child: _InsightList(
              items: insights.warnings,
              color: AppColors.warning,
              bulletIcon: Icons.arrow_upward_rounded,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Spartipps ────────────────────────────────────────────────────────
        if (insights.tips.isNotEmpty) ...[
          _SectionCard(
            icon: Icons.lightbulb_outline,
            iconColor: AppColors.accent,
            title: 'Spartipps',
            child: _InsightList(
              items: insights.tips,
              color: AppColors.accent,
              bulletIcon: Icons.chevron_right_rounded,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Positives ────────────────────────────────────────────────────────
        if (insights.positive.isNotEmpty)
          _SectionCard(
            icon: Icons.check_circle_outline,
            iconColor: AppColors.positive,
            title: 'Was gut läuft',
            child: _InsightList(
              items: insights.positive,
              color: AppColors.positive,
              bulletIcon: Icons.check_rounded,
            ),
          ),

        const SizedBox(height: 32),

        // ── Disclaimer ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  size: 14, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Diese Analyse wird lokal von einem KI-Modell generiert '
                  'und ersetzt keine professionelle Finanzberatung.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Wiederverwendbare Komponenten ──────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header mit Icon und Titel
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InsightList extends StatelessWidget {
  final List<String> items;
  final Color color;
  final IconData bulletIcon;

  const _InsightList({
    required this.items,
    required this.color,
    required this.bulletIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bullet Icon
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(bulletIcon, size: 11, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 13,
                        height: 1.5,
                      ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
