import asyncio
import logging
import random

import httpx

from loadgen.config import Settings
from loadgen.mix import choose_path

logger = logging.getLogger("loadgen")


async def run(
    settings: Settings,
    client: httpx.AsyncClient,
    rng: random.Random,
    max_requests: int | None = None,
) -> None:
    """Fire requests at the target, forever by default.

    The sleep between task launches sets the average request rate; the
    semaphore caps in-flight requests so a slow or dead target can't pile
    up unbounded tasks. max_requests exists only so tests can terminate.
    """
    semaphore = asyncio.Semaphore(settings.concurrency)
    interval = 1.0 / settings.rps
    sent = 0
    async with asyncio.TaskGroup() as tg:
        while max_requests is None or sent < max_requests:
            path = choose_path(rng, settings.error_rate, settings.slow_rate)
            tg.create_task(_hit(client, settings.target_url, path, semaphore))
            sent += 1
            await asyncio.sleep(interval)


async def _hit(
    client: httpx.AsyncClient,
    base_url: str,
    path: str,
    semaphore: asyncio.Semaphore,
) -> None:
    async with semaphore:
        try:
            response = await client.get(f"{base_url}{path}")
            logger.info("GET %s -> %s", path, response.status_code)
        except httpx.HTTPError as exc:
            logger.warning("GET %s failed: %s", path, exc)
