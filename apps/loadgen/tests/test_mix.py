import random
from collections import Counter

from loadgen.mix import ERROR, SLOW, SUCCESS, choose_path


def test_rates_zero_always_success() -> None:
    rng = random.Random(42)
    for _ in range(100):
        assert choose_path(rng, error_rate=0.0, slow_rate=0.0) == SUCCESS


def test_error_rate_one_always_error() -> None:
    rng = random.Random(42)
    for _ in range(100):
        assert choose_path(rng, error_rate=1.0, slow_rate=0.0) == ERROR


def test_distribution_roughly_matches_rates() -> None:
    rng = random.Random(42)
    counts = Counter(
        choose_path(rng, error_rate=0.2, slow_rate=0.1) for _ in range(10_000)
    )
    assert abs(counts[ERROR] / 10_000 - 0.2) < 0.02
    assert abs(counts[SLOW] / 10_000 - 0.1) < 0.02
    assert abs(counts[SUCCESS] / 10_000 - 0.7) < 0.02
