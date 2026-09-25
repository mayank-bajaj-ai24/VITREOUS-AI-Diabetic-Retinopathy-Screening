# Capacity finding

**Finding.** There is no active capacity bottleneck at 400 scheduled patients/day. Ophthalmologist is the most utilised resource (36.6%), but remains below the 90% operating threshold. The simulated camp completes 399 patients/day; mean ophthalmologist wait is 0.3 s and end-of-camp sync backlog is 0 images.

## Baseline evidence

| Resource | Utilisation | Operational reading |
|---|---:|---|
| Camera | 35.0% | 55.0 percentage points below the 90% threshold. |
| Ophthalmologist | 36.6% | 53.4 percentage points below the 90% threshold. |
| Network | 19.9% | 70.1 percentage points below the 90% threshold. |

## Experiments that did not improve completed daily throughput

- Adding cameras from 1 to 4 failed to lift completed throughput above 399 patients/day (399 to 399); camera utilisation only fell from 70.0% to 17.5%.
- Adding ophthalmologists from 1 to 3 failed to lift completed throughput above 399 patients/day (399 to 399); mean review wait fell from 0.3 to 0.0 s.
- Increasing bandwidth from 1 to 20 Mbps failed to lift completed throughput above 399 patients/day (399 to 399), but reduced deferred-sync backlog from 335 to 109 images.
- Changing the confidence threshold from 0.70 to 0.95 failed to lift completed throughput above 399 patients/day (399 to 399) and raised review utilisation from 28.4% to 39.2%.

These are capacity-model outcomes, not clinical-performance claims. The full endpoint data are in `experiment_summary.csv`.

## Evidence-integrity check

The baseline record reports 0 end-of-camp sync backlog, whereas the 5 Mbps bandwidth-sweep endpoint reports 109. These artifacts are not from an identical run set; rerun `run_simulation` after any model or configuration change before using this recommendation operationally.

## Resource recommendation

Within the evaluated grid, the minimum-cost feasible configuration is 1 camera(s), 1 ophthalmologist(s), and 5 Mbps. It delivers 399 patients/day with 70.0% camera, 36.6% review, and 19.9% network utilisation. This is a planning baseline, not a deployment decision: replace illustrative inputs with measured telemetry before use.
