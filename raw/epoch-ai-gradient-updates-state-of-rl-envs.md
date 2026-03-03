---
title: "An FAQ on Reinforcement Learning Environments"
url: "https://epoch.ai/gradient-updates/state-of-rl-envs"
date_fetched: "2026-02-16"
type: webpage
---

Title: An FAQ on Reinforcement Learning Environments

URL Source: https://epoch.ai/gradient-updates/state-of-rl-envs

Published Time: 2026-01-12T00:00:00+00:00

Markdown Content:
_This post is a collaboration between guest author [Chris Barber](https://x.com/chrisbarber) and [JS Denain](https://jsdena.in/) from Epoch AI. This post is part of our [Gradient Updates](https://epoch.ai/gradient-updates) newsletter, which shares more opinionated or informal takes about big questions in AI progress. These posts solely represent the views of the authors, and do not necessarily reflect the views of Epoch AI as a whole._

Reinforcement learning (RL) environments have become central to how frontier AI labs train their models. In September 2025, The Information [reported](https://www.theinformation.com/articles/anthropic-openai-developing-ai-co-workers?rc=dp0mql) that Anthropic had discussed spending over $1 billion on RL environments over the following year. As Andrej Karpathy put it in his [2025 year-in-review](https://karpathy.bearblog.dev/year-in-review-2025/): by training LLMs on a wide range of verifiable tasks across different environments, “the LLMs spontaneously develop strategies that look like ‘reasoning’ to humans.”

This wave of RL for capabilities started with OpenAI’s o1, which was trained on math and coding problems with verifiable answers. Since then, labs have expanded the range of tasks they train on, all the while scaling the amount of compute spent on RL training.

Without diverse, high-quality environments and tasks to train on, throwing more compute at RL [risks wasting much of it](https://www.mechanize.work/blog/cheap-rl-tasks-will-waste-compute/). As a result, creating those tasks and environments has become a key bottleneck for scaling capabilities, and a growing market that remains largely behind closed doors.

To understand the emerging industry of building environments and tasks that labs use to RL-train their models, we interviewed[1](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:1) 18 people across RL environment startups, [neolabs](https://www.theinformation.com/articles/investors-chase-neolabs-outflank-openai-anthropic), and frontier labs. We asked them what RL environments and tasks look like, how labs use them, what makes a good one, and where the field is headed.

**Main takeaways:**

*   **Enterprise workflows are a major growth area**. Math and coding tasks came first, but we’re now seeing significant growth in enterprise workflows: tasks like navigating Salesforce, filing reports, or manipulating spreadsheets.
*   **Reward hacking is a top concern**. Interviewees consistently cited robustness against reward hacking as a key quality criterion. Models find ways to game graders, and preventing this requires extensive iteration on both environments and tasks.
*   **Scaling without sacrificing quality is hard**. A major challenge is scaling the quantity of environments and tasks without sacrificing quality. The hard parts are management (coordinating a growing number of task builders) and maintaining good quality assessment processes.

What are RL environments and tasks?
-----------------------------------

In modern reinforcement learning for language models, the model is given a task to accomplish and a set of actions it can take. The model attempts the task, and a grader (typically automated, such as a unit test or an LLM judging against a rubric) assigns a score to its attempts. These scored attempts are then used to update the model’s weights, reinforcing successful strategies.

The RL environment is defined by the set of actions the model can take (running code, thinking out loud, clicking buttons, searching documents) and the surrounding context that determines the effect of these actions (environment variables, file systems, the state of a simulated application). In practice, the environment is often delivered as a Docker container, but not always[2](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:2).

Each task consists of a prompt instructing the model to achieve an objective, and a grader that determines whether (or to what extent) the objective was met. Terminology in this space isn’t fully standardized, and the boundary between “environment” and “task” is somewhat fuzzy[3](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:3). In this piece we discuss both environments and tasks, since they’re often built and sold together.

![Image 1](https://epoch.ai/assets/images/gradient-updates/2025/state-of-rl-envs/example_rl.png)
Here are some examples of environments and the kinds of tasks they could support:

*   A git repository, with tasks like fixing a bug so that unit tests pass, similar to benchmarks like [SWE-bench Verified](https://epoch.ai/blog/what-skills-does-swe-bench-verified-evaluate). The task specifies a git repository at a specific commit with a failing test suite; the environment provides the operating system and tools to interact with the repo; the grader runs the tests and checks that they pass.
*   An Airbnb clone, with tasks like finding the cheapest two-bedroom listing in a given city for specific dates. The environment is a simulated website with realistic listings, prices, and filters; the agent sees a structured representation of the page (like a DOM or accessibility tree) and outputs actions like clicking elements or typing into fields. The grader verifies the final answer.
*   A Bloomberg terminal clone, with tasks like finding the 5-year compound annual growth rate for a list of companies. The environment simulates the terminal’s interface and data; the grader checks whether the returned figures match the correct values.
*   An Excel clone, with tasks like creating a pivot table showing revenue by region from a raw dataset. The environment provides a spreadsheet application with realistic functionality; the grader compares the output against a reference solution.

For computer use environments like the Excel clone, a single environment might support hundreds of different tasks. For coding environments, it’s more common (but not always the case) for each environment to contain just one task, since setting up a repo state is relatively cheap[4](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:4).

How are RL environments used by labs?
-------------------------------------

Each environment and task can be used in three main ways: for reinforcement learning, for benchmarking, or for supervised fine-tuning on trajectories that solve the task.

Reinforcement learning remains the primary use case. As one RL environment startup employee put it: “RL is the main use. We have some requests for creating envs for benchmarking. I’d say perhaps 10-20x more the former vs the latter.” One difference is that benchmarks are typically built for single-turn evaluation, whereas there’s growing interest in RL environments that capture multi-turn interactions between agent and user.

Environments are also used to generate data for supervised learning, by using successful RL trajectories as training examples during midtraining. One interviewee noted: “While it might not drive purchasing today, a well-designed environment can be used as an effective mechanism for synthetic data generation. I feel this will be increasingly important as env development matures and designers target this use-case.”

An interviewee noted that supervised fine-tuning (SFT) had been growing especially for interleaved thinking and tool calling. With SFT, you can choose a single good trajectory and train on that, whereas RL requires multiple trajectories with enough differentiation between them to provide a learning signal. This makes SFT more practical when it’s relatively easy to produce good trajectories but hard to get a reliable grader or enough variation between attempts.

Usage patterns also vary by lab. One RL environment startup founder noted that trailing labs tend to be more interested in SFT than RL: “It’s quite hard to get your really large scale RL pipelines and it’s easy to throw stuff into your SFT mix.”

RL environment companies don’t always have full visibility into how their products are ultimately used, and usage likely changes over time as labs’ training pipelines evolve. As one founder put it when asked how customers use the environments they build: “To what extent are they using it to generate gold trajectories[5](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:5) versus doing RL? I think that would be pretty hard to answer.”

Which companies build RL Environments?
--------------------------------------

A growing number of **specialized startups** focus specifically on building RL environments. They cover a range of domains, from software engineering tasks to computer use to math and finance. Chris compiled a list of startups in this space [here](https://pavlovslist.com/).

**Traditional data providers** like Mercor, Surge, Handshake, and Turing, who used to primarily provide human-labeled data, now also sell RL environments. Part of what you pay for is their QA processes and supervision infrastructure, but as one founder put it, the main value add is “they have the guys”: if you need to scale up task creation quickly, they can staff a project faster than you could hire in-house.

**In-house teams** at model developers are also building environments (_cf._ job postings by [xAI](https://x.ai/careers/open-roles?dept=4025087007) or [Anthropic](https://www.anthropic.com/careers/jobs/5061517008)). This includes both frontier labs and neolabs like Cursor, who can leverage user data to build training tasks. One founder noted there’s been “substantially more in-housing” recently, as labs build out their own data teams. Reasons to do things in-house include avoiding margins paid to vendors, keeping training priorities confidential, and having direct expertise in some domains like AI research.

Finally, **product companies** are natural partners for building environments around their own software. If you’re Salesforce or Slack, you understand your product’s interface and edge cases better than anyone. We’re seeing a wave of partnerships between labs and product companies: Benchling and Anthropic for biology workflows, OpenAI with Shopify and Stripe for shopping, OpenAI’s recent health integrations. While we don’t know the exact details of how these partnerships work, it seems likely that the product companies are often at least collaborating on environment or task creation. In some cases, though, companies are hostile to agent traffic: Amazon has [sued](https://www.reuters.com/business/retail-consumer/perplexity-receives-legal-threat-amazon-over-agentic-ai-shopping-tool-2025-11-04/) Perplexity over its agentic shopping tool and blocked most AI agents from accessing its site.

How much do environments and tasks cost?
----------------------------------------

Costs are highly variable, depending on the domain, complexity, and number of tasks.

Contract sizes are often six to seven figures per quarter. For example, one RL environment founder noted that contracts are often seven figures per quarter or more. A neolab researcher mentioned seeing contracts in the $300k-$500k range, adding that it varies a lot depending on the number of tasks.

Environment costs depend on fidelity. [SemiAnalysis reported](https://newsletter.semianalysis.com/p/rl-environments-and-rl-for-science) that website replicas (“UI gyms”) cost around $20k each. But higher-quality replicas of complex products like Slack can cost significantly more: one interviewee mentioned figures around $300k for these.

Task costs also vary, but multiple interviewees agreed on a ballpark of $200-$2,000 per task. As one RL environment founder put it: “I’ve seen $200 to $2000 mostly. $20k per task would be rare but possible.” A neolab researcher confirmed this range aligns with their experience. The $20k figure comes up for especially complex software engineering tasks, but it’s rare. To put task costs in perspective: [Mechanize estimates](https://www.mechanize.work/blog/cheap-rl-tasks-will-waste-compute) that around $2,400 in compute is spent per task during RL training. This suggests that cheaper, lower-quality tasks might end up wasting that compute.

Exclusivity affects pricing significantly. Environments and tasks can be sold exclusively to one customer or non-exclusively to multiple labs. Two RL environment founders independently agreed that exclusive deals are roughly 4-5x more expensive than non-exclusive ones.

Overall spending in this space is growing rapidly. As mentioned above, The Information [reported](https://www.theinformation.com/articles/anthropic-openai-developing-ai-co-workers?rc=dp0mql) that Anthropic had discussed spending over $1 billion on RL environments over the following year. However, this is still a fraction of compute costs. OpenAI’s R&D compute spend in 2026 is [projected](https://www.theinformation.com/articles/openai-spend-100-billion-backup-servers-ai-breakthroughs?rc=1hiqbr) to be around $19 billion, roughly double the 2025 figure. Even accounting for the fact that Anthropic is smaller than OpenAI, compute spending will still dwarf RL environment spending.

What domains do RL environments cover?
--------------------------------------

Originally, the main domains were mathematics and coding[6](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:6). As one neolab researcher put it: “Coding and in some sense math kickstarted all the RL environments explorations. So code and math are most plentiful.”

Mathematics tasks are relatively easy to produce, since you don’t need to build a complex environment, just tasks with verifiable answers. However, emphasis on math may be declining more recently. One interviewee noted that “math might be shrinking,” and an RL environment founder observed that math tasks are easy to create but don’t transfer as well to other capabilities.

Coding remains a major source of demand. It’s a huge market, and there’s already been demonstrated uplift from training on code tasks. We’re also seeing coding environments go beyond SWE-bench-style tasks. One RL environment founder noted: “I’ve seen code environments go from more simple PASS_TO_PASS and FAIL_TO_PASS[7](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:7) type SWE-bench Verified tasks more towards being productionized. So how does a SWE actually work in an environment? They have GitHub, they have Linear, they have a code IDE.” A key challenge is that many tasks don’t have clean verification criteria beyond “passes unit tests.” As one neolab researcher noted: “There’s probably many solutions that pass the unit tests. But there’s some nicer solutions that have better trade-offs in terms of your engineering design decisions.” This poses a challenge on the grading front.

One of the major growth areas is enterprise workflows: tasks like filing an expense report, creating a pivot table in a spreadsheet, generating slides from a brief, or navigating a CRM to update customer records. One RL environment founder told us: “I think enterprise workflows are going to explode this year. I think labs index very heavily on what’s valuable and what is quantifiable, and enterprise workflows are perfect for that. By enterprise workflows I mean things that are sometimes computer use (e.g. a specific ERP[8](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:8) that has no backend) or sometimes things that involve APIs that can be exposed to an agent and used without computer use.”

Environments for enterprise workflows can take various forms: MCP-style tool integrations, Playwright-style browser interactions, or screenshot-based computer use. Many rely on clones of websites and apps like Slack or SAP. One lab researcher cautioned: “There’s a lot of good reasons to use clones of websites, but what everyone does is vibe code a buggy website which isn’t useful. There’s a large amount of useless bad environments out there for that reason.”

[Prime Intellect’s environment bounties](https://www.primeintellect.ai/blog/scaling-environments-program) give a sense of some of the domains covered by RL environments and how they’re built. They include environments based on prominent benchmarks, environments for interacting with MCP servers, AI research tasks like [nanoGPT Speedrunning](https://docs.google.com/spreadsheets/d/13UDfRDjgIZXsMI2s9-Lmn8KSMMsgk2_zsfju6cx_pNU/edit?gid=650541192#gid=650541192&range=A110), and tasks based on questions sourced from textbooks.

Overall, the main directions in the near future are coding and enterprise workflows. Across both, there’s growing interest in longer-horizon tasks. As one RL environment founder put it: “Long horizon is I think the future direction. Having agents do full end-to-end tasks that involve navigating through multiple tabs, browsers, and then submitting something that involves multi-hop steps.”

A few other directions came up in our interviews: training for multi-turn user interactions rather than just single-turn performance, environments that optimize for multiple goals at once, and environments with tooling allowing researchers to inspect and change trajectories to provide feedback.

What are the top priorities and challenges?
-------------------------------------------

Interviewees consistently cited robustness against reward hacking as the most important quality criterion. As one neolab researcher put it: “Reward hacking is a big issue. The model might cheat by searching up a solution, or if you’re not careful with how you script the repo, by checking out future commits[9](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:9). It needs to be robust. That’s the minimum.” Another framed it similarly: “Soundness matters most: high reward must mean the task was actually solved, not hacked.” Creating robust graders rarely works on the first pass: as one RL environment founder noted, “It takes many many iterations to check against reward hacking.” Notably, this remains a top priority even though models have become [better at not reward hacking over the past year](https://assets.anthropic.com/m/64823ba7485345a7/Claude-Opus-4-5-System-Card.pdf#page=103).

Difficulty calibration also matters. Tasks need to be challenging but not impossible, since if the pass rate is 0% or 100%, the model won’t learn[10](https://epoch.ai/gradient-updates/state-of-rl-envs#fn:10). Moreover, as one RL environment founder noted: “You don’t want it to be zero percent because then there’s a possibility that the task is infeasible, unless you’ve had another annotator do a blind solve and they succeed.” Multiple interviewees mentioned wanting a minimum pass rate of around 2-3%, or at least one success out of 64 or 128 rollouts.

Beyond individual task difficulty, the overall distribution matters. As one neolab researcher put it: “A very important feature of the RL environment is a smooth gradient: diversity in the difficulty of the tasks.” One person noted you might want a mix: some tasks at 0%, some at 5%, and some at 30%. After some training steps, the 0% tasks become learnable. Once a task reaches around 70% pass rate, you might discard it and move on to harder tasks.

Separately, tasks should also be compositional. As one neolab researcher noted: “The skills should not be disparate tasks, they should be similar to each other and leverage common skills.”

Scaling while maintaining quality is the core operational bottleneck. As [Kevin Lu has argued](https://kevinlu.ai/the-only-important-technology-is-the-internet), scaling RL environments is one of the key challenges for continued AI progress. But scaling task creation while maintaining quality is very hard. One RL environment founder noted: “Maintaining quality while scaling is the number one bottleneck that people see. Finding the experts isn’t that hard, but managing them and doing quality control is hard.” A neolab researcher emphasized the management challenge: “It’s not easy to find people to oversee this data construction, the RL environment construction process. The contractors, you need to motivate them. Sure, you’re paying them money. But how do you make sure they’re not just using LLMs? How do you make sure they’re actually verified? Motivating the contractors and doing the quality control is the grunt work.” One RL environment founder noted that their constraint on making more revenue is simply the difficulty of scaling up task creation at the required quality level.

The skills required are a mix of domain expertise, prompting ability, and product sense. Building environments mostly involves engineering skills, but creating good tasks requires something different. As one RL environment founder put it: “Domain knowledge and expert level prompting is more important than ML skills for creating tasks.” A neolab researcher added that product sense matters too: “You want to know how people are actually using these tools.” Having a lot of experience interacting with frontier models is key, as one neolab researcher noted: “You don’t necessarily need to be an AI researcher, but perhaps a very heavy Claude Code user, a prompt whisperer like Riley Goodside, can be better at figuring out what the frontier is than an AI researcher.” Another put it simply: “The people who are probably best at this are the people who create benchmarks that actually get used.”

RL environments have quickly become a major input to frontier AI training. Key challenges include preventing reward hacking and scaling production without sacrificing quality, while demand is growing for enterprise workflows and longer-horizon tasks. This is a fast-moving space, and we expect this picture to look quite different in a year.

_Thank you to all the interviewees, as well as to Jaime Sevilla, Josh You, and Lynette Bye for comments and editing help on this piece._

Notes
-----

1.   We had calls with 9 different people, got text/email input from an additional 9 people, and sanity checks but no input from 4 more people.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:1)

2.   For example, the environments on [Prime Intellect’s environment hub](https://app.primeintellect.ai/dashboard/environments) don’t rely on Docker, instead using a more lightweight approach based on their [verifiers library](https://github.com/PrimeIntellect-ai/verifiers). In some domains, for example most mathematics problems, there isn’t even a need for an environment since the model does not have to use tools.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:2)

3.   In traditional RL terminology, the “environment” encompasses the transition dynamics (how actions affect state), the reward function, and the distribution over starting states. A “task” in that framing is simply a specific starting state. In practice, the way people use these terms varies.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:3)

4.   Here again, the terminology isn’t fully standardized, and varies across domains: some people use “environment” to refer to a single Docker container with one task; others use it to mean a collection of containers with many tasks.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:4)

5.   Gold trajectories are human-verified examples of successfully completing a task, which can be used as training data for supervised fine-tuning.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:5)

6.   In a sense, RLHF and Constitutional AI came before math and coding environments (and, broadening still, physics engines like MuJoCo came even earlier). They both involve training language models with RL, although typically there’s been less emphasis on tool use and environments. In practice, people tend to think of them as separate categories, and the actors involved are often different.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:6)

7.   In SWE-bench Verified, PASS_TO_PASS refers to tests that should continue passing after the model’s edits, while FAIL_TO_PASS refers to tests that were failing before and should pass after the fix.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:7)

8.   ERP stands for Enterprise Resource Planning, software used by businesses to manage day-to-day activities like accounting, procurement, and project management. Examples include SAP and Oracle.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:8)

9.   See [here](https://x.com/tmkadamcz/status/1963996138044096969?s=46) for an example of the model looking at future commits on SWE-bench Verified.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:9)

10.   RL algorithms like [GRPO](https://arxiv.org/abs/2501.12948) improve by comparing different attempts at the same task. If one attempt succeeds and another fails, the model learns to favor the successful strategy. But if every attempt gets the same score (all passing or all failing), there’s no signal about which approaches work better.[↩](https://epoch.ai/gradient-updates/state-of-rl-envs#fnref:10)
