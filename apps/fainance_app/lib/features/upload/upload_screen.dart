import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

// ── Upload State ───────────────────────────────────────────────────────────────
// ChangeNotifier ist die Basis von Provider. Wenn du `notifyListeners()` rufst,
// werden alle Widgets die diesen Provider beobachten neu gebaut.
class UploadState extends ChangeNotifier {
  UploadStatus status = UploadStatus.idle;
  String? errorMessage;
  String? uploadId;
  int transactionCount = 0;
  double uploadProgress = 0;
  String selectedBank = 'auto';

  final _api = ApiClient();

  final List<String> availableBanks = [
    'auto',
    'Sparkasse',
    'Deutsche Bank',
    'N26',
    'DKB',
  ];

  void selectBank(String bank) {
    selectedBank = bank;
    notifyListeners();
  }

  Future<void> pickAndUpload(BuildContext context) async {
    // ── Datei auswählen ────────────────────────────────────────────────────────
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return; // Nutzer hat abgebrochen

    final file = result.files.single;
    if (file.path == null) {
      _setError('Dateipfad konnte nicht gelesen werden.');
      return;
    }

    // ── Upload starten ─────────────────────────────────────────────────────────
    status = UploadStatus.uploading;
    errorMessage = null;
    uploadProgress = 0;
    notifyListeners();

    try {
      final response = await _api.uploadCsv(
        file.path!,
        file.name,
        bankName: selectedBank,
        onProgress: (sent, total) {
          uploadProgress = sent / total;
          notifyListeners();
        },
      );

      uploadId = response.uploadId;
      transactionCount = response.transactionCount;
      status = UploadStatus.success;
      notifyListeners();

    } on Exception catch (e) {
      _setError(parseApiError(e));
    }
  }

  void reset() {
    status = UploadStatus.idle;
    errorMessage = null;
    uploadId = null;
    transactionCount = 0;
    uploadProgress = 0;
    notifyListeners();
  }

  void _setError(String message) {
    status = UploadStatus.error;
    errorMessage = message;
    notifyListeners();
  }
}

enum UploadStatus { idle, uploading, success, error }


// ── Upload Screen ──────────────────────────────────────────────────────────────
class UploadScreen extends StatelessWidget {
  const UploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UploadState(),
      child: const _UploadView(),
    );
  }
}

class _UploadView extends StatelessWidget {
  const _UploadView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UploadState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance AI'),
        actions: [
          if (state.status == UploadStatus.success)
            TextButton(
              onPressed: state.reset,
              child: const Text(
                'Neu hochladen',
                style: TextStyle(color: AppColors.secondary),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (state.status) {
            UploadStatus.idle => _IdleView(),
            UploadStatus.uploading => _UploadingView(),
            UploadStatus.success => _SuccessView(),
            UploadStatus.error => _ErrorView(),
          },
        ),
      ),
    );
  }
}


// ── Idle: Datei auswählen ──────────────────────────────────────────────────────
class _IdleView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<UploadState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // Headline
        Text(
          'Deine Finanzen,\nanalysiert.',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: 32,
                height: 1.15,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Lade deinen Kontoauszug als CSV hoch.\nDeine Daten bleiben lokal auf deinem Gerät.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),

        const SizedBox(height: 48),

        // Drop-Zone / Upload Button
        _UploadDropZone(),

        const SizedBox(height: 24),

        // Bank-Auswahl
        Text(
          'Bank',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.secondary,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        _BankSelector(),

        const Spacer(),

        // Info-Hinweis unten
        _PrivacyNote(),
      ],
    );
  }
}


class _UploadDropZone extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.read<UploadState>();

    return GestureDetector(
      onTap: () => state.pickAndUpload(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.upload_file_outlined,
                color: AppColors.secondary,
                size: 22,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'CSV-Datei auswählen',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Kontoauszug im CSV-Format',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}


class _BankSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<UploadState>();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.selectedBank,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          style: Theme.of(context).textTheme.bodyLarge,
          items: state.availableBanks.map((bank) {
            return DropdownMenuItem(
              value: bank,
              child: Text(bank == 'auto' ? 'Automatisch erkennen' : bank),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) state.selectBank(value);
          },
        ),
      ),
    );
  }
}


class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 14, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Deine Daten verlassen nie dieses Gerät. Die Analyse läuft lokal.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}


// ── Uploading: Fortschritt ─────────────────────────────────────────────────────
class _UploadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<UploadState>();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animierter Fortschrittsring
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: state.uploadProgress > 0 ? state.uploadProgress : null,
              color: AppColors.accent,
              strokeWidth: 2,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Analysiere Transaktionen…',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Das KI-Modell kategorisiert deine Ausgaben.\nDas kann 1–2 Minuten dauern.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}


// ── Success ────────────────────────────────────────────────────────────────────
class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<UploadState>();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Check Icon
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.income.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.income.withOpacity(0.3)),
          ),
          child: const Icon(Icons.check, color: AppColors.income, size: 22),
        ),
        const SizedBox(height: 24),

        Text(
          '${state.transactionCount} Transaktionen\nverarbeitet.',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 8),
        Text(
          'Alle Ausgaben wurden kategorisiert und sind bereit zur Analyse.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),

        const SizedBox(height: 48),

        // Zum Dashboard
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              // Navigation zum Dashboard mit der uploadId
              Navigator.of(context).pushNamed(
                '/dashboard',
                arguments: state.uploadId,
              );
            },
            child: const Text('Dashboard öffnen'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: state.reset,
            child: const Text('Weitere CSV hochladen'),
          ),
        ),
      ],
    );
  }
}


// ── Error ──────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<UploadState>();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.expense.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.expense.withOpacity(0.3)),
          ),
          child: const Icon(Icons.error_outline, color: AppColors.expense, size: 22),
        ),
        const SizedBox(height: 24),
        Text(
          'Etwas ist\nschiefgelaufen.',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            state.errorMessage ?? 'Unbekannter Fehler',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: state.reset,
            child: const Text('Erneut versuchen'),
          ),
        ),
      ],
    );
  }
}