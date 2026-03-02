import json
import logging
import re
from typing import Any

import aiohttp

from models import Transaction, InsightRequest, InsightResponse, VALID_CATEGORIES

logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "mistral:7b-instruct-q4_0"
BATCH_SIZE = 20
OLLAMA_TIMEOUT = 120

CATEGORIZE_SYSTEM_PROMPT = f"""You are a JSON-only financial transaction categorizer.
You MUST respond with ONLY a valid JSON array. No explanations. No markdown. No text before or after.

ALLOWED CATEGORIES (use exactly as written):
{json.dumps(sorted(VALID_CATEGORIES), ensure_ascii=False)}

RULES:
- Output ONLY the JSON array, nothing else
- Each item: {{"id": <integer>, "category": "<category>"}}
- Use ONLY categories from the list above
- Positive amounts (income) → "Sonstiges"
- Unknown merchants → "Sonstiges"

EXAMPLE INPUT:
[{{"id":0,"description":"REWE SAGT DANKE","amount":-34.50}},{{"id":1,"description":"Miete Januar","amount":-850.00}},{{"id":2,"description":"Gehalt","amount":2800.00}}]

EXAMPLE OUTPUT (ONLY THIS, NO OTHER TEXT):
[{{"id":0,"category":"Lebensmittel"}},{{"id":1,"category":"Miete"}},{{"id":2,"category":"Sonstiges"}}]"""

INSIGHTS_SYSTEM_PROMPT = """You are a financial advisor. Respond ONLY with a valid JSON object.
No markdown, no explanations, no text outside the JSON.

Required format:
{{
  "summary": "<2-3 sentences in German>",
  "warnings": ["<warning 1>"],
  "tips": ["<tip 1>"],
  "positive": ["<positive 1>"]
}}"""


async def _call_ollama(system_prompt: str, user_message: str) -> str:
    payload: dict[str, Any] = {
        "model": OLLAMA_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "stream": False,
        "options": {"temperature": 0.0, "num_predict": 1024},
    }
    timeout = aiohttp.ClientTimeout(total=OLLAMA_TIMEOUT)
    try:
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{OLLAMA_BASE_URL}/api/chat",
                json=payload,
            ) as response:
                if response.status != 200:
                    error_text = await response.text()
                    raise ConnectionError(f"Ollama Status {response.status}: {error_text}")
                data = await response.json()
                return data["message"]["content"]
    except aiohttp.ClientConnectorError:
        raise ConnectionError("Ollama nicht erreichbar. Starte mit: ollama serve")


def _extract_json(text: str) -> Any:
    text = text.strip()

    # Strategie 1: Direktes Parsen
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Strategie 2: Markdown-Block
    match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if match:
        try:
            return json.loads(match.group(1).strip())
        except json.JSONDecodeError:
            pass

    # Strategie 3: Bracket-Counting — findet exakten JSON-Block
    for start_char, end_char in [("[", "]"), ("{", "}")]:
        start_idx = text.find(start_char)
        if start_idx == -1:
            continue
        depth = 0
        in_string = False
        escape_next = False
        for i, char in enumerate(text[start_idx:], start=start_idx):
            if escape_next:
                escape_next = False
                continue
            if char == "\\" and in_string:
                escape_next = True
                continue
            if char == '"':
                in_string = not in_string
                continue
            if in_string:
                continue
            if char == start_char:
                depth += 1
            elif char == end_char:
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start_idx : i + 1])
                    except json.JSONDecodeError:
                        break

    raise ValueError(f"Kein valides JSON gefunden: {text[:300]}")


async def categorize_transactions(transactions: list[Transaction]) -> list[Transaction]:
    result = [t.model_copy() for t in transactions]
    batches = [result[i : i + BATCH_SIZE] for i in range(0, len(result), BATCH_SIZE)]

    logger.info(f"Kategorisiere {len(transactions)} Transaktionen in {len(batches)} Batches")

    for batch_idx, batch in enumerate(batches):
        logger.info(f"Batch {batch_idx + 1}/{len(batches)}...")
        batch_input = json.dumps(
            [{"id": i, "description": t.description, "amount": t.amount}
             for i, t in enumerate(batch)],
            ensure_ascii=False, separators=(",", ":"),
        )
        try:
            raw = await _call_ollama(CATEGORIZE_SYSTEM_PROMPT, batch_input)
            logger.info(f"Ollama Antwort: {raw[:200]}")
            parsed = _extract_json(raw)
            for item in parsed:
                local_idx = item["id"]
                category = item.get("category", "Sonstiges")
                if category not in VALID_CATEGORIES:
                    logger.warning(f"Ungültige Kategorie '{category}' → 'Sonstiges'")
                    category = "Sonstiges"
                if 0 <= local_idx < len(batch):
                    batch[local_idx] = batch[local_idx].model_copy(update={"category": category})
        except (ValueError, KeyError) as e:
            logger.error(f"Batch {batch_idx + 1} fehlgeschlagen: {e}")
            for i, t in enumerate(batch):
                if t.category is None:
                    batch[i] = t.model_copy(update={"category": "Sonstiges"})

    return result


async def generate_insights(request: InsightRequest) -> InsightResponse:
    analysis = request.analysis
    categories_text = "\n".join(
        f"- {c.category}: {c.total:.2f}€ ({c.percentage:.1f}%)"
        for c in sorted(analysis.categories, key=lambda x: x.total, reverse=True)
    )
    user_message = (
        f"Period: {analysis.period_start} to {analysis.period_end}\n"
        f"Income: {analysis.total_income:.2f}€\n"
        f"Expenses: {analysis.total_expenses:.2f}€\n"
        f"Balance: {analysis.net:.2f}€\n"
        f"Categories:\n{categories_text}"
    )
    if request.user_context:
        user_message += f"\nUser context: {request.user_context}"
    try:
        raw = await _call_ollama(INSIGHTS_SYSTEM_PROMPT, user_message)
        logger.info(f"Insights Antwort: {raw[:300]}")
        parsed = _extract_json(raw)
        return InsightResponse(
            summary=parsed.get("summary", "Keine Zusammenfassung verfügbar."),
            warnings=parsed.get("warnings", []),
            tips=parsed.get("tips", []),
            positive=parsed.get("positive", []),
        )
    except (ValueError, KeyError) as e:
        logger.error(f"Insights fehlgeschlagen: {e}")
        return InsightResponse(
            summary="Analyse konnte nicht generiert werden.",
            warnings=[], tips=[], positive=[],
        )


async def check_ollama_health() -> dict[str, str]:
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"{OLLAMA_BASE_URL}/api/tags",
                timeout=aiohttp.ClientTimeout(total=5),
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    models = [m["name"] for m in data.get("models", [])]
                    if any(OLLAMA_MODEL in m for m in models):
                        return {"status": "ok", "model": OLLAMA_MODEL}
                    return {"status": "model_missing",
                            "message": f"ollama pull {OLLAMA_MODEL}"}
    except Exception as e:
        return {"status": "unreachable", "message": str(e)}