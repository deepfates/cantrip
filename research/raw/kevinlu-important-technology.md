---
title: "The Only Important Technology Is the Internet"
url: "https://kevinlu.ai/the-only-important-technology-is-the-internet"
date_fetched: "2026-02-16"
---

Title: The Only Important Technology Is The Internet

URL Source: https://kevinlu.ai/the-only-important-technology-is-the-internet

Published Time: 2025-12-20T20:04:23+00:00

Markdown Content:
Although progress in AI is often attributed to landmark papers – such as [transformers](https://en.wikipedia.org/wiki/Transformer_(deep_learning_architecture)), [RNNs](https://en.wikipedia.org/wiki/Recurrent_neural_network), or [diffusion](https://en.wikipedia.org/wiki/Diffusion_model) – this ignores the fundamental bottleneck of artificial intelligence: the data. But what does it mean to have good data?

If we _truly_ want to advance AI, instead of studying deep learning optimization, we should be studying the internet. The internet is the technology that **_actually_** unlocked the scaling for our AI models.

Transformers are a distraction
------------------------------

![Image 1](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/attention_wager.png)

Inspired by the rapid progress made by architectural innovations (in 5 years, going from AlexNet to the Transformer), many researchers have sought better architecture priors. People [bet](https://www.isattentionallyouneed.com/) on if we could devise a better architecture than the transformer. In truth, there _have_ been better architectures developed since the transformer – but then why is it so hard to “feel” an improvement since GPT-4?

### Shifting regimes

**Compute-bound.** Once upon a time, methods scaled with compute, and we saw that more efficient methods were better. What mattered was packing our data into the models as _efficiently_ as possible, and not only did these methods achieve better results, but they seemed to _improve_ with scale.

![Image 2](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/training_compute_vs_performance.png)

**Data-bound.** Actually, research is not useless. The community has developed better methods since the transformer – such as [SSMs (Albert Gu et al. 2021)](https://arxiv.org/abs/2111.00396) and [Mamba (Albert Gu et al. 2023)](https://arxiv.org/abs/2312.00752) (and more) – but we don’t exactly think of them as being free wins: for a given amount of training compute, we should train a transformer that will perform better.

But the data-bound regime is freeing: all our methods are going to perform the same anyway! So we should pick the method which is [best for inference](https://x.com/_kevinlu/status/1939737362764112019), which may well be some subquadratic attention variant, and we may indeed see these methods come back into the spotlight soon ([Spending Inference Time](https://kevinlu.ai/spending-inference-time)).

### What should researchers be doing?

Now imagine that we don’t “merely” care about inference (which is “product”), and instead that we care about asymptotic performance (“AGI”).

*   Clearly, optimizing the architecture is wrong.
*   Determining how to clip your Q-function trace is definitely wrong.
*   Handcrafting new datasets doesn’t scale.
*   Your new temporal Gaussian exploration method probably doesn’t scale either.

Much of the community has converged on the principle that we should be studying new methods for consuming data, for which there are two leading paradigms: (1) next-token prediction and (2) reinforcement learning. (Apparently, we have not made great progress on new paradigms :)

All AI does is consume data
---------------------------

The landmark works provide new pathways for consuming data:

1.   [AlexNet (Alex Krizhevsky et al. 2012)](https://papers.nips.cc/paper_files/paper/2012/hash/c399862d3b9d6b76c8436e924a68c45b-Abstract.html) used next-token prediction to consume [ImageNet](https://www.image-net.org/)
2.   [GPT-2 (Alec Radford et al. 2019)](https://cdn.openai.com/better-language-models/language_models_are_unsupervised_multitask_learners.pdf) used next-token prediction to consume the internet’s text
3.   “Natively multimodal” models ([GPT-4o](https://openai.com/index/introducing-4o-image-generation/), [Gemini 1.5](https://developers.googleblog.com/en/7-examples-of-geminis-multimodal-capabilities-in-action/)) used next-token prediction to consume the internet’s images and audio
4.   [ChatGPT](https://chatgpt.com/) used reinforcement learning to consume stochastic human preference rewards in chat settings
5.   [Deepseek R1](https://arxiv.org/abs/2501.12948) used reinforcement learning to consume deterministic verifiable rewards in narrow domains

Insofar as next-token prediction is concerned, the internet is the great solution: it provides an abundant source of sequentially correlated data for a sequence-based method (next-token prediction) to learn from.

![Image 3: Sequence Modeling Diagram](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/text_perception_generation.png)

 The internet is full of sequences in structured HTML form, amenable to next-token prediction. Depending on the ordering, you can recover a variety of different useful capabilities. 

This is not merely coincidence: this sequence data is **_perfect_** for next-token prediction; the internet and next-token prediction go hand-in-hand.

### Planetary-scale data

Alec Radford gave a prescient [talk](https://sites.google.com/view/berkeley-cs294-158-sp20/home) in 2020 about how, in spite of all the new methods proposed back then, none seemed to matter compared to curating more data. In particular, we stopped hoping for “magic” generalization through better methods (our loss function should implement a parse tree), but instead a simple principle: if the model wasn’t told something, of course it doesn’t know it.

> Instead of manually specifying what to predict through the creation of large supervised datasets…
> 
> 
> Figure out how to learn from and predict everything “out there”.

> You can think of everytime we build a dataset as setting the importance of everything else in the world to 0 and the importance of everything in the dataset to 1.
> 
> 
> Our poor models! They know so little and yet still have so much hidden from them.

![Image 4](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/radford_manifold.png)

After GPT-2, the world [started taking notice](https://www.weforum.org/stories/2019/02/amazing-new-ai-churns-out-coherent-paragraphs-of-text/) of OpenAI, and time has since shown its impact.

### What if we had transformers but no internet?

**Low-data.** The obvious counterfactual is that in the low-data regime, transformers would be worthless: we consider them to have a worse “architectural prior” than convolutional or recurrent networks. Therefore, transformers should perform worse than their convolutional counterparts.

**Books.** A less extreme case is that, without the internet, we probably would do pretraining on books, or textbooks. Of all human data, generally we might consider textbooks to represent the pinnacle of human intelligence, whose authors have undergone tremendous education and poured significant thought into each word. In essence, it represents the flavor that “high quality data” should be better than “high quantity” data.

![Image 5](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/bazel_books.png)

**Textbooks.** The [phi models (“Textbooks Are All You Need”; by Suriya Gunasekar et al. 2023)](https://arxiv.org/abs/2306.11644) here show fantastic small model performance, but still require GPT-4 (pretrained on the internet) to perform filtering and generate synthetic data. Like academics, the phi models also have poor world knowledge compared to similarly sized counterparts, as measured by [SimpleQA (Jason Wei et al. 2024)](https://openai.com/index/introducing-simpleqa/).

Indeed the phi models are quite good, but we have yet to see that these models can reach the same asymptotic performance of their internet-based counterparts, and it is obvious that textbooks lack much real world and multilingual knowledge (they look _very_ strong in the compute-bound regime though).

### Classification of data

I think there is also an interesting connection to our earlier classification of RL data above. Textbooks act like **_verifiable_** rewards: their statements are (almost) _always_ true. In contrast, books – particularly in creative writing – might instead contain much more data about **_human preferences_** and imbue their resultant student models with far greater diversity.

Much in the same way we might not trust [o3](https://openai.com/index/introducing-o3-and-o4-mini/) or [Sonnet 3.7](https://www.anthropic.com/news/claude-3-7-sonnet) to write for us, we might believe that a model only trained on high-quality data lacks a certain creative flair. Tying directly to above, the phi models don’t really have great product-market fit: when you need knowledge, you prefer a big model; when you want a [local](https://www.reddit.com/r/LocalLLaMA/) roleplay writing model, people generally don’t turn to phi.

The beauty of the internet
--------------------------

Really, books and textbooks are simply compressed forms of the data available on the internet, even if there is a powerful intelligence behind them performing the compression. Going up one layer, the internet is an incredibly diverse source of supervision for our models, and a representation of humanity.

![Image 6: Internet Use Timeline](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/internet_use_timeline.png)

 From [DataReportal](https://datareportal.com/reports/digital-2024-deep-dive-the-state-of-internet-adoption). 

At first glance, many researchers might find it weird (or a distraction) that in order to make strides in research, we should turn to product. But actually I think it is quite natural: assuming that we care that AGI does something beneficial for humans, and not just act intelligent in a vacuum (as [AlphaZero](https://en.wikipedia.org/wiki/AlphaZero) does), then it makes sense to think about the form factor (product) that AGI takes on – and I think the **co-design** between research (pretraining) and product (internet) is beautiful.

![Image 7: Thinking Machines Lab, Learning By Doing](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/tml_codesign.png)

 From [Thinking Machines Lab](https://thinkingmachines.ai/). 

### Decentralization and diversity

The internet is decentralized in a way that anyone can add knowledge democratically: there is no central source of truth. There are an immense amount of rich perspectives, cultural memes, and low-resource languages represented in the internet; and if we pretrain on them with a large language model, we get a resultant intelligence which understands a vast amount of knowledge.

This therefore means that the stewards of the product (ie, of the internet) have an important role to play in the design of AGI! If we crippled the diversity of the internet, our models would have significantly worse entropy for use in RL. And if we _eliminated_ data, we would remove entire subcultures from their representation in AGI.

**Alignment.** There is a super interesting result that in order to have aligned models, you must pretrain on both aligned _and_ unaligned data [(“When Bad Data Leads to Good Models”; by Kenneth Li et al. 2025)](https://arxiv.org/abs/2505.04741), because pretraining then learns a linearly separable direction between the two. If you drop _all_ the unaligned data, this leads to the model not having a strong understanding of what unaligned data is, and why it is bad (also see [Xiangyu Qi et al. 2024](https://arxiv.org/abs/2406.05946) and [Mohit Raghavendra et al. 2024](https://arxiv.org/abs/2410.03717)).

![Image 8: Detoxification Results](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/bad_data_table.png)

**Detoxification results.** Higher numbers ("Toxigen") indicate greater toxicity. The model pretrained on **10% toxic data** (_10% Toxic data + steering (ours)_) is less toxic than pretraining on **0% toxic data** (_Clean data + steering_). 

In particular, the “toxic” data from above comes from 4chan, an anonymous online forum known for unrestricted discussion and toxic content. Although this is one specific case where there is a deep connection between the product and the research (we _need_ the unrestricted discussion to have aligned research models), I think you can think of many more cases where such internet design decisions impact outcomes after training.

![Image 9](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/dalle_comparison.png)

* for a non-alignment example, see [Improving Image Generation with Better Captions (James Betker et al. 2023)](https://cdn.openai.com/papers/dall-e-3.pdf), which was behind DALL-E 3; recaptioning to better disentangle “good” and “bad” images is now used in virtually all generative models. This has similarities to thumbs up/down in human preference rewards.

### The internet as a skill curriculum

![Image 10](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/khan_academy.jpg)

Another important property of the internet is that it contains a wide variety of knowledge of varying degrees of difficulty: it ranges from educational knowledge for elementary school students ([Khan Academy](https://www.khanacademy.org/)), to college-level courses ([MIT OpenCourseWare](https://ocw.mit.edu/)), and frontier science ([arXiv](https://arxiv.org/)). If you were to train a model on only frontier science, you could imagine that there is a lot of implicitly assumed unwritten knowledge which the models might not learn from only reading papers.

This is important because imagine you have a dataset, you train the model on it, and now it learns that dataset. What next? Well, you could manually go out and curate the next one – OpenAI started by paying knowledge workers [$2 / hour](https://time.com/6247678/openai-chatgpt-kenya-workers/) to label data; then graduating to PhD-level workers around $100 / hour; and now their frontier models are performing SWE tasks valued at [O($10,000)](https://openai.com/index/introducing-o3-and-o4-mini/).

But this is a lot of work, right? We started by manually collecting datasets like [CIFAR](https://www.cs.toronto.edu/~kriz/cifar.html), then [ImageNet](https://www.image-net.org/), then bigger ImageNet… – or [grade-school math](https://paperswithcode.com/dataset/gsm8k), then [AIME](https://artofproblemsolving.com/wiki/index.php/American_Invitational_Mathematics_Examination), then [FrontierMath](https://epoch.ai/frontiermath)… – but, by virtue of serving the whole world at planetary scale, the internet **_emergently_** contains tasks with a smooth curriculum of difficulty.

**Curriculum in RL.** As we move towards reinforcement learning, curriculum plays an even greater role: since the reward is sparse, it is imperative that the model understands the sub-skills required to solve the task once and achieve nonzero reward. Once the model discovers a nonzero reward once, it can then analyze what was successful and then try to replicate it again, and RL learns impressively from sparse rewards.

But there is no free lunch: the models still require a smooth curriculum in order to learn. Pretraining is more forgiving because its _objective_ is dense; but to make up for this, RL must use a dense _curriculum_.

![Image 11: RL Curriculum for Goal Reaching](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/yunzhi_zhang_curriculum.gif)

 From [Yunzhi Zhang et al. 2020](https://sites.google.com/berkeley.edu/vds/?pli=1&authuser=1). The RL agent first learns to achieve nearby goals close to the start of the maze, before learning to achieve goals further away. 

**Self-play** (as used in eg. [AlphaZero](https://en.wikipedia.org/wiki/AlphaZero) or [AlphaStar](https://deepmind.google/discover/blog/alphastar-mastering-the-real-time-strategy-game-starcraft-ii/)) also creates a curriculum (in the narrow domain of chess or StarCraft here). Much like RL agents or video-game players want to win (and therefore discover new strategies), online users want to contribute new ideas (sometimes receiving upvotes or ad revenue), hence expanding the frontier of knowledge and creating a natural learning curriculum.

### The [Bitter Lesson](https://www.cs.utexas.edu/~eunsol/courses/data/bitter_lesson.pdf)

It is therefore important to keep in mind that **people actually want to use the internet**, and all these useful properties emerge as a result of the interaction with the internet as a product. If we have to manually curate datasets, there is a dichotomy between what is being curated, and what people find as useful capabilities. It is not up to the researcher to select the useful skills: the internet user will tell you.

 Part of people actually wanting to use the internet is that the technology is cheap enough per-user to see widespread adoption. If the internet were gated by an expensive subscription, users would not end up contributing their data at scale. (see also: [Google Search](https://news.ycombinator.com/item?id=2110938)) 

I think people miss this a lot in the discussion of scaling, but the internet is the simple idea which scales learning and search – data and compute – and if you can find those simple ideas and scale them, you get great results.

### AGI is a record of humanity

So I think there is ample room to discuss how AGI should be built apart from mathematical theory: the internet (and by extension, AGI) can be considered from many lenses, from philosophy to the social sciences. It is well known that LLMs persist the [bias](https://arxiv.org/abs/2309.00770) of the data they were trained on. If we train a model on data from the 1900s, we will have a snapshot of the linguistic structure of the 1900s that can persist forever. We can watch human knowledge and culture evolve in real-time.

In Wikipedia articles and Github repos, we can see the collaborative nature of human intelligence. We can model cooperation and the human desire for a more perfect result. In online forums, we can see debate and diversity, where humans contribute novel ideas (and often receive some kind of selective pressure to provide some new thought). From social media, AI learns what humans find important enough to care about sharing with their loved ones. It sees human mistakes, the processes that grow to fix them, and ever-present strides towards truth.

As Claude writes,

> AI learns not from our best face but from our complete face — including arguments, confusions, and the messy process of collective sensemaking.

**Takeaways.** To be precise, the internet is very useful for model training because:

1.   It is **diverse**, hence it contains a lot of knowledge useful to the models.
2.   It forms a natural **curriculum** for the models to learn new skills.
3.   People **want to use it**, hence they continually contribute more data (product-market fit).
4.   It is **economical**: the technology is cheap enough for tons of humans to use it.

The internet is the dual of next-token prediction
-------------------------------------------------

It is somewhat obvious that reinforcement learning is the future (and “necessary” in order to achieve superhuman intelligence). But, as stated above, we lack general data sources for RL to consume. It is a deep struggle to get high-quality reward signal: we must either fight for pristine chat data, or scrounge around meager verifiable tasks. And we see chat preferences from someone else don’t necessarily correspond to what _I_ like, and a model trained on verifiable data doesn’t necessarily get better at non-verifiable tasks that I care about.

The internet was such a perfect complement to supervised next-token prediction: one might make the strong statement that given the internet as a substrate, researchers then _must_ have converged on next-token prediction. We can think of the internet as the **“primordial soup”** that led to artificial intelligence.

So I might say that the internet is the **dual** of next-token prediction.

| ML terminology (research) | Product terminology (dual) |
| --- | --- |
| next-token prediction | internet |
| sequential data | HTML file |
| train-test divergence | product-market fit |
| inference cost | economic viability |
| robust representations | redundancy (same information expressed many ways) |
| active learning | user engagement |
| multi-task learning | planetary-scale diversity |
| evolutionary fitness | upvotes |
| emergence | virality |

As mentioned above, in spite of all our research effort, we still only have two major learning paradigms. Hence it is possibly easier to come up with new “product” ideas than new major paradigms. That leads us to the question: **what is the dual of reinforcement learning?**

### RL to optimize perplexity

Firstly, I note that there is some work applying RL to the next-token prediction objective by using [perplexity](https://en.wikipedia.org/wiki/Perplexity) as a reward signal [(Yunhao Tang et al. 2025)](https://arxiv.org/abs/2503.19618). This direction aims to serve as a bridge between the benefits of RL and the diversity of the internet.

However, I think this is somewhat misguided, because the beauty of the RL paradigm is that it allows us to consume new data sources (rewards), not act as a new objective for modeling old data. For example, GANs [(Ian Goodfellow et al. 2014)](https://arxiv.org/abs/1406.2661) were once a fancy (and powerful) objective for getting more out of fixed data, but eventually got outcompeted by [diffusion](https://en.wikipedia.org/wiki/Diffusion_model), and then eventually back to next-token prediction.

What would instead be maximally exciting is finding (or **_creating_**) new data sources for RL to consume!

### What is the dual of reinforcement learning?

There are a few different ideas going around, each with some kind of drawback. None of them are “pure” research ideas, but instead involve building a product around RL. Here, I speculate a bit on what these could look like.

Recall that our desired properties are: diverse, natural curriculum, product-market fit, and economically viable.

**Traditional rewards.**

*   **Human preferences (RLHF).** As discussed above, these are hard to collect, can differ between humans, and are incredibly noisy. As can be seen with YouTube or TikTok, these tend to optimize for “engagement” rather than intelligence; it remains to be seen if there can be a clear connection made whereby increasing engagement leads to increased intelligence. 
    *   … but there will _definitely_ be a lot of RL for YouTube in the next couple years ([Andrej Karpathy](https://x.com/karpathy/status/1929634696474120576)).

*   **Verifiable rewards (RLVR).** These are limited to a narrow set of domains, and don’t always generalize outside of those domains; see o3 and Claude Sonnet 3.7.

**Applications.**

*   **Robotics.** Many people dream of building out large-scale robotics data collection pipelines and flywheels over the next decade as a way to bring intelligence into the real world, and they are incredibly exciting. As evidenced by the high rate of failure for robotics startups, this is obviously challenging. For RL, among many other reasons, it is hard to label rewards, you have to deal with varying robot morphologies, there is some sim-to-real gap, nonstationary environments, etc. As we see with self-driving cars, they are also not necessarily economical.

*   **Recommendation systems.** Sort of an extension of human preferences, but a little more targeted, we could use RL to recommend our users some product and see if they use or buy it. This incurs some penalty for being narrow as a domain, or more general (eg, “life advice”) and then facing more noisy rewards.

*   **AI research.** We can use RL to perform “AI research” [(AI Scientist; by Chris Lu et al. 2024)](https://arxiv.org/abs/2408.06292) and train the model to train other models to maximize benchmark performance. _Arguably_ this is not a narrow domain, but in practice it is. Additionally, as [Thinking Machines](https://thinkingmachines.ai/) writes: “The most important breakthroughs often come from rethinking our objectives, not just optimizing existing metrics.”

*   **Trading.** Now we have a fun metric which is _mostly_ unhackable (the model could learn market manipulation), but you will probably lose a lot of money in the process (your RL agents will probably learn not to play).

*   **Computer action data.** Insofar as RL is teaching the model a _process_, we could teach the models to execute actions on a computer (not unlike robotics), as [Adept](https://www.adept.ai/) tried to do. Especially when combined with human data (as many trading companies have on their employees), one could use some combination of next-token prediction and RL to this end. But again, this is not so easy either, and people generally won’t consent to their data being logged (unlike the internet, which requires you to engage with the content by virtue of participating, most people won’t consent to a keylogger).

    *   Coding is related here. RL to past test cases is verifiable, but generating the test cases (and large scale system design, modeling tech debt…) is not.

**Final comment:** imagine we sacrifice diversity for a bit. You can use RL at home for **your product metric**, whether that looks like [RL for video games](https://kevinlu.ai/pokemon-agents), [Claude trying to run a vending machine](https://www.anthropic.com/research/project-vend-1), or some other notion of profit or user engagement. There is many reasons that this might work – but the challenge is how to convert this into a diverse reward signal that scales into a groundbreaking paradigm shift.

* * *

Anyhow, I think we are far from discovering what the correct dual for reinforcement learning is, in a system that is as elegant and productive as the internet.

![Image 12: Our poor models! They know so little and yet still have so much hidden from them.](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/radford_hidden.png)

 What is being hidden from our RL agents today? 

But I hope you take away the dream that someday we will figure out how to create this, and it will be a big deal:

![Image 13: Reinforcement Learning Manifold](https://kevinlu.ai/assets/the_only_important_technology_is_the_internet/reinforcement_manifold.png)

 The dual of reinforcement learning. 

Twitter thread: [link](https://x.com/_kevinlu/status/1942977315031687460)

Notes mentioning this note
--------------------------

There are no notes linking to this note.
