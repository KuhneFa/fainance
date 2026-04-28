import 'package:flutter/material.dart';

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
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      final analysis = args['analysis'] as AnalysisResult;
      final descriptions = (args['descriptions'] as List<String>?) ?? [];
      _insights = LocalInsightsEngine.generate(
        analysis,
        descriptions: descriptions,
      );
      _initialized = true;
    }
  }

  bool get _isDe => _insights?.language != 'en';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          _isDe ? 'Deine Finanzen' : 'Your Finances',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: _insights == null
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(_insights!),
    );
  }

  Widget _buildContent(InsightResponse i) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Zusammenfassung ──────────────────────────────────────────────────
        _card(
          icon: Icons.bar_chart_rounded,
          title: _isDe ? 'Zusammenfassung' : 'Summary',
          color: AppColors.accent,
          child: Text(i.summary,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  height: 1.5)),
        ),

        // ── Bewusstseins-Analyse ─────────────────────────────────────────────
        if (i.awareness.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            icon: Icons.visibility_outlined,
            title: _isDe ? 'Wo du am meisten buchst' : 'Where you book most',
            color: const Color(0xFF8B5CF6),
            child: Column(
              children: i.awareness.map((a) => _awarenessRow(a)).toList(),
            ),
          ),
        ],

        // ── Warnungen ────────────────────────────────────────────────────────
        if (i.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            icon: Icons.info_outline_rounded,
            title:
                _isDe ? 'Im Vergleich zum Richtwert' : 'Compared to benchmarks',
            color: const Color(0xFFF59E0B),
            child: Column(
              children: i.warnings
                  .map((w) => _bullet(w, const Color(0xFFF59E0B)))
                  .toList(),
            ),
          ),
        ],

        // ── Tipps ────────────────────────────────────────────────────────────
        if (i.tips.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            icon: Icons.lightbulb_outline,
            title: _isDe ? 'Ideen zum Sparen' : 'Ideas to save',
            color: AppColors.accent,
            child: Column(
              children:
                  i.tips.map((t) => _bullet(t, AppColors.accent)).toList(),
            ),
          ),
        ],

        // ── Positives ────────────────────────────────────────────────────────
        if (i.positive.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            icon: Icons.check_circle_outline,
            title: _isDe ? 'Was gut läuft' : 'What\'s going well',
            color: AppColors.income,
            child: Column(
              children:
                  i.positive.map((p) => _bullet(p, AppColors.income)).toList(),
            ),
          ),
        ],

        // ── Disclaimer ───────────────────────────────────────────────────────
        const SizedBox(height: 24),
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
              Icon(Icons.lock_outline,
                  size: 14, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isDe
                      ? 'Alle Analysen laufen lokal auf deinem Gerät. '
                          'Keine Daten verlassen dein Telefon.'
                      : 'All analysis runs locally on your device. '
                          'No data leaves your phone.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Awareness Row — zeigt Buchungsfrequenz ohne Wertung ───────────────────
  Widget _awarenessRow(CategoryAwareness a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.category,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  _isDe
                      ? '${a.bookingCount}× gebucht · ${a.total.toStringAsFixed(2)}€'
                      : '${a.bookingCount}× booked · ${a.total.toStringAsFixed(2)}€',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${a.percentageOfExpenses.toStringAsFixed(1)}%',
              style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
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
          Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _bullet(String text, Color color) {
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
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}
