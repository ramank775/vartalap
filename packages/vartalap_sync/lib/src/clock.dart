/// Injectable clock — real time in prod, virtual in tests.
///
/// Every timestamp that lands in `messages.state_updated_at`,
/// `outbound_ops.next_retry_at`, etc. MUST come from a [Clock], not
/// from [DateTime.now] directly. SPIKE_B_SYNC.md §12 mandates this so
/// the retry-backoff e2e test can advance time deterministically.
abstract class Clock {
  int nowMs();

  static const Clock system = _SystemClock();
}

class _SystemClock implements Clock {
  const _SystemClock();
  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch;
}

/// Test clock — advance time by calling [setNowMs].
class FakeClock implements Clock {
  int _now;
  FakeClock([this._now = 0]);

  @override
  int nowMs() => _now;

  set now(int ms) => _now = ms;

  void advance(Duration d) {
    _now += d.inMilliseconds;
  }
}
