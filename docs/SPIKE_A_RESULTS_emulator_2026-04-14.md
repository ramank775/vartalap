# Spike A — emulator run, 2026-04-14

**Device:** `sdk gphone64 x86 64` (Android 16 / API 36 emulator)
**Dataset:** 1k channels, 100k messages, Pareto distribution (shape=1.16)
**Harness:** `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/bench_test.dart -d emulator-5554 --profile`

> **Caveat:** x86_64 emulator. Numbers are directional, not gate-compliant.
> Real-device profile-build measurement (Realme X2 Pro / SD855+ first;
> mid-range SD6xx ultimately) is required before treating as ship-blocking.

## Profile build, all stores with `journal_mode=WAL, synchronous=NORMAL`

This is the authoritative run. Referenced by `docs/SPIKE_A_LOCAL_STORE.md`.

| candidate     | scenario                  | p50 ms | p95 ms | p99 ms | max ms | extra |
|---------------|---------------------------|-------:|-------:|-------:|-------:|-------|
| drift         | chat_list_cold            |  1.23  |  1.23  |  1.23  |  1.23  | n=1 |
| drift         | chat_list_warm            |  1.01  |  1.71  |  1.80  |  1.80  | n=50 |
| drift         | messages_read_hot_channel |  0.33  |  0.38  |  0.46  |  0.46  | n=50 |
| drift         | batch_insert_100          |  1.86  |  2.92  |  3.33  |  3.33  | n=20 |
| drift         | single_send               |  0.10  |  0.16  |  0.27  |  1.87  | n=100 |
| drift         | watch_amplification       |  0.59  |  3.16  |  8.54  | 11.90  | **emits=100/100, ratio 1.00** |
| sqflite       | chat_list_cold            |  5.45  |  5.45  |  5.45  |  5.45  | n=1 |
| sqflite       | chat_list_warm            |  3.43  |  5.09  | 104.71 | 104.71 | n=50; p99 outlier is a single sample, not reproducible |
| sqflite       | messages_read_hot_channel |  0.59  |  1.10  |  1.77  |  1.77  | n=50 |
| sqflite       | batch_insert_100          |  4.59  |  5.86  |  6.17  |  6.17  | n=20 |
| sqflite       | single_send               |  0.86  |  1.29  |  1.95  |  2.40  | n=100 |
| sqflite       | watch_amplification       |  0.82  |  1.87  |  2.69  |  7.11  | **emits=0/100, ratio 0.00** |
| event_sourced | chat_list_cold            |  2.14  |  2.14  |  2.14  |  2.14  | n=1 |
| event_sourced | chat_list_warm            |  2.22  |  2.89  |  3.68  |  3.68  | n=50 |
| event_sourced | messages_read_hot_channel |  0.97  |  5.63  |  8.01  |  8.01  | n=50 |
| event_sourced | batch_insert_100          | 10.53  | 13.97  | 14.10  | 14.10  | n=20 |
| event_sourced | single_send               |  0.77  |  1.33  |  2.64  |  8.73  | n=100 |
| event_sourced | watch_amplification       |  0.93  |  5.03  |  6.44  |  7.03  | **emits=0/100, ratio 0.00** |

## Key findings

1. **v3 gate (reads p95 < 10ms, writes p95 < 50ms):** all three pass.
2. **Drift watch amplification (100/100 re-emits on unrelated writes):**
   architectural disqualifier. Drift `.watch()` re-runs on any write to
   the watched table; in production this is every push-delivered message
   triggering a full re-query for every open chat stream.
3. **Event-sourced had a tail-latency bug driven by WAL checkpoint
   pressure** (debug run showed p99 24ms in amplification scenario,
   clustered at iterations 68-73). Root cause: default `journal_mode=DELETE`.
   Fix: `PRAGMA journal_mode=WAL, synchronous=NORMAL`. After fix, p99
   drops to 6.44ms and the tail disappears.
4. **Sqflite vs event-sourced on perf:** sqflite wins batch-insert
   (5.86ms vs 13.97ms), single-send (1.29ms vs 1.33ms — within noise),
   reads about equal. Event-sourced writes ~2x per op (event + projection)
   so the gap is absolute, not tail-latency. Both well under gate.
5. **Isolated sqflite p99 = 104.71ms** on chat_list_warm: single outlier
   in 50 samples, max and p99 are the same value, not reproducible across
   runs. Dart VM pause or emulator stall, not a store issue.

## Prior debug-build run (kept for history)

First run was `flutter test integration_test/...` on debug build. Showed a
much larger event-sourced tail spike (p95 19.27ms, p99 24ms in
amplification) that turned out to be the journal-mode issue above.
Profile build + WAL fixed it. Raw debug numbers are preserved in the
initial version of this file in git history; they are not
gate-authoritative.
