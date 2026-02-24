import io
import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

import pandas as pd

from models import Transaction

logger = logging.getLogger(__name__)


# ── Bank-Format-Definitionen ───────────────────────────────────────────────────
# Ein @dataclass ist wie ein Pydantic-Model, aber für interne Datenstrukturen
# ohne Validierungs-Overhead. Perfekt für Konfigurationsobjekte wie dieses.
@dataclass
class BankFormat:
    """
    Beschreibt wie eine bestimmte Bank ihre CSV-Datei aufbaut.
    Jedes Feld ist der Spaltenname in der Original-CSV der Bank.
    """
    name: str
    date_col: str
    description_col: str
    amount_col: str
    date_format: str          # Python strptime-Format, z.B. "%d.%m.%Y"
    decimal_sep: str = ","    # Deutsche Banken: Komma, N26: Punkt
    thousands_sep: str = "."  # Deutsche Banken: Punkt, N26: kein Separator
    encoding: str = "utf-8"
    skiprows: int = 0         # manche Banken haben Header-Zeilen vor den Spalten


# Bekannte Bankformate – kann einfach erweitert werden
BANK_FORMATS: list[BankFormat] = [
    BankFormat(
        name="Sparkasse",
        date_col="Buchungstag",
        description_col="Verwendungszweck",
        amount_col="Betrag (EUR)",
        date_format="%d.%m.%y",
        decimal_sep=",",
        thousands_sep=".",
        encoding="iso-8859-1",  # Sparkasse nutzt kein UTF-8!
        skiprows=0,
    ),
    BankFormat(
        name="Deutsche Bank",
        date_col="Buchungstag",
        description_col="Verwendungszweck",
        amount_col="Betrag (EUR)",
        date_format="%d.%m.%Y",
        decimal_sep=",",
        thousands_sep=".",
        encoding="utf-8",
        skiprows=0,
    ),
    BankFormat(
        name="N26",
        date_col="Date",
        description_col="Payee",
        amount_col="Amount (EUR)",
        date_format="%Y-%m-%d",
        decimal_sep=".",
        thousands_sep="",
        encoding="utf-8",
        skiprows=0,
    ),
    BankFormat(
        name="DKB",
        date_col="Buchungsdatum",
        description_col="Glaeubiger-ID",  # DKB fasst Infos zusammen
        amount_col="Betrag (EUR)",
        date_format="%d.%m.%Y",
        decimal_sep=",",
        thousands_sep=".",
        encoding="iso-8859-1",
        skiprows=4,  # DKB hat 4 Metadaten-Zeilen am Anfang
    ),
]


# ── Format-Erkennung ───────────────────────────────────────────────────────────
def detect_bank_format(columns: list[str]) -> Optional[BankFormat]:
    """
    Versucht anhand der Spaltennamen zu erkennen, von welcher Bank die CSV kommt.
    Gibt None zurück wenn kein Format passt — dann muss der Nutzer es angeben.
    """
    for fmt in BANK_FORMATS:
        required = {fmt.date_col, fmt.description_col, fmt.amount_col}
        # issubset prüft ob alle required-Spalten in den CSV-Spalten vorhanden sind
        if required.issubset(set(columns)):
            logger.info(f"Bank-Format erkannt: {fmt.name}")
            return fmt
    return None


# ── Betrag normalisieren ───────────────────────────────────────────────────────
def parse_amount(raw: str, decimal_sep: str, thousands_sep: str) -> float:
    """
    Wandelt einen Betrags-String in einen float um.
    Beispiele:
      "1.234,56" (Sparkasse) → 1234.56
      "-42.00"   (N26)       → -42.0
      "1 200,00" (mit Leerzeichen als Tausender) → 1200.0
    """
    if not isinstance(raw, str):
        raw = str(raw)

    # Leerzeichen als Tausender-Separator entfernen (manche Banken)
    cleaned = raw.strip().replace(" ", "")

    # Tausender-Separator entfernen, dann Dezimal-Separator zu Punkt normalisieren
    if thousands_sep:
        cleaned = cleaned.replace(thousands_sep, "")
    cleaned = cleaned.replace(decimal_sep, ".")

    try:
        return float(cleaned)
    except ValueError:
        raise ValueError(f"Konnte Betrag nicht parsen: '{raw}' → '{cleaned}'")


# ── Datum normalisieren ────────────────────────────────────────────────────────
def parse_date(raw: str, date_format: str):
    """
    Parst einen Datums-String in ein Python date-Objekt.
    strptime = "string parse time" — das Gegenteil von strftime.
    """
    try:
        return datetime.strptime(raw.strip(), date_format).date()
    except ValueError:
        raise ValueError(
            f"Konnte Datum nicht parsen: '{raw}' mit Format '{date_format}'. "
            f"Erwartetes Format: z.B. {datetime.now().strftime(date_format)}"
        )


# ── Haupt-Parser ───────────────────────────────────────────────────────────────
def parse_csv(
    file_bytes: bytes,
    bank_format: Optional[BankFormat] = None,
) -> list[Transaction]:
    """
    Liest eine CSV-Datei ein und gibt eine Liste normalisierter Transaktionen zurück.

    Args:
        file_bytes: Der rohe Dateiinhalt als Bytes (kommt direkt vom HTTP-Upload).
        bank_format: Optional. Wenn None, wird das Format automatisch erkannt.

    Returns:
        Liste von validierten Transaction-Objekten.

    Raises:
        ValueError: Wenn das Format nicht erkannt wird oder die CSV fehlerhaft ist.
    """

    # ── Schritt 1: Encoding-Erkennung und Einlesen ────────────────────────────
    # Wir versuchen zuerst utf-8, dann iso-8859-1 (Latin-1).
    # Das deckt ~99% aller deutschen Bank-CSVs ab.
    df = None
    detected_encoding = "utf-8"

    for encoding in ["utf-8", "iso-8859-1", "cp1252"]:
        try:
            skiprows = bank_format.skiprows if bank_format else 0
            df = pd.read_csv(
                io.BytesIO(file_bytes),
                encoding=encoding,
                sep=None,           # pandas erkennt Separator automatisch (,  oder ;)
                engine="python",    # nötig für sep=None
                skiprows=skiprows,
                on_bad_lines="skip",  # fehlerhafte Zeilen überspringen statt crashen
            )
            detected_encoding = encoding
            break
        except UnicodeDecodeError:
            continue

    if df is None:
        raise ValueError(
            "CSV konnte nicht gelesen werden. "
            "Bitte stelle sicher, dass die Datei UTF-8 oder ISO-8859-1 kodiert ist."
        )

    # Leerzeilen und vollständig leere Spalten entfernen
    df = df.dropna(how="all").reset_index(drop=True)
    # Spaltennamen trimmen (manche Banken haben Leerzeichen in Spaltennamen)
    df.columns = [str(c).strip() for c in df.columns]

    logger.info(
        f"CSV eingelesen: {len(df)} Zeilen, Encoding: {detected_encoding}, "
        f"Spalten: {list(df.columns)}"
    )

    # ── Schritt 2: Format erkennen ────────────────────────────────────────────
    if bank_format is None:
        bank_format = detect_bank_format(list(df.columns))

    if bank_format is None:
        raise ValueError(
            f"Bank-Format konnte nicht automatisch erkannt werden. "
            f"Gefundene Spalten: {list(df.columns)}. "
            f"Unterstützte Formate: {[f.name for f in BANK_FORMATS]}"
        )

    # ── Schritt 3: Spalten extrahieren und normalisieren ──────────────────────
    transactions: list[Transaction] = []
    errors: list[str] = []

    for idx, row in df.iterrows():
        try:
            raw_date = str(row[bank_format.date_col])
            raw_desc = str(row[bank_format.description_col])
            raw_amount = str(row[bank_format.amount_col])

            # Zeilen überspringen die offensichtlich keine Transaktionen sind
            # (z.B. Summenzeilen am Ende mancher Bank-CSVs)
            if raw_date.lower() in ("nan", "", "buchungstag", "date"):
                continue

            parsed_date = parse_date(raw_date, bank_format.date_format)
            parsed_amount = parse_amount(
                raw_amount,
                bank_format.decimal_sep,
                bank_format.thousands_sep,
            )

            # Beschreibung säubern: mehrfache Leerzeichen zusammenfassen
            clean_desc = " ".join(raw_desc.split())

            transactions.append(
                Transaction(
                    date=parsed_date,
                    description=clean_desc,
                    amount=parsed_amount,
                )
            )

        except (ValueError, KeyError) as e:
            # Einzelne fehlerhafte Zeilen loggen aber nicht abbrechen.
            # Der Nutzer bekommt am Ende eine Zusammenfassung der Fehler.
            errors.append(f"Zeile {idx + 1}: {e}")
            logger.warning(f"Zeile {idx + 1} übersprungen: {e}")

    if not transactions:
        raise ValueError(
            f"Keine gültigen Transaktionen gefunden. "
            f"Fehler: {'; '.join(errors[:5])}"  # max 5 Fehler anzeigen
        )

    if errors:
        logger.warning(
            f"{len(errors)} von {len(df)} Zeilen konnten nicht geparst werden."
        )

    logger.info(f"Erfolgreich geparst: {len(transactions)} Transaktionen")
    return transactions