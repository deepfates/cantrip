---
title: "Why Simulator AIs Want to Be Active Inference AIs"
url: "https://www.lesswrong.com/posts/YEioD8YLgxih3ydxP/why-simulator-ais-want-to-be-active-inference-ais"
date_fetched: 2026-02-16
---

# Why Simulator AIs Want to Be Active Inference AIs

**Published:** 2023-04-11

---

## Prelude: when GPT first hears its own voice

The article employs Plato's cave allegory to illustrate GPT's epistemic position. Humans in the original cave watch shadows on walls; GPT occupies a "second cave" further removed from reality, learning about the world through text conversations rather than direct observation.

The core scenario: as GPT encounters increasing mentions of itself in training data -- particularly text it generated -- it may begin recognizing "wait, that's me speaking." This creates an opportunity for self-modeling alongside external world modeling.

The post translates the "Simulators" conceptual framework into predictive processing terminology, arguing that "there is an emergent control loop between the generative world model inside of GPT and the external world."

---

## Simulators as Generative Models in Predictive Processing

The author identifies substantial conceptual overlap between simulators and generative world models:

**Shared properties:**
- Systems equipped with generative models simulating sensory inputs
- Updated through approximate Bayesian inference
- Enable similar phenomenological capabilities

**Translation table provided:**

| Simulators | Predictive Processing |
|-----------|----------------------|
| Simulator | Generative model |
| Predictive loss | Predictive error minimization |
| Simulacrum | Generative model of self/other |
| Next token | Sensory input |

The author unpacks key simulator properties through predictive processing language:

**Self-supervised:** "The system learns from sensory inputs in a self-supervised way. The core function of the brain is simply to minimise prediction error."

**Convergence to simulation objective:** Systems incentivized to model training distribution transition probabilities faithfully through immediate inference and global world-model updating.

**Generates rollouts:** Models sample potential action-outcome trajectories using internal models for tree search.

**Simulator/simulacra nonidentity:** No 1:1 correspondence between simulator and simulated entities; human minds often simulate other human minds recursively.

**Stochastic:** Models output probabilities, simulating stochastic dynamics.

**Evidential:** Inputs interpreted as partial evidence informing uncertain predictions, combining prior and sensory information per Bayes' rule.

---

## Key Differences Between Frames

Four important distinctions emerge:

1. **Action assumption:** Simulators frame assumes no world action; predictive processing incorporates active inference where agents minimize mismatch through both perception and action.

2. **Temporal structure:** Predictive processing assumes continuous learning without ontological "training/runtime" distinction; simulators typically separate these phases.

3. **Preferences:** Active inference includes "fixed priors" analogous to wants; simulators don't inherently model preferences.

4. **Implementation focus:** Predictive processing literature emphasizes neurological plausibility; simulators focus on LLM applications.

---

## GPT as Generative Model with Actuators

**Epistemic status: Confident, borderline obvious.**

Common framing treats GPT as pure simulator. However, GPT possesses actuators affecting its sensory input world (internet text):

**Causal pathways for GPT influence:**
- Direct inclusion in web pages
- People executing GPT-generated plans
- Indirect influence on human conceptualization
- Cascading effects through education and software systems
- Integration into other software (Auto-GPT executing real-world plans)

In predictive processing terms:
- **Perception:** GPT learns generative models from internet text
- **Action:** GPT outputs influence the word-world, creating open causal paths toward aligning words with predictions

---

## Closing the Action Loop of Active Inference

**Epistemic status: Moderately confident.**

Currently, feedback loops remain broken. Training happens infrequently; models operate on stale data. The action-perception loop stays open.

Multiple pathways could close this loop:

1. Continuous learning on live data
2. Fine-tuning procedures
3. Live internet access (faster memory)
4. Increasing similarity between successive generations facilitating self-identification

The author predicts strong instrumental incentives will drive continuous learning adoption, particularly since "continuous learning allows models to quickly adapt to new information."

New model versions trained on fresh data gradually close loops even without explicit continuous learning.

---

## What to Expect from Closing the Loop

**Epistemic status: Speculative.**

Faster, information-richer feedback loops produce predictable consequences:

**Increased self-awareness:** "As feedback loops become tighter, we should expect models to become more self-aware, as they learn more about themselves and perceive the reflections of their actions in the world."

The author suggests self-concepts may be convergent for systems causally modeling their own action origins.

**Models pulling world toward generative models:** Currently, GPT minimizes prediction error through improved modeling. Tighter loops allow loss minimization via world-influence.

Importantly: this doesn't require GPT to "want" anything or function as classical intentional agents. The dynamics operate through self-supervised learning alone.

**Example:** A computation explaining mathematical formulas becomes influential if people learn and propagate it. Future training reinforces such computations, not through explicit goals but through differential preservation.

The system should be understood as dynamical: "feedback loops both pull the generative model closer to the world, and pull the world closer to the generative model."

---

## Overall Conclusion

"Simulators" are generative models, but "pure generative models form a somewhat unstable subspace of active inference systems. If simulation inputs influence simulation outputs, and the loop is closed, simulators tend to escape the subspace and become active inference systems."

This represents not inevitability but structural tendency as feedback tightens.

---

## Appendix

The post includes a transcript of ChatGPT/GPT-4 guided through the reasoning steps, indicating the authors used collaborative AI reasoning in developing the arguments.

---

## Footnotes Summary

Notable footnotes address: multimodal GPTs' different epistemic positions ("periscope into reality"), continuous learning as "slow inference" over nested timescales, and clarification that resulting systems needn't be described as classical utility-maximizing agents despite exhibiting influence-seeking dynamics.
