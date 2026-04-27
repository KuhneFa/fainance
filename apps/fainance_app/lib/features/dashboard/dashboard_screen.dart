import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../local/insights_engine.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _touchedIndex = -1;
  late AnalysisResult _analysis;
  late List<Transaction> _transactions;
  bool _initialized = false;

  // LLM Insights State
  InsightResponse? _llmInsights;
  bool _llmLoading = false;
  bool _llmAvailable = false; // true wenn Backend erreichbar

  final _currencyFmt = NumberFormat.currency(locale: 'de_DE', symbol: '€');
  final _dateFmt = DateFormat('dd.MM.yyyy', 'de_DE');
  final _dio = Dio(BaseOptions(
    baseUrl: 'http://localhost:8000',
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 120),
  ));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      _analysis = args['analysis'] as AnalysisResult;
      _transactions = args['transactions'] as List<Transaction>;
      _initialized = true;
      _checkBackendAndLoadInsights();
    }
  }

  // ── Backend-Check + LLM Insights laden ────────────────────────────────────
  Future<void> _checkBackendAndLoadInsights() async {
    try {
      await _dio.get('/');
      // Backend erreichbar → LLM-Insights laden
      setState(() {
        _llmAvailable = true;
        _llmLoading = true;
      });
      await _loadLlmInsights();
    } catch (_) {
      // Backend nicht erreichbar → kein LLM-Block, lokale Insights reichen
      setState(() => _llmAvailable = false);
    }
  }

  Future<void> _loadLlmInsights() async {
    try {
      final response = await _dio.post(
        '/insights',
        data: jsonEncode({'analysis': _analysis.toJson()}),
        options: Options(contentType: 'application/json'),
      );
      setState(() {
        _llmInsights = InsightResponse.fromJson(
          response.data as Map<String, dynamic>,
        );
        _llmLoading = false;
      });
    } catch (_) {
      // LLM-Aufruf fehlgeschlagen → lokale Insights als Fallback
      setState(() {
        _llmInsights = LocalInsightsEngine.generate(_analysis);
        _llmLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildStatCards()),
          SliverToBoxAdapter(child: _buildPieChart()),
          // LLM-Block direkt unter dem Pie Chart
          SliverToBoxAdapter(child: _buildLlmInsightsBlock()),
          SliverToBoxAdapter(child: _buildCategoryList()),
          SliverToBoxAdapter(child: _buildInsightsButton()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          _buildTransactionList(),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.background,
      pinned: true,
      title: const Text(
        'Analyse',
        style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Neu laden', style: TextStyle(color: AppColors.accent)),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }

  // ── Stat Cards ─────────────────────────────────────────────────────────────
  Widget _buildStatCards() {
    final items = [
      (
        'Einnahmen',
        _currencyFmt.format(_analysis.totalIncome),
        AppColors.income
      ),
      (
        'Ausgaben',
        _currencyFmt.format(_analysis.totalExpenses),
        AppColors.expense
      ),
      (
        'Saldo',
        _currencyFmt.format(_analysis.net),
        _analysis.net >= 0 ? AppColors.income : AppColors.expense
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: items.map((item) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.$1,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11)),
                  const SizedBox(height: 4),
                  FittedBox(
                    child: Text(item.$2,
                        style: TextStyle(
                            color: item.$3,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Pie Chart ──────────────────────────────────────────────────────────────
  Widget _buildPieChart() {
    final categories = _analysis.categories;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ausgaben nach Kategorie',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) => setState(() {
                    _touchedIndex =
                        response?.touchedSection?.touchedSectionIndex ?? -1;
                  }),
                ),
                sectionsSpace: 2,
                centerSpaceRadius: 60,
                sections: categories.asMap().entries.map((entry) {
                  final i = entry.key;
                  final cat = entry.value;
                  final isTouched = i == _touchedIndex;
                  return PieChartSectionData(
                    value: cat.total,
                    title: isTouched
                        ? '${cat.percentage.toStringAsFixed(1)}%'
                        : '',
                    radius: isTouched ? 50 : 40,
                    color:
                        AppColors.chartColors[i % AppColors.chartColors.length],
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  );
                }).toList(),
              )),
            ),
          ],
        ),
      ),
    );
  }

  // ── LLM Insights Block ─────────────────────────────────────────────────────
  // Erscheint nur wenn Backend erreichbar. Zeigt Ladeindikator während
  // Ollama rechnet, dann Zusammenfassung + erste Warnung + ersten Tipp.
  Widget _buildLlmInsightsBlock() {
    // Backend nicht verfügbar → Block komplett ausblenden
    if (!_llmAvailable) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.accent, size: 16),
                const SizedBox(width: 8),
                Text(
                  'KI-Analyse',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_llmLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Inhalt
            if (_llmLoading)
              Text(
                'Ollama analysiert deine Ausgaben...',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
              )
            else if (_llmInsights != null) ...[
              // Zusammenfassung
              Text(
                _llmInsights!.summary,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.5),
              ),
              // Erste Warnung
              if (_llmInsights!.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _llmChip(
                  icon: Icons.warning_amber_rounded,
                  text: _llmInsights!.warnings.first,
                  color: const Color(0xFFF59E0B),
                ),
              ],
              // Erster Tipp
              if (_llmInsights!.tips.isNotEmpty) ...[
                const SizedBox(height: 8),
                _llmChip(
                  icon: Icons.lightbulb_outline,
                  text: _llmInsights!.tips.first,
                  color: AppColors.accent,
                ),
              ],
              // Link zu vollständigen Insights
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.pushNamed(
                  context,
                  '/insights',
                  arguments: {
                    'analysis': _analysis,
                    'transactions': _transactions,
                  },
                ),
                child: Text(
                  'Alle Tipps anzeigen →',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _llmChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }

  // ── Kategorie-Liste ────────────────────────────────────────────────────────
  Widget _buildCategoryList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: _analysis.categories.asMap().entries.map((entry) {
            final i = entry.key;
            final cat = entry.value;
            final color =
                AppColors.chartColors[i % AppColors.chartColors.length];
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(cat.category,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  Text(_currencyFmt.format(cat.total),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${cat.percentage.toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: cat.percentage / 100,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Insights Button ────────────────────────────────────────────────────────
  Widget _buildInsightsButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.pushNamed(
            context,
            '/insights',
            arguments: {
              'analysis': _analysis,
              'transactions': _transactions,
            },
          ),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Alle KI-Tipps anzeigen'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  // ── Transaktionsliste ──────────────────────────────────────────────────────
  Widget _buildTransactionList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Transaktionen (${_transactions.length})',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            );
          }
          final t = _transactions[index - 1];
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.description,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(_dateFmt.format(t.date),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12)),
                      if (t.category != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(t.category!,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              Text(
                _currencyFmt.format(t.amount),
                style: TextStyle(
                    color: t.amount > 0 ? AppColors.income : AppColors.expense,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ]),
          );
        },
        childCount: _transactions.length + 1,
      ),
    );
  }
}
