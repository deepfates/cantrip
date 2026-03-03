---
title: "INTELLECT-2 Release: The First 32B Parameter Model Trained Through Globally Distributed Reinforcement Learning"
url: "https://www.primeintellect.ai/blog/intellect-2-release"
date_fetched: "2026-02-16"
---

Title: INTELLECT-2 Release: The First 32B Parameter Model Trained Through Globally Distributed Reinforcement Learning

URL Source: https://www.primeintellect.ai/blog/intellect-2-release

Markdown Content:
![Image 1](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/682104ffd9b893407813e24e_intellect-2-technical-report.png)

May 11, 2025

We're excited to release INTELLECT-2, the first 32B parameter model trained via globally distributed reinforcement learning. Unlike traditional centralized training efforts, INTELLECT-2 trains a reasoning language model using fully asynchronous RL across a dynamic, heterogeneous swarm of permissionless compute contributors.

To enable a training run with this unique infrastructure, we built various components from scratch: we introduce PRIME-RL, our training framework purpose-built for distributed asynchronous reinforcement learning, based on top of novel components such as TOPLOC, which verifies rollouts from untrusted inference workers, and SHARDCAST, which efficiently broadcasts policy weights from training nodes to inference workers.

Beyond infrastructure components, we propose modifications to the standard GRPO training recipe and data filtering techniques that were crucial to achieve training stability and ensure that our model successfully learned its training objective, thus improving upon QwQ-32B.

We open-source INTELLECT-2 along with our code and data, hoping to enable more open research in the field of decentralized training

*   **Detailed Technical Report:**[primeintellect.ai/intellect-2](http://primeintellect.ai/intellect-2)
*   [**INTELLECT-2 on Hugging Face**](https://huggingface.co/collections/PrimeIntellect/intellect-2-68205b03343a82eabc802dc2)
    *   Chat Interface to try it out: [chat.primeintellect.ai](http://chat.primeintellect.ai/)

*   [**prime-rl: – our async RL framework**](https://github.com/PrimeIntellect-ai/prime-rl)

![Image 2](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/68210770ed19e45df800ade8_Screenshot%202025-03-25%20at%2017.46.32%20(2).png)

**Paradigm Shift for Decentralized Training**
---------------------------------------------

Test-time compute scaling with reinforcement learning has emerged as a new scaling axis for large language models (LLMs), enabling improvements by allowing models to spend more time reasoning.

However, reinforcement learning training is typically centralized, requiring large clusters of co-located GPUs and fast interconnect speeds. With INTELLECT-2, we showcase a paradigm shift: reinforcement learning is inherently more asynchronous and well suited for decentralized, globally distributed compute.

Training Infrastructure
-----------------------

We introduce the following key open-source infrastructure components for training INTELLECT-2:

*   [**PRIME-RL**:](https://github.com/PrimeIntellect-ai/prime-rl)
    *   Fully asynchronous reinforcement learning framework designed for decentralized training. Decouples rollout generation, model training, and weight broadcasting. It enables training across heterogeneous, unreliable networks.
    *   The trainer implementation uses PyTorch FSDP2, inference uses vLLM and the verifiers use the [GENESYS](https://github.com/PrimeIntellect-ai/genesys) schema introduced in [SYNTHETIC-1](https://www.primeintellect.ai/blog/synthetic-1-release).

*   **SHARDCAST**: A library for distributing large files via a HTTP-based tree-topology network that efficiently propagates updated model weights to the decentralized inference workers.

‍

![Image 3](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/67fc98b6b2ae65e17cf41926_Blog%20Asset.png)

*   **TOPLOC**:
    *   A locality-sensitive hashing scheme for efficient verifiable inference. It detects tampering or precision changes in model inference and works reliably across nondeterministic GPU hardware.
    *   Inference workers generate the rollouts, these rollout files are uploaded via signed URLs, an on-chain event triggers TOPLOC validators to check them; accepted files feed the trainer, while invalid ones slash and remove the submitting node from the pool.

![Image 4](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/682107b3b1d00e49e0e1d232_toploc-validator.png)

*   [**Protocol Testnet**:](https://github.com/PrimeIntellect-ai/pi-protocol) Provides the infrastructure to aggregate and coordinate global computeresources.
    *   Rust-based orchestrator and discovery service coordinate permissionless workers—nodes auto-register with hardware checks, heartbeats, and _pull_ Docker-container tasks while the orchestrator schedules workloads, tracks health, and records pool ownership and contributions.

![Image 5](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/682107d311028667c6db24ad_image%20(1).png)

Training Recipe
---------------

*   **Training Data & Rewards:**
    *   285k verifiable tasks (math & coding) from **NuminaMath-1.5, Deepscaler**, and [SYNTHETIC-1](https://www.primeintellect.ai/blog/synthetic-1-release).
    *   Binary task reward + length reward lets users budget thinking tokens at inference time.

*   **Two-step asynchronous RL:** The broadcast of new policy weights is fully overlapped with ongoing inference and training—eliminating the communication bottleneck

![Image 6](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/682107ef11028667c6db337a_async-rl-schedule.png)

*   **Two-Sided GRPO Clipping:** Stabilizes training by mitigating gradient spikes with two-sided token probability ratio clipping.

![Image 7](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/6821080742d40ea0c31cfc42_two-sided-clipping.png)

*   **Advanced Data Filtering:** Combines offline and online filtering to select challenging tasks, significantly enhancing model learning efficiency.

![Image 8](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/6821086978179d3909d2a696_data-filtering.png)

*   **Aggressive Gradient Clipping:** Addresses escalating gradient norms at scale, providing improved training stability.

Experiments
-----------

We report results from two main experiments: TARGET-SHORT, an experimental run with short target lengths to train an efficient reasoning model, and, TARGET-LONG, our main run with longer target lengths.

*   **Compute Utilization:** During the two main experiments, we successfully overlapped communication with computation through two-step asynchronous reinforcement learning.
*   **Reward Trajectories:**
    *   Throughout training, we saw significant improvements of our task rewards, indicating that the model improved its performance on our mathematics and coding problems. We also saw a reduction of length penalties, but a much slower one than during our ablation experiments

‍

*   **Benchmark Performance:** We were able to increase the performance of QwQ-32B on mathematics and coding benchmarks.

![Image 9](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/682108892e5b8c350cb40532_benchmarks.png)

*   Overall, as QwQ-32B was already extensively trained with RL, it was difficult to obtain huge amounts of generalized improvement on benchmarks beyond our improvements on the training dataset. To see stronger improvements, it is likely that better base models such as the now available Qwen3, or higher quality datasets and RL environments are needed.

Future Work
-----------

INTELLECT-2 is a first step towards open frontier reasoning models trained in a decentralized fashion. Over the coming months, we’ll work on:

*   **Increasing the Ratio of Inference to Training Compute**
    *   Inference is embarrassingly parallel and communication-free, so more complex RL environments that devote _more_ FLOPs to inference are a natural fit for decentralized training.

*   **Tool Calls & Multi-Turn RL**
    *   To fully leverage inference-time compute for scientific and research progress, we need to give models built-in tools in its reasoning chain—web search, Python interpreters, etc.

*   **Crowdsourcing RL Tasks & Environments**
    *   We believe open-source has a unique advantage here. Distributed RL is still in its early days, and with the right community and contributions, open-source AI can outpace the closed labs.

*   **Model Merging & DiLoCo**
    *   Fuse independently trained RL models—either at the end or continuously via DiLoCo—to create a single unified model, scaling decentralized RL to a lot more compute.

Check out the technical reports for more details: [primeintellect.ai/intellect-2](https://www.primeintellect.ai/intellect-2)

**Join Us**
-----------

INTELLECT-2 demonstrates that globally decentralized RL works. Now, we’re focusing on tool-assisted reasoning, crowdsourcing higher-quality data, and optimizing our infrastructure and training recipe to build frontier open models.

Join us if you want to build open source and decentralized AGI with us.

Eurus-2-PRIME

System Prompt

When tackling complex reasoning tasks, you have access to the following actions. Use them as needed to progress through your thought process. [ASSESS] [ADVANCE] [VERIFY] [SIMPLIFY] [SYNTHESIZE] [PIVOT] [OUTPUT] You should strictly follow the format below: [ACTION NAME] # Your action step 1 # Your action step 2 # Your action step 3 ... Next action: [NEXT ACTION NAME]

User

Quadratic polynomials

and

have leading coefficients

and

respectively. The graphs of both polynomials pass through the two points

and

Find

Eurus-2-PRIME

[ASSESS]

We are given two quadratic polynomials

and

with leading coefficients

and

, respectively. The graphs of both polynomials pass through the points

and

. We need to find the value of

.

[ADVANCE]

Let's express the quadratic polynomials

and

in the general form:

Since the graphs of both polynomials pass through the points

and

, we can substitute these points into the equations of

and

to form a system of equations.

For

:

For

:

[ADVANCE]

Now, we can solve the system of equations for

:

Subtract Equation 1 from Equation 2:

Substitute

into Equation 1:

So, for

, we have:

Next, we can solve the system of equations for

:

Subtract Equation 3 from Equation 4:

Substitute

into Equation 3:

So, for

, we have:

[ADVANCE]

Finally, we can find

:

So, the value of

is

.

INTELLECT-MATH-7B-SFT (ours)

System Prompt

Solve the following math problem efficiently and clearly. Think carefully and step by step about your response and reason before providing a final response. Conclude your response with: \n\nTherefore, the final answer is:

. I hope it is correct.\n\nWhere [answer] is just the final number or expression that solves the problem.

User

Quadratic polynomials

and

have leading coefficients

and

respectively. The graphs of both polynomials pass through the two points

and

Find

![Image 10](https://cdn.prod.website-files.com/66239f0441b09824acb92c75/678edcd5f221a97f3337fc68_Ellipse%201.png)

INTELLECT-MATH-7B-SFT

So I've got this problem here about quadratic polynomials

and

.

has a leading coefficient of

, and

has a leading coefficient of

. Both polynomials pass through the points

and

. I need to find

.

First, since both

and

are quadratic polynomials, I can express them in the general form:

Wait, actually, the leading coefficient is the coefficient of the highest power of

, which for a quadratic is

. So yes,

and

.

Now, both polynomials pass through the points

and

. That means when

,

, and when

,

. Similarly for

.

So, I can set up equations using these points.

First, for

:

Similarly,

Let me calculate

and

:

So,

Now, I have two equations:

1)

2)

I can subtract equation 1 from equation 2 to eliminate

:

So,

Wait, but coefficients are usually integers, but maybe not. Let me check.

Now, plug

back into one of the equations to find

. Let's use equation 1:

So,

Hmm,

would be

, which is

.

Now, let's do the same for

.

Now, equations for

:

1)

2)

Subtract equation 1 from equation 2:

Now, plug

back into equation 1:

So,

Therefore,

Now,

Wait, but the problem says "present the answer in LaTeX format: \boxed{Your answer}"

So, I should write

But let me double-check my calculations to make sure I didn't make any mistakes.

First, for

:

Subtracting:

Then,

Similarly for

:

Subtracting:

Then,

So,

,

, sum is

.

Seems correct.

Final Answer

INTELLECT-MATH-7B (ours)

System Prompt

Solve the following math problem efficiently and clearly. Think carefully and step by step about your response and reason before providing a final response. Conclude your response with: \n\nTherefore, the final answer is:

. I hope it is correct.\n\nWhere [answer] is just the final number or expression that solves the problem.

User

Quadratic polynomials

and

have leading coefficients

and

respectively. The graphs of both polynomials pass through the two points

and

Find

![Image 11](https://cdn.prod.website-files.com/66239f0441b09824acb92c75/678edcd5f221a97f3337fc68_Ellipse%201.png)

INTELLECT-MATH-7B

So I have two quadratic polynomials,

and

, with leading coefficients 2 and -2, respectively. Both pass through the points

and

. I need to find

.

First, since both are quadratic polynomials, I can express them in the general form:

But since both pass through the points

and

, I can set up equations using these points.

For

:

Similarly for

:

Let's compute the squares:

So for

:

For

:

Now, I have two systems of linear equations:

For

:

Subtract equation (1) from equation (2):

Now plug

back into equation (1):

So

For

:

Subtract equation (3) from equation (4):

Now plug

back into equation (3):

So

.

Now,

.

.

Therefore,

.

Final Answer

.

Authors

Acknowledgements

Prime Intellect Research Team: Sami Jaghouar, Justus Mattern, Jack Min Ong, Jannik Straube, Manveer Basra, Aaron Pazdera, Matthew Di Ferrante, Kushal Thaman, Felix Gabriel, Fares Obeid, Kemal Erdem, Michael Keiblinger, Johannes Hagemann

ESSAYS

Related Posts
-------------
