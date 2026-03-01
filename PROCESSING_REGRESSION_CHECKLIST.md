# SlideCrop Processing Regression Checklist

## 1) Baseline Lock
- Current known-good tag: `baseline-2026-03-01-main`
- Use this tag as rollback point if processing quality regresses.

## 2) Regression Photo Set (Local)
Keep a fixed photo set on your machine with:
- good crops (clean screen borders)
- hard perspective shots
- podium/speaker leakage cases
- dark/low contrast shots
- non-slide failures

Recommended size:
- quick check: 20 photos
- full check: 50+ photos

## 3) Before Every Processing Change
1. Run quick check set.
2. Verify all 3 flows:
- import -> process
- manual adjust
- save as new / replace originals
3. Note:
- Ready count
- Needs Review count
- obvious wrong AUTO crops

## 4) Performance Check
Use DEBUG logs from `ProcessingViewModel`:
- per-image total ms
- stage timings (load/thumb/process)
- batch total ms
- avg ms/image
- images/sec

Target run:
- same device
- same settings
- same 30-image batch
- 3 runs, compare median

## 5) Merge Gate (Simple)
Only merge to `main` when:
- no obvious new wrong AUTO crops on regression set
- Ready/Review behavior remains reasonable
- throughput is same or better for 30-image batch

