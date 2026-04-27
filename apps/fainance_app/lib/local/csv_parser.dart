import 'dart:convert';
import '../core/models.dart';

// ── Bank-Formate ───────────────────────────────────────────────────────────────
class BankFormat {
  final String name;
  final List<String> requiredColumns;
  final String dateColumn;
  final String descriptionColumn;
  final String amountColumn;
  final String dateFormat; // dd.MM.yy oder dd.MM.yyyy oder yyyy-MM-dd
  final String decimalSeparator; // , oder .
  final String thousandSeparator;
  final String delimiter; // ; oder ,

  const BankFormat({
    required this.name,
    required this.requiredColumns,
    required this.dateColumn,
    required this.descriptionColumn,
    required this.amountColumn,
    required this.dateFormat,
    this.decimalSeparator = ',',
    this.thousandSeparator = '.',
    this.delimiter = ';',
  });
}

const _bankFormats = [
  BankFormat(
    name: 'Sparkasse',
    requiredColumns: ['Buchungstag', 'Verwendungszweck', 'Betrag (EUR)'],
    dateColumn: 'Buchungstag',
    descriptionColumn: 'Verwendungszweck',
    amountColumn: 'Betrag (EUR)',
    dateFormat: 'dd.MM.yy',
  ),
  BankFormat(
    name: 'Deutsche Bank',
    requiredColumns: ['Buchungstag', 'Verwendungszweck', 'Betrag (EUR)'],
    dateColumn: 'Buchungstag',
    descriptionColumn: 'Verwendungszweck',
    amountColumn: 'Betrag (EUR)',
    dateFormat: 'dd.MM.yyyy',
  ),
  BankFormat(
    name: 'N26',
    requiredColumns: ['Date', 'Payee', 'Amount (EUR)'],
    dateColumn: 'Date',
    descriptionColumn: 'Payee',
    amountColumn: 'Amount (EUR)',
    dateFormat: 'yyyy-MM-dd',
    decimalSeparator: '.',
    thousandSeparator: ',',
    delimiter: ',',
  ),
  BankFormat(
    name: 'DKB',
    requiredColumns: ['Buchungsdatum', 'Glaeubiger-ID', 'Betrag (EUR)'],
    dateColumn: 'Buchungsdatum',
    descriptionColumn: 'Glaeubiger-ID',
    amountColumn: 'Betrag (EUR)',
    dateFormat: 'dd.MM.yyyy',
  ),
];

// ── Parser ────────────────────────────────────────────────────────────────────
class CsvParser {
  /// Parst CSV-Bytes und gibt Transaktionen zurück.
  /// Erkennt automatisch das Bank-Format.
  static List<Transaction> parse(List<int> bytes) {
    // Encoding-Detection: versuche UTF-8, fallback auf Latin-1
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }

    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw FormatException('CSV-Datei ist leer.');
    }

    // Bank-Format erkennen
    final format = _detectFormat(lines.first);
    if (format == null) {
      throw FormatException(
        'Bank-Format nicht erkannt. '
        'Unterstützt: Sparkasse, Deutsche Bank, N26, DKB.',
      );
    }

    // Header-Index für jede Spalte
    final headers = _splitLine(lines.first, format.delimiter);
    final dateIdx = headers.indexOf(format.dateColumn);
    final descIdx = headers.indexOf(format.descriptionColumn);
    final amountIdx = headers.indexOf(format.amountColumn);

    final transactions = <Transaction>[];

    for (var i = 1; i < lines.length; i++) {
      final cols = _splitLine(lines[i], format.delimiter);
      if (cols.length <= amountIdx) continue;

      try {
        final date = _parseDate(cols[dateIdx].trim(), format.dateFormat);
        final amount = _parseAmount(
          cols[amountIdx].trim(),
          format.decimalSeparator,
          format.thousandSeparator,
        );
        final description = cols[descIdx].trim().replaceAll(
            RegExp(r'\s+'), ' '); // mehrfache Leerzeichen bereinigen

        if (amount == 0.0) continue; // Nullbeträge überspringen

        transactions.add(Transaction(
          date: date,
          description: description,
          amount: amount,
        ));
      } catch (_) {
        continue; // fehlerhafte Zeilen überspringen
      }
    }

    if (transactions.isEmpty) {
      throw FormatException('Keine gültigen Transaktionen gefunden.');
    }

    return transactions;
  }

  static BankFormat? _detectFormat(String headerLine) {
    for (final format in _bankFormats) {
      final headers = _splitLine(headerLine, format.delimiter);
      final hasAll = format.requiredColumns
          .every((col) => headers.any((h) => h.trim() == col));
      if (hasAll) return format;
    }
    return null;
  }

  static List<String> _splitLine(String line, String delimiter) {
    // Berücksichtigt Anführungszeichen: "Wert, mit Komma"
    final result = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == delimiter && !inQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString());
    return result;
  }

  static DateTime _parseDate(String value, String format) {
    // dd.MM.yy oder dd.MM.yyyy oder yyyy-MM-dd
    if (format == 'yyyy-MM-dd') {
      return DateTime.parse(value);
    }

    final parts = value.split('.');
    if (parts.length != 3) {
      throw FormatException('Ungültiges Datum: $value');
    }

    final day = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    var year = int.parse(parts[2]);

    // 2-stellige Jahreszahl: 24 → 2024
    if (year < 100) year += 2000;

    return DateTime(year, month, day);
  }

  static double _parseAmount(
    String value,
    String decimalSep,
    String thousandSep,
  ) {
    var cleaned = value;
    if (thousandSep.isNotEmpty) {
      cleaned = cleaned.replaceAll(thousandSep, '');
    }
    cleaned = cleaned.replaceAll(decimalSep, '.');
    cleaned = cleaned.replaceAll(RegExp(r'[^\d.\-]'), '');

    final amount = double.tryParse(cleaned);
    if (amount == null) {
      throw FormatException('Ungültiger Betrag: $value');
    }
    // Auf 2 Dezimalstellen runden
    return (amount * 100).round() / 100;
  }
}
