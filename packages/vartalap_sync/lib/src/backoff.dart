import 'dart:math';

/// Retry backoff policy per SPIKE_B_SYNC.md §6.
///
/// delay(n) = min(base * 2^(n-1), max) * (1 + random(0, 0.3))
abstract class BackoffPolicy {
  Duration delayFor(int attempt);
}

class ExponentialJitterBackoff implements BackoffPolicy {
  final Duration base;
  final Duration max;
  final double jitter;
  final Random _rng;

  ExponentialJitterBackoff({
    this.base = const Duration(seconds: 1),
    this.max = const Duration(minutes: 5),
    this.jitter = 0.3,
    Random? rng,
  }) : _rng = rng ?? Random();

  @override
  Duration delayFor(int attempt) {
    if (attempt < 1) return Duration.zero;
    final nominal = base * pow(2, attempt - 1);
    final clamped = nominal > max ? max : nominal;
    final jitterFactor = 1.0 + _rng.nextDouble() * jitter;
    final ms = (clamped.inMilliseconds * jitterFactor).round();
    return Duration(milliseconds: ms);
  }
}

/// Test policy — deterministic, no jitter, small base. Used by the
/// SPIKE_B_SYNC.md §12 e2e test.
class FixedBackoff implements BackoffPolicy {
  final Duration delay;
  const FixedBackoff(this.delay);

  @override
  Duration delayFor(int attempt) => delay;
}
