---
title: "Cheap RL Tasks Will Waste Compute"
url: "https://www.mechanize.work/blog/cheap-rl-tasks-will-waste-compute/"
date_fetched: "2026-02-16"
---

Title: Cheap RL tasks will waste compute

URL Source: https://www.mechanize.work/blog/cheap-rl-tasks-will-waste-compute/

Markdown Content:
Ege Erdil, Matthew Barnett, Tamay Besiroglu

 August 18, 2025

When creating RL tasks, one faces a choice between two different approaches. One can either spend a lot of engineering effort per task to make a small number of hand-crafted tasks that provide highly informative reward signals. Or one can employ various methods of procedural generation to create a much larger number of tasks, with less engineering effort per task, at the cost of reduced task diversity and weaker reward signals.

This is essentially a quality vs. quantity tradeoff: at a fixed budget for creating new tasks, producing more tasks means that each task will on average be lower quality, less informative, and cover a narrower slice of the task distribution.

We predict that within about one year, AI labs will favor quality over quantity when procuring RL environments and spend a surprisingly large amount of money on procurement _per RL task_. In particular, we expect that labs will likely soon spend a few thousand dollars per task to post-train their flagship models.

Our argument is simple: since procuring RL tasks cheaply results in lower quality training runs and the compute cost per RL run will soon become very high, AI labs will be strongly incentivized to increase task quality to avoid wasting expensive compute on poor-quality tasks. At current RL compute costs, this argument suggests it’s inefficient for AI labs to spend significantly less than ~$500 per RL task. Within a year, however, this figure is likely to increase roughly fivefold, reaching a few thousand dollars per task.

To justify these numbers, consider the [API price of Grok 4](https://docs.x.ai/docs/models), which right now is $15.00 per 1M output tokens. This represents the actual opportunity cost of compute for running Grok 4, since it indicates that compute used to serve Grok 4 can be sold for inference at this price. On average, a single task in SWE-bench Verified results in a transcript length of [approximately](https://logs.epoch.ai/inspect-viewer/c79c08da/viewer.html?log_file=https%3A%2F%2Flogs.epoch.ai%2Finspect_ai_logs%2FknygsTpEGHyBFW4iSAWzn6.eval) 20,000 tokens. But SWE-bench Verified is over one year old at this point, and in our experience, frontier RL tasks are already resulting in transcripts with an average length of around 100,000 tokens per task. In line with these observations, Epoch AI has [observed](https://epoch.ai/data-insights/output-length) that transcript lengths appear to be growing at a rate of 5x per year. Extrapolating this trend by just one year suggests that transcript lengths for a single RL task will soon be around half a million tokens.

If, as in the [DeepSeek-R1](https://arxiv.org/abs/2501.12948) training run, models are trained with a [group size of 64](https://arxiv.org/abs/2402.03300), and on average each task uses 500,000 tokens at $15 per million tokens, the average cost will be (500,000 tokens × $15 × 64) ÷ 1M = $480 per RL task per run. Moreover, RL tasks are typically reused multiple times across research and production runs. Conservatively assuming five reuses per task, the total lifetime compute expense will be $2,400 for each RL task. Multi-agent orchestration within complex RL environments could increase these compute costs even further.

We think these high compute costs will justify high spending on RL task procurement. The key to understanding our argument is to recognize that data and compute are complementary: to achieve high model performance, labs must spend a significant amount on both. Severely underinvesting in one relative to the other wastes most of your investment. If compute costs are $2,400 per task, then it would make little sense to spend only $100 per task on task procurement, since that would mean getting low-quality RL runs. It would be like putting cheap tires on a Ferrari: the marginal savings on the tires would become negligible compared to the performance sacrificed from the expensive asset.

Applying this logic, we predict that AI labs will increase spending on data procurement and compute proportionally. By this, we don’t just mean that total spending on data will grow in tandem with total spending on compute; rather, we predict that per-task spending on both inputs will rise proportionally, leading to increasingly expensive RL tasks.

If current trends continue, within a few years we may see vastly more elaborate RL tasks than today’s most sophisticated examples; these might involve debugging complex distributed software systems under production-level load, operating mock e-commerce businesses, or optimizing data center operations under realistic workloads and energy constraints.

What does this imply for the RL-environment market? The most obvious implication is that AI labs will increasingly move away from training on procedurally generated RL tasks and tasks produced cheaply by [massive numbers of low-paid contractors](https://www.mechanize.work/blog/sweatshop-data-is-over/). To advance frontier models, they will adopt a more labor-intensive build process that relies on full-time domain experts who spend months developing sustained context and crafting individualized tasks, rather than pursuing cheap automation or contractor outsourcing.

The suppliers who win will be those who deliver the highest-quality, context-rich tasks, ship them rapidly, and price them efficiently given compute costs. Teams that invest in deep domain expertise, rigorous validation, and continuous iteration will gain a durable advantage as labs increasingly prioritize quality over quantity.

Want to build the next generation of highly sophisticated RL environments? [We’re hiring](https://jobs.ashbyhq.com/mechanize) software engineers.

[← Back](https://www.mechanize.work/)
