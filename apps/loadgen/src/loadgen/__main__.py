import asyncio
import logging
import random

import httpx

from loadgen.config import Settings
from loadgen.runner import run


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    settings = Settings()
    logger = logging.getLogger("loadgen")
    logger.info(
        "starting: target=%s rps=%s error_rate=%s slow_rate=%s concurrency=%s",
        settings.target_url,
        settings.rps,
        settings.error_rate,
        settings.slow_rate,
        settings.concurrency,
    )

    async def _run() -> None:
        async with httpx.AsyncClient(timeout=10.0) as client:
            await run(settings, client, random.Random())

    asyncio.run(_run())


if __name__ == "__main__":
    main()
