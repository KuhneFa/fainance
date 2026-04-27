import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../local/categorizer.dart';
import '../../local/csv_parser.dart';

// ── State ─────────────────────────────────────────────────────────────────────
enum UploadStatus { idle, parsing, categorizing, success, error }

class UploadState extends ChangeNotifier {
  UploadStatus status = UploadStatus.idle;
  String? errorMessage;
  CategorizationStats? stats;

  // Ergebnisse werden direkt weitergegeben — kein Server-Round-Trip
  List<Transaction>? transactions;
  AnalysisResult? analysis;

  Future<void> pickAndProcess() async {
    status = UploadStatus.parsing;
    errorMessage = null;
    notifyListeners();

    try {
      // Datei auswählen
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // Bytes direkt laden — kein Dateipfad nötig
      );

      if (result == null || result.files.isEmpty) {
        status = UploadStatus.idle;
        notifyListeners();
        return;
      }

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        throw Exception('Datei konnte nicht gelesen werden.');
      }

      // Schritt 1: CSV parsen (lokal, kein Server)
      final parsed = CsvParser.parse(bytes);

      status = UploadStatus.categorizing;
      notifyListeners();

      // Schritt 2: Kategorisieren (lokal, kein LLM nötig)
      stats = LocalCategorizer.categorizeAll(parsed);

      // Schritt 3: Analyse berechnen
      analysis = LocalCategorizer.analyze(stats!.transactions);
      transactions = stats!.transactions;

      status = UploadStatus.success;
      notifyListeners();
    } catch (e) {
      status = UploadStatus.error;
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  void reset() {
    status = UploadStatus.idle;
    errorMessage = null;
    stats = null;
    transactions = null;
    analysis = null;
    notifyListeners();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _state = UploadState();

  @override
  void initState() {
    super.initState();
    _state.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChange);
    _state.dispose();
    super.dispose();
  }

  void _onStateChange() {
    if (_state.status == UploadStatus.success) {
      // Direkt zum Dashboard — keine upload_id mehr nötig
      Navigator.pushReplacementNamed(
        context,
        '/dashboard',
        arguments: {
          'transactions': _state.transactions,
          'analysis': _state.analysis,
        },
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Text(
                'fainance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Lokale Finanzanalyse.\nKeine Cloud. Keine Kompromisse.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              _buildUploadCard(),
              const Spacer(),
              _buildSupportedBanks(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    final isLoading = _state.status == UploadStatus.parsing ||
        _state.status == UploadStatus.categorizing;

    return GestureDetector(
      onTap: isLoading ? null : _state.pickAndProcess,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isLoading ? const Color(0xFF3B82F6) : const Color(0xFF262626),
          ),
        ),
        child: Column(
          children: [
            if (isLoading) ...[
              const CircularProgressIndicator(
                color: Color(0xFF3B82F6),
                strokeWidth: 2,
              ),
              const SizedBox(height: 16),
              Text(
                _state.status == UploadStatus.parsing
                    ? 'Lese CSV...'
                    : 'Kategorisiere Transaktionen...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            ] else if (_state.status == UploadStatus.error) ...[
              const Icon(Icons.error_outline,
                  color: Color(0xFFEF4444), size: 40),
              const SizedBox(height: 12),
              Text(
                _state.errorMessage ?? 'Unbekannter Fehler',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _state.reset,
                child: const Text('Erneut versuchen'),
              ),
            ] else ...[
              const Icon(Icons.upload_file, color: Color(0xFF3B82F6), size: 40),
              const SizedBox(height: 12),
              const Text(
                'CSV-Kontoauszug auswählen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Daten verlassen nie dein Gerät',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSupportedBanks() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['Sparkasse', 'Deutsche Bank', 'N26', 'DKB'].map((bank) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Text(
            bank,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        );
      }).toList(),
    );
  }
}
