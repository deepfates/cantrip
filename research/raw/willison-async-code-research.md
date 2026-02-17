---
title: "Code research projects with async coding agents like Claude Code and Codex"
url: "https://simonwillison.net/2025/Nov/6/async-code-research/"
date_fetched: "2026-02-16"
type: webpage
---

Title: Code research projects with async coding agents like Claude Code and Codex

URL Source: https://simonwillison.net/2025/Nov/6/async-code-research/

Markdown Content:
6th November 2025

I’ve been experimenting with a pattern for LLM usage recently that’s working out really well: **asynchronous code research tasks**. Pick a research question, spin up an asynchronous coding agent and let it go and run some experiments and report back when it’s done.

*   [Code research](https://simonwillison.net/2025/Nov/6/async-code-research/#code-research)
*   [Coding agents](https://simonwillison.net/2025/Nov/6/async-code-research/#coding-agents)
*   [Asynchronous coding agents](https://simonwillison.net/2025/Nov/6/async-code-research/#asynchronous-coding-agents)
*   [Give them a dedicated GitHub repository](https://simonwillison.net/2025/Nov/6/async-code-research/#give-them-a-dedicated-github-repository)
*   [Let them rip with unlimited network access](https://simonwillison.net/2025/Nov/6/async-code-research/#let-them-rip-with-unlimited-network-access)
*   [My simonw/research collection](https://simonwillison.net/2025/Nov/6/async-code-research/#my-simonw-research-collection)
*   [This is total slop, of course](https://simonwillison.net/2025/Nov/6/async-code-research/#this-is-total-slop-of-course)
*   [Try it yourself](https://simonwillison.net/2025/Nov/6/async-code-research/#try-it-yourself)

#### Code research[#](https://simonwillison.net/2025/Nov/6/async-code-research/#code-research)

Software development benefits enormously from something I call **code research**. The great thing about questions about code is that they can often be definitively answered by writing and executing code.

I often see questions on forums which hint at a lack of understanding of this skill.

“Could Redis work for powering the notifications feed for my app?” is a great example. The answer is _always_ “it depends”, but a better answer is that a good programmer already has everything they need to answer that question for themselves. Build a proof-of-concept, simulate the patterns you expect to see in production, then run experiments to see if it’s going to work.

I’ve been a keen practitioner of code research for a long time. Many of my most interesting projects started out as a few dozen lines of experimental code to prove to myself that something was possible.

#### Coding agents[#](https://simonwillison.net/2025/Nov/6/async-code-research/#coding-agents)

It turns out **coding agents** like Claude Code and Codex are a fantastic fit for this kind of work as well. Give them the right goal and a useful environment and they’ll churn through a basic research project without any further supervision.

LLMs hallucinate and make mistakes. This is far less important for code research tasks because the code itself doesn’t lie: if they write code and execute it and it does the right things then they’ve demonstrated to both themselves and to you that something really does work.

They can’t prove something is impossible—just because the coding agent couldn’t find a way to do something doesn’t mean it can’t be done—but they can often demonstrate that something _is_ possible in just a few minutes of crunching.

#### Asynchronous coding agents[#](https://simonwillison.net/2025/Nov/6/async-code-research/#asynchronous-coding-agents)

I’ve used interactive coding agents like Claude Code and Codex CLI for a bunch of these, but today I’m increasingly turning to their **asynchronous coding agent** family members instead.

An asynchronous coding agent is a coding agent that operates on a fire-and-forget basis. You pose it a task, it churns away on a server somewhere and when it’s done it files a pull request against your chosen GitHub repository.

OpenAI’s [Codex Cloud](https://chatgpt.com/codex), Anthropic’s [Claude Code for web](https://claude.ai/code), Google Gemini’s [Jules](https://jules.google/), and GitHub’s [Copilot coding agent](https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent?utm_source=chatgpt.com) are four prominent examples of this pattern.

These are _fantastic_ tools for code research projects. Come up with a clear goal, turn it into a few paragraphs of prompt, set them loose and check back ten minutes later to see what they’ve come up with.

I’m firing off 2-3 code research projects a day right now. My own time commitment is minimal and they frequently come back with useful or interesting results.

#### Give them a dedicated GitHub repository[#](https://simonwillison.net/2025/Nov/6/async-code-research/#give-them-a-dedicated-github-repository)

You can run a code research task against an existing GitHub repository, but I find it’s much more liberating to have a separate, dedicated repository for your coding agents to run their projects in.

This frees you from being limited to research against just code you’ve already written, and also means you can be much less cautious about what you let the agents do.

I have two repositories that I use for this—one public, one private. I use the public one for research tasks that have no need to be private, and the private one for anything that I’m not yet ready to share with the world.

#### Let them rip with unlimited network access[#](https://simonwillison.net/2025/Nov/6/async-code-research/#let-them-rip-with-unlimited-network-access)

The biggest benefit of a dedicated repository is that you don’t need to be cautious about what the agents operating in that repository can do.

Both Codex Cloud and Claude Code for web default to running agents in a locked-down environment, with strict restrictions on how they can access the network. This makes total sense if they are running against sensitive repositories—a prompt injection attack of the [lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) variety could easily be used to steal sensitive code or environment variables.

If you’re running in a fresh, non-sensitive repository you don’t need to worry about this at all! I’ve configured my research repositories for full network access, which means my coding agents can install any dependencies they need, fetch data from the web and generally do anything I’d be able to do on my own computer.

#### My simonw/research collection[#](https://simonwillison.net/2025/Nov/6/async-code-research/#my-simonw-research-collection)

Let’s dive into some examples. My public research repository is at [simonw/research](https://github.com/simonw/research) on GitHub. It currently contains 13 folders, each of which is a separate research project. I only created it two weeks ago so I’m already averaging nearly one a day!

It also includes [a GitHub Workflow](https://github.com/simonw/research/blob/main/.github/workflows/update-readme.yml) which uses [GitHub Models](https://docs.github.com/en/github-models) to automatically update [the README](https://github.com/simonw/research/blob/main/README.md) file with a summary of every new project, using [Cog](https://cog.readthedocs.io/), [LLM](https://llm.datasette.io/), [llm-github-models](https://github.com/tonybaloney/llm-github-models) and [this snippet of Python](https://github.com/simonw/research/blob/b059108dfefeb05a48e1c27f7a127dc9fd648129/README.md#L9-L116).

Here are a some example research projects from the repo.

**[node-pyodide](https://github.com/simonw/research/tree/main/node-pyodide)** shows an example of a [Node.js script](https://github.com/simonw/research/blob/main/node-pyodide/server-simple.js) that runs the [Pyodide](https://pyodide.org/) WebAssembly distribution of Python inside it—yet another of my [ongoing attempts](https://simonwillison.net/tags/sandboxing+python/) to find a great way of running Python in a WebAssembly sandbox on a server.

**[python-markdown-comparison](https://github.com/simonw/research/tree/main/python-markdown-comparison)** ([transcript](https://gistpreview.github.io/?fb07c2a3fd2d4cfb814a46696a58a00e)) provides a detailed performance benchmark of seven different Python Markdown libraries. I fired this one off because I stumbled across [cmarkgfm](https://pypi.org/project/cmarkgfm/), a Python binding around GitHub’s Markdown implementation in C, and wanted to see how it compared to the other options. This one produced some charts! `cmarkgfm` came out on top by a significant margin:

![Image 1: Bar chart titled "Relative Performance vs cmarkgfm (Large Document)" comparing relative speed of markdown libraries, with marko at 52.1x, markdown2 at 16.9x, mistletoe at 14.1x, markdown at 12.9x, commonmark at 12.1x, mistune at 10.0x, and cmarkgfm at 1.0x baseline marked by a red dashed line; x-axis labeled "Relative Speed (lower is better)" ranging from 0 to 50+](https://static.simonwillison.net/static/2025/markdown-performance.png)

Here’s the entire prompt I used for that project:

> Create a performance benchmark and feature comparison report on PyPI cmarkgfm compared to other popular Python markdown libraries—check all of them out from github and read the source to get an idea for features, then design and run a benchmark including generating some charts, then create a report in a new python-markdown-comparison folder (do not create a _summary.md file or edit anywhere outside of that folder). Make sure the performance chart images are directly displayed in the README.md in the folder.

Note that I didn’t specify any Markdown libraries other than `cmarkgfm`—Claude Code ran a search and found the other six by itself.

**[cmarkgfm-in-pyodide](https://github.com/simonw/research/tree/main/cmarkgfm-in-pyodide)** is a lot more fun. A neat thing about having all of my research projects in the same repository is that new projects can build on previous ones. Here I decided to see how hard it would be to get `cmarkgfm`—which has a C extension—working inside Pyodide inside Node.js. Claude successfully compiled a 88.4KB `cmarkgfm_pyodide-2025.10.22-cp312-cp312-emscripten_3_1_46_wasm32.whl` file with the necessary C extension and proved it could be loaded into Pyodide in WebAssembly inside of Node.js.

I ran this one using Claude Code on my laptop after an initial attempt failed. The starting prompt was:

> Figure out how to get the cmarkgfm markdown lover _[typo in prompt, this should have been “library” but it figured it out anyway]_ for Python working in pyodide. This will be hard because it uses C so you will need to compile it to pyodide compatible webassembly somehow. Write a report on your results plus code to a new cmarkgfm-in-pyodide directory. Test it using pytest to exercise a node.js test script that calls pyodide as seen in the existing node.js and pyodide directory
> 
> 
> There is an existing branch that was an initial attempt at this research, but which failed because it did not have Internet access. You do have Internet access. Use that existing branch to accelerate your work, but do not commit any code unless you are certain that you have successfully executed tests that prove that the pyodide module you created works correctly.

This one gave up half way through, complaining that emscripten would take too long. I told it:

> Complete this project, actually run emscripten, I do not care how long it takes, update the report if it works

It churned away for a bit longer and complained that the existing Python library used CFFI which isn’t available in Pyodide. I asked it:

> Can you figure out how to rewrite cmarkgfm to not use FFI and to use a pyodide-friendly way of integrating that C code instead?

... and it did. You can [see the full transcript here](https://gistpreview.github.io/?6d778a8f9c4c2c005a189ff308c3bc47).

**[blog-tags-scikit-learn](https://github.com/simonw/research/tree/main/blog-tags-scikit-learn)**. Taking a short break from WebAssembly, I thought it would be fun to put [scikit-learn](https://scikit-learn.org/stable/) through its paces on a text classification task against my blog:

> Work in a new folder called blog-tags-scikit-learn
> 
> 
> Download `https://datasette.simonwillison.net/simonwillisonblog.db`—a SQLite database. Take a look at the blog_entry table and the associated tags—a lot of the earlier entries do not have tags associated with them, where the later entries do. Design, implement and execute models to suggests tags for those earlier entries based on textual analysis against later ones
> 
> 
> Use Python scikit learn and try several different strategies
> 
> 
> Produce JSON of the results for each one, plus scripts for running them and a detailed markdown description
> 
> 
> Also include an HTML page with a nice visualization of the results that works by loading those JSON files.

This resulted in seven `.py` files, four `.json` results files and a detailed [report](https://github.com/simonw/research/blob/main/blog-tags-scikit-learn/README.md). (It ignored the bit about an HTML page with a nice visualization for some reason.) Not bad for a few moments of idle curiosity typed into my phone!

That’s just three of the thirteen projects in the repository so far. The commit history for each one usually links to the prompt and sometimes the transcript if you want to see how they unfolded.

More recently I added a short `AGENTS.md` file to the repo with a few extra tips for my research agents. You can [read that here](https://github.com/simonw/research/blob/b059108dfefeb05a48e1c27f7a127dc9fd648129/AGENTS.md).

#### This is total slop, of course[#](https://simonwillison.net/2025/Nov/6/async-code-research/#this-is-total-slop-of-course)

My preferred definition of [AI slop](https://simonwillison.net/2024/May/8/slop/) is AI-generated content that is published without human review. I’ve not been reviewing these reports in great detail myself, and I wouldn’t usually publish them online without some serious editing and verification.

I want to share the pattern I’m using though, so I decided to keep them quarantined in this one public `simonw/research` repository.

A tiny feature request for GitHub: I’d love to be able to mark a repository as “exclude from search indexes” such that it gets labelled with `<meta name="robots" content="noindex">` tags. I still like to keep AI-generated content out of search, to avoid contributing more to the [dead internet](https://en.wikipedia.org/wiki/Dead_Internet_theory).

#### Try it yourself[#](https://simonwillison.net/2025/Nov/6/async-code-research/#try-it-yourself)

It’s pretty easy to get started trying out this coding agent research pattern. Create a free GitHub repository (public or private) and let some agents loose on it and see what happens.

You can run agents locally but I find the asynchronous agents to be more convenient—especially as I can run them (or trigger them from my phone) without any fear of them damaging my own machine or leaking any of my private data.

Claude Code for web offers [a free $250 of credits](https://support.claude.com/en/articles/12690958-claude-code-promotion) for their $20/month users for a limited time (until November 18, 2025). Gemini Jules has [a free tier](https://jules.google/docs/usage-limits/). There are plenty of other coding agents you can try out as well.

Let me know if your research agents come back with anything interesting!
