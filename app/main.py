import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field

from model import FEATURE_NAMES, IrisClassifier

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("inference")

_model: IrisClassifier | None = None
_startup_error: str | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _model, _startup_error
    start = time.monotonic()
    try:
        _model = IrisClassifier()
        logger.info("model loaded in %.3fs", time.monotonic() - start)
    except Exception as exc:  # noqa: BLE001 - surfaced via /readyz instead of crashing
        _startup_error = str(exc)
        logger.exception("model failed to load")
    yield


app = FastAPI(title="knative-inference-demo", lifespan=lifespan)
Instrumentator().instrument(app).expose(app, endpoint="/metrics")


class PredictRequest(BaseModel):
    features: list[float] = Field(
        ..., min_length=4, max_length=4, description=f"Order: {FEATURE_NAMES}"
    )


class PredictResponse(BaseModel):
    predicted_class: str
    probabilities: dict[str, float]


@app.get("/healthz")
def healthz() -> dict:
    """Liveness: the process is up and serving requests."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> dict:
    """Readiness: the model is loaded and able to serve predictions."""
    if _model is None:
        raise HTTPException(status_code=503, detail=_startup_error or "model not loaded")
    return {"status": "ready"}


@app.post("/predict", response_model=PredictResponse)
def predict(request: PredictRequest) -> PredictResponse:
    if _model is None:
        raise HTTPException(status_code=503, detail="model not loaded")
    result = _model.predict(request.features)
    return PredictResponse(predicted_class=result["class"], probabilities=result["probabilities"])
