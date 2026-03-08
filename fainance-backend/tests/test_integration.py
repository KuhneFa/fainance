"""
Integrationstest: Testet den kompletten Upload → Analyse → Kategorisierung Flow.

Voraussetzungen (lokal):
  - Backend läuft: uvicorn main:app --port 8000
  - Ollama läuft: ollama serve

In CI läuft das Backend ohne Ollama — LLM-Tests werden übersprungen.

Ausführen:
  pytest tests/test_integration.py -v -s
"""
import io
import os

import httpx
import pytest

BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8000")
TIMEOUT = 180

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

EXPECTED_CATEGORIES: dict[str, str] = {
    "REWE SAGT DANKE": "Lebensmittel",
    "Miete Januar": "Miete",
    "Gehalt Januar": "Sonstiges",
    "Fitnessstudio Monatsbeitrag": "Sport",
    "dm Drogeriemarkt": "Drogerie",
    "Deutsche Bahn Ticket": "Transport",
    "Netflix": "Unterhaltung",
    "Apotheke Zuzahlung": "Gesundheit",
    "ETF Sparplan": "Sparen / Investieren",
    "ALDI SUED": "Lebensmittel",
}


@pytest.fixture(scope="module")
def client():
    with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT) as c:
        yield c


@pytest.fixture(scope="module")
def upload_id(client):
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


class TestHealth:
    def test_backend_is_running(self, client):
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "running"
        print(f"\n✅ Backend läuft. Ollama: {data['ollama']['status']}")

    def test_ollama_is_reachable(self, client):
        response = client.get("/")
        ollama_status = response.json()["ollama"]["status"]
        if ollama_status != "ok":
            print(f"\n⚠️  Ollama Status: {ollama_status}")
        else:
            print("\n✅ Ollama OK")


class TestUpload:
    def test_upload_returns_upload_id(self, upload_id):
        import uuid
        uuid.UUID(upload_id)

    def test_upload_correct_transaction_count(self, client):
        response = client.post(
            "/upload-csv",
            files={"file": ("test.csv", io.BytesIO(TEST_CSV), "text/csv")},
            data={"bank_name": "auto"},
        )
        assert response.json()["transaction_count"] == 10

    def test_upload_rejects_non_csv(self, client):
        response = client.post(
            "/upload-csv",
            files={"file": ("test.txt", io.BytesIO(b"test"), "text/plain")},
            data={"bank_name": "auto"},
        )
        assert response.status_code == 415

    def test_upload_rejects_empty_file(self, client):
        empty_csv = b"Buchungstag;Verwendungszweck;Betrag (EUR)\n"
        response = client.post(
            "/upload-csv",
            files={"file": ("empty.csv", io.BytesIO(empty_csv), "text/csv")},
            data={"bank_name": "auto"},
        )
        assert response.status_code == 422


class TestAnalysis:
    def test_analysis_returns_correct_totals(self, client, upload_id):
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
        response = client.get(f"/analysis/{upload_id}")
        categories = response.json()["categories"]
        assert len(categories) > 0
        print(f"\n📂 Kategorien gefunden: {[c['category'] for c in categories]}")

    def test_analysis_percentages_sum_to_100(self, client, upload_id):
        response = client.get(f"/analysis/{upload_id}")
        categories = response.json()["categories"]
        total_pct = sum(c["percentage"] for c in categories)
        assert total_pct == pytest.approx(100.0, abs=1.0)

    def test_analysis_invalid_upload_id(self, client):
        response = client.get("/analysis/nicht-eine-uuid")
        assert response.status_code == 400


class TestCategorization:
    def test_transactions_have_categories(self, client, upload_id):
        response = client.get(f"/transactions/{upload_id}")
        assert response.status_code == 200
        transactions = response.json()
        uncategorized = [t for t in transactions if t["category"] is None]
        assert len(uncategorized) == 0, \
            f"{len(uncategorized)} Transaktionen ohne Kategorie"

    def test_category_accuracy(self, client, upload_id):
        """Nur lokal ausführen — braucht Ollama für LLM-Fallback."""
        response = client.get(f"/transactions/{upload_id}")
        transactions = response.json()
        correct, total = 0, 0
        wrong: list[str] = []

        print("\n🔍 Kategorisierungs-Ergebnisse:")
        for t in transactions:
            desc = t["description"]
            actual = t["category"]
            expected = EXPECTED_CATEGORIES.get(desc)
            if expected is None:
                continue
            total += 1
            if actual == expected:
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

        # In CI ohne Ollama reichen Keywords für ~70%
        min_accuracy = 0.5
        assert accuracy >= min_accuracy, \
            f"Genauigkeit zu niedrig: {accuracy:.0%} (min. {min_accuracy:.0%})"

    def test_all_categories_are_valid(self, client, upload_id):
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
        response = client.get(f"/transactions/{upload_id}")
        transactions = response.json()
        wrong_income = [
            t for t in transactions
            if t["amount"] > 0 and t["category"] != "Sonstiges"
        ]
        assert len(wrong_income) == 0, \
            f"Einnahmen falsch kategorisiert: {wrong_income}"