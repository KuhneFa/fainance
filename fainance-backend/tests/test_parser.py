"""
Tests für den CSV-Parser und die Datenmodelle.
Ausführen mit: pytest tests/ -v
"""
from datetime import date

import pytest

from models import VALID_CATEGORIES, Transaction
from parser import detect_bank_format, parse_amount, parse_csv, parse_date


def make_sparkasse_csv(rows: list[str]) -> bytes:
    header = "Buchungstag;Verwendungszweck;Betrag (EUR)"
    content = "\n".join([header] + rows)
    return content.encode("utf-8")


class TestTransaction:
    def test_valid_transaction(self):
        t = Transaction(date=date(2024, 1, 1), description="REWE", amount=-34.50)
        assert t.amount == -34.50
        assert t.category is None

    def test_amount_rounded_to_cents(self):
        t = Transaction(date=date(2024, 1, 1), description="Test", amount=-34.567)
        assert t.amount == -34.57

    def test_zero_amount_raises(self):
        with pytest.raises(ValueError, match="darf nicht 0"):
            Transaction(date=date(2024, 1, 1), description="Test", amount=0.0)

    def test_invalid_category_raises(self):
        with pytest.raises(ValueError, match="keine gültige Kategorie"):
            Transaction(
                date=date(2024, 1, 1),
                description="Test",
                amount=-10.0,
                category="Halluzination",
            )

    def test_valid_category_accepted(self):
        for category in VALID_CATEGORIES:
            t = Transaction(
                date=date(2024, 1, 1),
                description="Test",
                amount=-10.0,
                category=category,
            )
            assert t.category == category

    def test_is_expense(self):
        t = Transaction(date=date(2024, 1, 1), description="Test", amount=-10.0)
        assert t.amount < 0

    def test_is_income(self):
        t = Transaction(date=date(2024, 1, 1), description="Gehalt", amount=2800.0)
        assert t.amount > 0


class TestParseAmount:
    def test_german_format(self):
        assert parse_amount("1.234,56", ",", ".") == 1234.56

    def test_english_format(self):
        assert parse_amount("-42.00", ".", "") == -42.0

    def test_negative_german(self):
        assert parse_amount("-850,00", ",", ".") == -850.0

    def test_without_thousands(self):
        assert parse_amount("34,50", ",", ".") == 34.50

    def test_invalid_raises(self):
        with pytest.raises(ValueError, match="Konnte Betrag nicht parsen"):
            parse_amount("kein_betrag", ",", ".")


class TestParseDate:
    def test_german_short_year(self):
        result = parse_date("01.01.24", "%d.%m.%y")
        assert result == date(2024, 1, 1)

    def test_german_long_year(self):
        result = parse_date("15.03.2024", "%d.%m.%Y")
        assert result == date(2024, 3, 15)

    def test_iso_format(self):
        result = parse_date("2024-03-15", "%Y-%m-%d")
        assert result == date(2024, 3, 15)

    def test_invalid_date_raises(self):
        with pytest.raises(ValueError, match="Konnte Datum nicht parsen"):
            parse_date("kein-datum", "%d.%m.%Y")


class TestDetectBankFormat:
    def test_detects_sparkasse(self):
        columns = ["Buchungstag", "Verwendungszweck", "Betrag (EUR)"]
        fmt = detect_bank_format(columns)
        assert fmt is not None
        assert fmt.name == "Sparkasse"

    def test_detects_n26(self):
        columns = ["Date", "Payee", "Amount (EUR)"]
        fmt = detect_bank_format(columns)
        assert fmt is not None
        assert fmt.name == "N26"

    def test_unknown_format_returns_none(self):
        columns = ["Datum", "Empfaenger", "Wert"]
        fmt = detect_bank_format(columns)
        assert fmt is None


class TestParseCsv:
    def test_parses_sparkasse_csv(self):
        csv_bytes = make_sparkasse_csv([
            "01.01.24;REWE SAGT DANKE;-34,50",
            "02.01.24;Gehalt;2800,00",
            "03.01.24;Miete;-850,00",
        ])
        transactions = parse_csv(csv_bytes)
        assert len(transactions) == 3
        assert transactions[0].amount == -34.50
        assert transactions[1].amount == 2800.00
        assert transactions[2].amount == -850.00

    def test_skips_empty_lines(self):
        csv_bytes = make_sparkasse_csv([
            "01.01.24;REWE;-34,50",
            "",
            "03.01.24;Miete;-850,00",
        ])
        transactions = parse_csv(csv_bytes)
        assert len(transactions) == 2

    def test_raises_on_empty_csv(self):
        csv_bytes = b"Buchungstag;Verwendungszweck;Betrag (EUR)\n"
        with pytest.raises(ValueError, match="Keine gültigen Transaktionen"):
            parse_csv(csv_bytes)

    def test_raises_on_unknown_format(self):
        csv_bytes = b"Datum;Empfaenger;Wert\n01.01.24;Test;-10,00\n"
        with pytest.raises(ValueError, match="Bank-Format konnte nicht"):
            parse_csv(csv_bytes)

    def test_descriptions_are_cleaned(self):
        csv_bytes = make_sparkasse_csv([
            "01.01.24;REWE   SAGT   DANKE;-34,50",
        ])
        transactions = parse_csv(csv_bytes)
        assert transactions[0].description == "REWE SAGT DANKE"