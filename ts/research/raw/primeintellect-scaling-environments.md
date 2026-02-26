---
title: "Scaling Our Open-Source Environments Program"
url: "https://www.primeintellect.ai/blog/scaling-environments-program"
date_fetched: "2026-02-16"
---

Title: Scaling Our Open-Source Environments Program

URL Source: https://www.primeintellect.ai/blog/scaling-environments-program

Markdown Content:
![Image 1](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/68fff9af17e579de241d4867_cover_env-hub_bounties%20copy.jpg)

October 27, 2025

Today, we're scaling up our open-source environments program to become the global hub for open evals and RL environments.

As part of this, we're committing hundreds of thousands of $ in grants and looking for partners who want to join our mission to accelerate open superintelligence.

In the past 2 months, we've crowdsourced 400+ frontier RL environments & evals through bounties and our RL residency, which had over 500+ applicants.

Through our new large-scale bounty program we will scale this to thousands of open-source environments.

‍

Over the past few weeks, the community crowdsourced environments across:

*   Autonomous AI Research
*   Frontier Evals
*   Browser Automation
*   Theorem Proving
*   Subject-Specific QA
*   Legal/Finance Tasks

and many more domains...

Thank you to all the community members who've contributed an environment or joined the residency so far!

![Image 2](https://cdn.prod.website-files.com/66239f0441b09824acb92c7e/68fffc8312f8e44922e49be6_community-members.png)

We’ve learned a lot over the past 2 months from our Bounties and RL Residency program — scaling past 400+ environments, with 80+ reviewed implementations and 500+ applications for the residency.

Today, we’re committing hundreds of thousands of $ as grants to sponsor builders around the world to help us grow the Environments Hub into the premier platform for open evals and RL environments.

Many of these grants will be in the form of bounties for completing specific environment implementations, such as popular evaluation suites, paper reproductions, or ecosystem integrations.

Prime Intellect Bounty Program - Environments, Evals, and Open Superintelligence
--------------------------------------------------------------------------------

To scale the Environments Hub while maintaining high quality, the bounty program is split into two categories: **Open Access** and **Application-Only Tasks**.

*   **Open Access tasks** can be attempted by anyone, are intended for first-time builders within the Environments Hub ecosystem, and have smaller bounties in the $100-500 range.
*   **Application-Only tasks** are more complex in scope, and have larger bounties ranging from 5000+. They are intended for those who are already comfortable building environments/evals, and will be assigned on an approval basis to builders who apply via this form: [https://form.typeform.com/to/jLfT7v7o](https://form.typeform.com/to/jLfT7v7o)

Bounties are awarded upon successful completion of the task. For Application-Only tasks involving reimplementation of established benchmarks, this will entail full reproduction of known evaluation scores for a relevant subset of models.

### Call for Partners

We are also opening a **Call for Partners** for organizations who are eager to sponsor bounties via this program, or who are otherwise interested in participating (e.g. volunteering reviewer time, donating API credits, suggesting tasks for implementation, formalizing validation criteria, etc).

Apply here: [https://form.typeform.com/to/DkpaAX0d](https://form.typeform.com/to/DkpaAX0d)

Example ideas:

*   Sourcing environments for knowledge or skills in a particular domain of interest (e.g. medicine, materials science, systems programming)
*   Companies interested in sponsoring environments & evals built around their tools
*   Companies or organizations who are training their own models and are seeking custom RL environments.
*   Companies who are creating their own evals and interested in spotlighting work samples on the Environments Hub
*   Academic researchers who are creating their own novel benchmarks -- we are happy to sponsor evaluation costs for benchmarks whose reference implementation is built with verifiers and released on the Environments Hub.

Bounties sponsored by third-party organizations typically will fall within the Application-Only category, and we will assist in matching your task with capable and compatible builders from our community.

Next Steps
----------

Our goal is to establish the Environments Hub as the global center of gravity for building, sharing and accessing RL environments & evals.

We’re excited to scale the scope, complexity and usefulness of environments on the hub to enable the open-source ecosystem to train increasingly competitive and useful models.

We’ve already been training and evaluating INTELLECT-3 on environments & evals contributed by the community over the last months to scale RL post-training by orders of magnitude of our previous efforts.

Let's open-source the tools to build superintelligence.

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

![Image 3](https://cdn.prod.website-files.com/66239f0441b09824acb92c75/678edcd5f221a97f3337fc68_Ellipse%201.png)

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

![Image 4](https://cdn.prod.website-files.com/66239f0441b09824acb92c75/678edcd5f221a97f3337fc68_Ellipse%201.png)

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

ESSAYS

Related Posts
-------------
