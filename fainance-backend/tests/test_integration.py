"""
Integrationstest: Testet den kompletten Upload → Analyse → Kategorisierung Flow.

Voraussetzungen:
  - Backend läuft auf localhost:8000 (uvicorn main:app)
  - Ollama läuft mit dem konfigurierten Modell

Ausführen:
  pytest tests/test_integration.py -v -s

Das `-s` Flag zeigt print-Ausgaben — nützlich um die Kategorien zu sehen.
"""
import pytest
import httpx
import io
import os

# ── Konfiguration ──────────────────────────────────────────────────────────────
BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8000")
TIMEOUT = 180  # Sekunden — LLM braucht Zeit

# Test-CSV im Sparkasse-Format mit bekannten Transaktionen
# Wir wissen was die korrekte Kategorie sein sollte → können validieren
TEST_CSV = """Buchungstag;Verwendungszweck;Betrag (EUR)
01.01.24;REWE SAGT DANKE;-45,30
02.01.24;Miete Januar;-850,00
03.01.24;Gehalt Januar;2800,00
04.01.24;Fitnessstudio Monatsbeitrag;-29,90
05.01.24;dm Drogeriemarkt;-22,30
06.01.24;Deutsche Bahn Ticket;-54,00
07.01.24;Netflix;-12,99
08.01.24;Apotheke Zuzahlung;-10,00
09.01.24;ETF Sparplan;-200,00
10.01.24;ALDI SUED;-31,50
""".encode("utf-8")

# Erwartete Kategorien pro Beschreibung
# Wir testen ob das Modell mindestens diese zuordnet
EXPECTED_CATEGORIES: dict[str, str] = {
    "REWE SAGT DANKE": "Lebensmittel",
    "Miete Januar": "Miete",
    "Gehalt Januar": "Sonstiges",           # Einnahmen → immer Sonstiges
    "Fitnessstudio Monatsbeitrag": "Sport",
    "dm Drogeriemarkt": "Drogerie",
    "Deutsche Bahn Ticket": "Transport",
    "Netflix": "Unterhaltung",
    "Apotheke Zuzahlung": "Gesundheit",
    "ETF Sparplan": "Sparen / Investieren",
    "ALDI SUED": "Lebensmittel",
}


# ── Fixtures ───────────────────────────────────────────────────────────────────
@pytest.fixture(scope="module")
def client():
    """HTTP-Client für alle Tests in diesem Modul."""
    with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT) as c:
        yield c


@pytest.fixture(scope="module")
def upload_id(client):
    """
    Führt einmal einen CSV-Upload durch und gibt die upload_id zurück.
    `scope="module"` bedeutet: wird nur einmal pro Test-Datei ausgeführt,
    nicht für jeden einzelnen Test neu. Spart Zeit und API-Calls.
    """
    response = client.post(
        "/upload-csv",
        files={"file": ("test.csv", io.BytesIO(TEST_CSV), "text/csv")},
        data={"bank_name": "auto"},
    )
    assert response.status_code == 201, f"Upload fehlgeschlagen: {response.text}"
    data = response.json()
    print(f"\n✅ Upload erfolgreich: {data['transaction_count']} Transaktionen")
    print(f"   upload_id: {data['upload_id']}")
    return data["upload_id"]


# ── Tests ──────────────────────────────────────────────────────────────────────
class TestHealth:
    def test_backend_is_running(self, client):
        """Prüft ob das Backend erreichbar ist."""
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "running"
        print(f"\n✅ Backend läuft. Ollama: {data['ollama']['status']}")

    def test_ollama_is_reachable(self, client):
        """Prüft ob Ollama läuft — gibt Warning statt Fehler wenn nicht."""
        response = client.get("/")
        ollama_status = response.json()["ollama"]["status"]
        if ollama_status != "ok":
            pytest.warns(UserWarning, match="Ollama")
            print(f"\n⚠️  Ollama Status: {ollama_status}")
        else:
            print(f"\n✅ Ollama OK")


class TestUpload:
    def test_upload_returns_upload_id(self, upload_id):
        """Upload liefert eine gültige UUID zurück."""
        import uuid
        uuid.UUID(upload_id)  # wirft ValueError wenn keine gültige UUID

    def test_upload_correct_transaction_count(self, client):
        """Prüft ob alle Zeilen der CSV geparst wurden."""
        response = client.post(
            "/upload-csv",
            files={"file": ("test.csv", io.BytesIO(TEST_CSV), "text/csv")},
            data={"bank_name": "auto"},
        )
        assert response.json()["transaction_count"] == 10

    def test_upload_rejects_non_csv(self, client):
        """Nur CSV-Dateien erlaubt."""
        response = client.post(
            "/upload-csv",
            files={"file": ("test.txt", io.BytesIO(b"test"), "text/plain")},
            data={"bank_name": "auto"},
        )
        assert response.status_code == 415

    def test_upload_rejects_empty_file(self, client):
        """Leere Dateien werden abgelehnt."""
        empty_csv = b"Buchungstag;Verwendungszweck;Betrag (EUR)\n"
        response = client.post(
            "/upload-csv",
            files={"file": ("empty.csv", io.BytesIO(empty_csv), "text/csv")},
            data={"bank_name": "auto"},
        )
        assert response.status_code == 422


class TestAnalysis:
    def test_analysis_returns_correct_totals(self, client, upload_id):
        """Einnahmen, Ausgaben und Saldo werden korrekt berechnet."""
        response = client.get(f"/analysis/{upload_id}")
        assert response.status_code == 200
        data = response.json()

        print(f"\n📊 Analyse:")
        print(f"   Einnahmen:  {data['total_income']:.2f}€")
        print(f"   Ausgaben:   {data['total_expenses']:.2f}€")
        print(f"   Saldo:      {data['net']:.2f}€")

        assert data["total_income"] == pytest.approx(2800.0, abs=0.01)
        assert data["total_expenses"] == pytest.approx(1255.99, abs=0.01)
        assert data["net"] == pytest.approx(1544.01, abs=0.01)

    def test_analysis_has_categories(self, client, upload_id):
        """Mindestens eine Kategorie muss vorhanden sein."""
        response = client.get(f"/analysis/{upload_id}")
        categories = response.json()["categories"]
        assert len(categories) > 0
        print(f"\n📂 Kategorien gefunden: {[c['category'] for c in categories]}")

    def test_analysis_percentages_sum_to_100(self, client, upload_id):
        """Prozentzahlen müssen zusammen 100% ergeben."""
        response = client.get(f"/analysis/{upload_id}")
        categories = response.json()["categories"]
        total_pct = sum(c["percentage"] for c in categories)
        assert total_pct == pytest.approx(100.0, abs=1.0)  # 1% Toleranz

    def test_analysis_invalid_upload_id(self, client):
        """Ungültige upload_id gibt 400 zurück."""
        response = client.get("/analysis/nicht-eine-uuid")
        assert response.status_code == 400


class TestCategorization:
    def test_transactions_have_categories(self, client, upload_id):
        """Alle Transaktionen müssen eine Kategorie haben."""
        response = client.get(f"/transactions/{upload_id}")
        assert response.status_code == 200
        transactions = response.json()

        uncategorized = [t for t in transactions if t["category"] is None]
        assert len(uncategorized) == 0, \
            f"{len(uncategorized)} Transaktionen ohne Kategorie"

    def test_category_accuracy(self, client, upload_id):
        """
        Kerntest: Prüft wie viele Kategorien korrekt zugeordnet wurden.
        Wir erwarten mindestens 60% Genauigkeit — auch schwächere Modelle
        sollten das schaffen. Mit Mistral/LLaMA sollten es >85% sein.
        """
        response = client.get(f"/transactions/{upload_id}")
        transactions = response.json()

        correct = 0
        total = 0
        wrong: list[str] = []

        print("\n🔍 Kategorisierungs-Ergebnisse:")
        for t in transactions:
            desc = t["description"]
            actual = t["category"]
            expected = EXPECTED_CATEGORIES.get(desc)

            if expected is None:
                continue  # Transaktion nicht im Erwartungs-Dict

            total += 1
            is_correct = actual == expected
            if is_correct:
                correct += 1
                print(f"   ✅ {desc[:30]:<30} → {actual}")
            else:
                wrong.append(f"{desc} → erwartet '{expected}', bekommen '{actual}'")
                print(f"   ❌ {desc[:30]:<30} → {actual} (erwartet: {expected})")

        accuracy = correct / total if total > 0 else 0
        print(f"\n📈 Genauigkeit: {correct}/{total} = {accuracy:.0%}")

        if wrong:
            print("\n❌ Falsch kategorisiert:")
            for w in wrong:
                print(f"   {w}")

        # 60% als Mindestanforderung — anpassen je nach Modell
        assert accuracy >= 0.6, \
            f"Kategorisierungsgenauigkeit zu niedrig: {accuracy:.0%} (min. 60%)"

    def test_all_categories_are_valid(self, client, upload_id):
        """Alle Kategorien müssen aus der erlaubten Liste stammen."""
        from models import VALID_CATEGORIES
        response = client.get(f"/transactions/{upload_id}")
        transactions = response.json()

        invalid = [
            f"{t['description']} → '{t['category']}'"
            for t in transactions
            if t["category"] not in VALID_CATEGORIES
        ]
        assert len(invalid) == 0, f"Ungültige Kategorien: {invalid}"

    def test_income_is_sonstiges(self, client, upload_id):
        """Einnahmen (positive Beträge) müssen als 'Sonstiges' kategorisiert sein."""
        response = client.get(f"/transactions/{upload_id}")
        transactions = response.json()

        wrong_income = [
            t for t in transactions
            if t["amount"] > 0 and t["category"] != "Sonstiges"
        ]
        assert len(wrong_income) == 0, \
            f"Einnahmen falsch kategorisiert: {wrong_income}"
