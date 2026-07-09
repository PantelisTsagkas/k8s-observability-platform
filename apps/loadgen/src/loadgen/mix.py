import random

SUCCESS = "/simulate/success"
ERROR = "/simulate/error"
SLOW = "/simulate/slow"


def choose_path(rng: random.Random, error_rate: float, slow_rate: float) -> str:
    """Pick the next endpoint to hit.

    One roll in [0, 1): the first error_rate slice maps to the error
    endpoint, the next slow_rate slice to the slow one, the rest to
    success. The rng is injected so tests can seed it.
    """
    roll = rng.random()
    if roll < error_rate:
        return ERROR
    if roll < error_rate + slow_rate:
        return SLOW
    return SUCCESS
