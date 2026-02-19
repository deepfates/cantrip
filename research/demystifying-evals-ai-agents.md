---
title: "Demystifying evals for AI agents"
url: https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents
date_fetched: 2026-02-16
author: Mikaela Grace, Jeremy Hadfield, Rodrigo Olivares, and Jiri De Jonghe
---

## Introduction

Evaluations help development teams deploy AI agents with greater confidence. Without them, issues surface only after users encounter problems, creating reactive debugging cycles. As agents operate across multiple turns -- calling tools, adjusting state, and responding to intermediate outcomes -- their inherent autonomy and flexibility make them challenging to assess compared to single-turn systems.

## The Structure of an Evaluation

An evaluation tests an AI system by providing input and applying grading logic to output. The field distinguishes between single-turn evaluations (straightforward prompt-response-grade) and multi-turn evaluations for complex agent behaviors.

**Key terminology includes:**

- **Task:** A single test with defined inputs and success criteria
- **Trial:** One attempt at a task; multiple trials produce consistent results
- **Grader:** Logic scoring agent performance across multiple assertions
- **Transcript/Trace:** Complete record of all outputs, tool calls, reasoning, and interactions
- **Outcome:** Final environmental state after task completion
- **Evaluation harness:** Infrastructure running end-to-end testing, recording steps, grading, and aggregating results
- **Agent harness:** System enabling models to function as agents through input processing and tool orchestration

## Why Build Evaluations?

Early-stage teams often progress through manual testing and intuition. However, scaling creates a breaking point where "the agent feels worse" lacks verifiable cause without systematic measurement. Evaluations transform debugging from reactive complaint-response cycles into proactive quality management.

Benefits include:

- Specification clarity before building
- Regression detection across changes
- Rapid model adoption assessment
- Baseline metrics on latency, cost, and error rates
- Communication channels between product and research teams

## How to Evaluate AI Agents

### Types of Graders

**Code-based graders** provide speed, objectivity, and reproducibility through string matching, binary tests, static analysis, and outcome verification. They struggle with valid variations from expected patterns.

**Model-based graders** offer flexibility and nuance through rubric scoring, natural language assertions, and pairwise comparisons. They require calibration and introduce non-determinism and expense.

**Human graders** deliver gold-standard quality matching expert judgment but remain expensive, slow, and difficult to scale.

### Capability vs. Regression Evals

Capability evals measure what agents handle well, starting at low pass rates. Regression evals verify continued performance on previously solved tasks, maintaining near-100% pass rates. As capability evals saturate, they graduate to regression suites.

### Agent-Specific Approaches

**Coding agents** naturally fit deterministic evaluation through test suites. Benchmarks like SWE-bench Verified improved from 40% to over 80% in one year by grading solutions against existing tests.

**Conversational agents** require multidimensional assessment: outcome verification, transcript constraints, and rubrics evaluating interaction quality. These often need simulated users for realistic scenarios.

**Research agents** face challenges from subjective quality judgments and shifting ground truth. Combining grader types -- groundedness checks, coverage verification, and source quality assessment -- helps manage these complexities.

**Computer use agents** interact through screenshots and UI elements rather than APIs. Evaluation requires running agents in real or sandboxed environments, verifying both navigation accuracy and backend state changes.

### Handling Non-Determinism

Two metrics capture variability:

- **pass@k:** Probability of at least one correct solution across k attempts
- **pass^k:** Probability all k trials succeed (consistency metric)

## Building Effective Evals: A Practical Roadmap

**Start early with 20-50 tasks** drawn from real user failures rather than waiting for hundreds of tasks. Convert manual checks and bug reports into test cases.

**Write unambiguous tasks with reference solutions.** Two domain experts should independently reach the same verdict. Tasks must be solvable by compliant agents; ambiguous specs cause false failures.

**Build balanced problem sets** testing both occurrence and non-occurrence of behaviors. One-sided evals create one-sided optimization.

**Construct robust eval harnesses** with isolated, clean environments. Shared state between trials introduces correlated failures unrelated to agent performance.

**Design thoughtful graders** emphasizing outcomes over paths. "Great eval design involves choosing the best graders for the agent and the tasks." Avoid penalizing creative valid approaches. Include partial credit for multistep tasks.

**Check transcripts regularly.** Reading actual agent outputs reveals whether graders work properly and whether failures reflect genuine mistakes or eval limitations.

**Monitor for saturation.** When agents pass all solvable tasks, evals provide no improvement signal. Saturation can mask substantial capability gains through small numerical increases.

**Maintain eval suites as living artifacts** through dedicated ownership and routine iteration -- as essential as maintaining unit tests.

## Integration with Other Methods

Automated evaluations represent one component of comprehensive agent assessment. Production monitoring detects real-world failures and distribution drift. A/B testing validates changes with actual user traffic. User feedback surfaces unanticipated issues. Manual transcript review builds failure mode intuition. Systematic human studies provide gold-standard judgments for calibration.

The most effective teams combine these methods, using automated evals for rapid iteration, production monitoring for ground truth, and periodic human review for calibration.

## Conclusion

Teams investing in evaluations accelerate development as "the agent feels worse" becomes actionable through metrics. Development patterns vary by agent type, but fundamental principles remain constant: start early, source realistic tasks, define robust success criteria, combine grader types thoughtfully, maintain sufficient difficulty, iterate on signal quality, and regularly review transcripts. Agent evaluation remains an evolving field requiring ongoing technique adaptation as tasks lengthen, systems collaborate multi-agent style, and work becomes increasingly subjective.
