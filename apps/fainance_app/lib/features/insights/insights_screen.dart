import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../local/insights_engine.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightResponse? _insights;
  bool _loading = true;
  String? _error;

  final _currencyFmt = NumberFormat.currency(locale: 'de_DE', symbol: '€');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) {
      _generateInsights();
    }
  }

  Future<void> _generateInsights() async {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
    final analysis = args['analysis'] as AnalysisResult;

    try {
      // Lokal generieren — kein Backend nötig
      final insights = LocalInsightsEngine.generate(analysis);
      setState(() {
        _insights = insights;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'KI-Spartipps',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final i = _insights!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCard(
          icon: Icons.summarize_outlined,
          title: 'Zusammenfassung',
          color: AppColors.accent,
          child: Text(
            i.summary,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
        if (i.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildCard(
            icon: Icons.warning_amber_rounded,
            title: 'Achtung',
            color: const Color(0xFFF59E0B),
            child: Column(
              children: i.warnings
                  .map((w) => _buildBullet(w, const Color(0xFFF59E0B)))
                  .toList(),
            ),
          ),
        ],
        if (i.tips.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildCard(
            icon: Icons.lightbulb_outline,
            title: 'Spartipps',
            color: AppColors.accent,
            child: Column(
              children:
                  i.tips.map((t) => _buildBullet(t, AppColors.accent)).toList(),
            ),
          ),
        ],
        if (i.positive.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildCard(
            icon: Icons.check_circle_outline,
            title: 'Was gut läuft',
            color: AppColors.income,
            child: Column(
              children: i.positive
                  .map((p) => _buildBullet(p, AppColors.income))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline,
                  size: 14, color: Colors.white.withOpacity(0.3)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alle Analysen werden lokal auf deinem Gerät durchgeführt. '
                  'Keine Daten verlassen dein Telefon.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildBullet(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
