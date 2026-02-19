---
title: "Why Evals Haven't Landed Yet - Julia Neagu"
url: "https://x.com/julianeagu/status/1964704824299253888"
date_fetched: 2026-02-16
---

# Julia Neagu on Why Evals Haven't Landed Yet

Julia Neagu shares lessons from building evaluation systems at GitHub Copilot and Quotient, explaining why evaluation tooling hasn't gained traction despite two years of industry discourse.

## Core Problem: Ergonomics Mismatch

The fundamental issue is that evaluation platforms don't align with existing developer workflows. Engineers operate within three familiar contexts: unit tests, CI/CD pipelines, and monitoring systems. Most evaluation platforms emphasize manual review and data analysis -- activities that align with data science roles, not software engineering practices.

Neagu notes: "Engineers are not used to operating in notebooks and spreadsheets, and they will avoid it at all costs." This explains why evaluation adoption remains limited despite widespread evangelism.

## GitHub Copilot's Evaluation Stack

At GitHub, the team implemented:

- A comprehensive benchmarking harness focused on regression testing with public repository code
- A/B testing and production monitoring via telemetry
- Weekly "Shiproom" meetings where executives reviewed experimental results

The approach worked well because code is objectively testable. However, "the pressure to move fast and ship was so high that if something passed A/B, we shipped it."

## Quotient's Pivot

When Neagu co-founded Quotient in 2023, initial offline evaluation approaches failed because customers either "vibe-shipped" or avoided comprehensive dataset building. The company pivoted toward:

- Online evaluation through production tracing and logging
- Automated analysis of agent traces
- Pre-built metrics for detecting critical failures
- Visibility into user-facing issues

## Practical Recommendations

For AI product builders, Neagu recommends: start with rapid shipping and user feedback, add monitoring before launch, track user signals, fix discovered issues, and only invest heavily in systematic evaluation once product-market fit exists.

She concludes that successful companies prioritize shipping velocity over methodical evaluation, checking results afterward rather than delaying deployment for comprehensive testing.
