from __future__ import annotations

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db.init_db import init_db
from app.routes.imports import router as imports_router
from app.routes.transactions import router as transactions_router
from app.routes.analytics import router as analytics_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield

app = FastAPI(title="Finance AI API", lifespan=lifespan)

# MVP: Next dev server
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(imports_router)
app.include_router(transactions_router)
app.include_router(analytics_router)

@app.get("/health")
def health():
    return {"ok": True}
