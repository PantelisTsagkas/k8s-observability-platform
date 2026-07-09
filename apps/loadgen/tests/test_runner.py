import random
from collections import Counter

import httpx

from loadgen.config import Settings
from loadgen.runner import run


async def test_run_sends_expected_mix() -> None:
    """Drive the runner against a mock transport: no network, but the full
    request path (URL building, concurrency, logging) is exercised."""
    seen: Counter[str] = Counter()

    def handler(request: httpx.Request) -> httpx.Response:
        seen[request.url.path] += 1
        return httpx.Response(200)

    settings = Settings(
        target_url="http://test",
        rps=1000.0,  # keep the inter-request sleep negligible in tests
        error_rate=1.0,  # deterministic: every request goes to /simulate/error
        slow_rate=0.0,
        concurrency=3,
    )
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await run(settings, client, random.Random(1), max_requests=20)

    assert seen == {"/simulate/error": 20}


async def test_run_survives_connect_errors() -> None:
    """A dead target must not crash the runner; it logs and keeps going."""

    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("target down")

    settings = Settings(target_url="http://test", rps=1000.0)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await run(settings, client, random.Random(1), max_requests=5)
