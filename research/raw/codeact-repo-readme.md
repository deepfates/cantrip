---
title: "CodeAct GitHub Repository"
url: "https://github.com/xingyaoww/code-act"
date_fetched: "2026-02-16"
---

Title: GitHub - xingyaoww/code-act: Official Repo for ICML 2024 paper "Executable Code Actions Elicit Better LLM Agents" by Xingyao Wang, Yangyi Chen, Lifan Yuan, Yizhe Zhang, Yunzhu Li, Hao Peng, Heng Ji.

URL Source: https://github.com/xingyaoww/code-act

Markdown Content:
Executable Code Actions Elicit Better LLM Agents
------------------------------------------------

[](https://github.com/xingyaoww/code-act#-executable-code-actions-elicit-better-llm-agents-)
[📃 Paper](https://arxiv.org/abs/2402.01030) • [🤗 Data (CodeActInstruct)](https://huggingface.co/datasets/xingyaoww/code-act) • [🤗 Model (CodeActAgent-Mistral-7b-v0.1)](https://huggingface.co/xingyaoww/CodeActAgent-Mistral-7b-v0.1) • [🤖 Chat with CodeActAgent!](https://chat.xwang.dev/)

We propose to use executable **code** to consolidate LLM agents’ **act**ions into a unified action space (**CodeAct**). Integrated with a Python interpreter, CodeAct can execute code actions and dynamically revise prior actions or emit new actions upon new observations (e.g., code execution results) through multi-turn interactions (check out [this example!](https://chat.xwang.dev/r/Vqn108G)).

[![Image 1: Overview](https://github.com/xingyaoww/code-act/raw/main/figures/overview.png)](https://github.com/xingyaoww/code-act/blob/main/figures/overview.png)

News
----

[](https://github.com/xingyaoww/code-act#news)
**Apr 10, 2024**: CodeActAgent Mistral is [officially available at `ollama`](https://ollama.com/xingyaow/codeact-agent-mistral)!

**Mar 11, 2024**: We also add [llama.cpp](https://github.com/ggerganov/llama.cpp) support for inferencing CodeActAgent on laptop (tested on MacOS), check out instructions [here](https://github.com/xingyaoww/code-act#using-llamacpp-for-laptop)!

**Mar 11, 2024**: We now support serving all CodeActAgent's components (LLM serving, code executor, MongoDB, Chat-UI) via Kubernetes ⎈! Check out [this guide](https://github.com/xingyaoww/code-act/blob/main/docs/KUBERNETES_DEPLOY.md)!

**Feb 2, 2024**: CodeAct is released!

Why CodeAct?
------------

[](https://github.com/xingyaoww/code-act#why-codeact)
Our extensive analysis of 17 LLMs on API-Bank and a newly curated benchmark [M 3 ToolEval](https://github.com/xingyaoww/code-act/blob/main/docs/EVALUATION.md) shows that CodeAct outperforms widely used alternatives like Text and JSON (up to 20% higher success rate). Please check our paper for more detailed analysis!

[![Image 2: Comparison between CodeAct and Text/JSON](https://github.com/xingyaoww/code-act/raw/main/figures/codeact-comparison-table.png)](https://github.com/xingyaoww/code-act/blob/main/figures/codeact-comparison-table.png)_Comparison between CodeAct and Text / JSON as action._

[![Image 3: Comparison between CodeAct and Text/JSON](https://github.com/xingyaoww/code-act/raw/main/figures/codeact-comparison-perf.png)](https://github.com/xingyaoww/code-act/blob/main/figures/codeact-comparison-perf.png)_Quantitative results comparing CodeAct and {Text, JSON} on M 3 ToolEval._

📁 CodeActInstruct
------------------

[](https://github.com/xingyaoww/code-act#-codeactinstruct)
We collect an instruction-tuning dataset, CodeActInstruct, consists of 7k multi-turn interactions using CodeAct. Dataset is release at [huggingface dataset 🤗](https://huggingface.co/datasets/xingyaoww/code-act). Please refer to the paper and [this section](https://github.com/xingyaoww/code-act#-data-generation-optional) for details of data collection.

[![Image 4: Data Statistics](https://github.com/xingyaoww/code-act/raw/main/figures/data-stats.png)](https://github.com/xingyaoww/code-act/blob/main/figures/data-stats.png)_Dataset Statistics. Token statistics are computed using Llama-2 tokenizer._

🪄 CodeActAgent
---------------

[](https://github.com/xingyaoww/code-act#-codeactagent)
Trained on **CodeActInstruct** and general conversations, **CodeActAgent** excels at out-of-domain agent tasks compared to open-source models of the same size, while not sacrificing generic performance (e.g., knowledge, dialog). We release two variants of CodeActAgent:

*   **CodeActAgent-Mistral-7b-v0.1** (recommended, [model link](https://huggingface.co/xingyaoww/CodeActAgent-Mistral-7b-v0.1)): using Mistral-7b-v0.1 as the base model with 32k context window.
*   **CodeActAgent-Llama-7b** ([model link](https://huggingface.co/xingyaoww/CodeActAgent-Llama-2-7b)): using Llama-2-7b as the base model with 4k context window.

[![Image 5: Model Performance](https://github.com/xingyaoww/code-act/raw/main/figures/model-performance.png)](https://github.com/xingyaoww/code-act/blob/main/figures/model-performance.png)_Evaluation results for CodeActAgent. ID and OD correspondingly stand for in-domain and out-of-domain evaluation. Overall averaged performance normalizes the MT-Bench score to be consistent with other tasks and excludes in-domain tasks for fair comparison._

Please check out [📃 our paper](https://github.com/xingyaoww/code-act/blob/main/TODO) for more details about data collection, model training, evaluation, and more!

🚀 Use CodeActAgent for Your Application!
-----------------------------------------

[](https://github.com/xingyaoww/code-act#-use-codeactagent-for-your-application)

codeact-demo.mp4

_Demo of the chat interface._
A CodeActAgent system contains the following components:

*   **LLM Serving**: We use [vLLM as an example](https://github.com/xingyaoww/code-act#serve-the-model-using-vllm-into-openai-compatible-api), but any serving software that can serve the model into an OpenAI compatile API should be fine.
*   **Interaction Interface**: 
    *   [Chat-UI for chat interface + MongoDB for chat history](https://github.com/xingyaoww/code-act#via-chat-ui)
    *   OR [simple Python script](https://github.com/xingyaoww/code-act#via-simple-python-script)

*   **Code Execution Engine**: This service will start an [API](https://github.com/xingyaoww/code-act#start-your-code-execution-engine) that accepts code execution requests from Chat-UI or the Python script, then starts an individual docker container to execute code for _each_ chat session.

🌟 **If you have access to a Kubernetes cluster**: You can follow [our Kubernetes setup guide](https://github.com/xingyaoww/code-act/blob/main/docs/KUBERNETES_DEPLOY.md) that allows you to spin up all of these components using one command!

Follow the guide below to set up with Docker.

### Serve the Model into OpenAI Compatible API

[](https://github.com/xingyaoww/code-act#serve-the-model-into-openai-compatible-api)
#### Using VLLM via Docker (requires [nvidia-docker](https://github.com/NVIDIA/nvidia-docker))

[](https://github.com/xingyaoww/code-act#using-vllm-via-docker-requires-nvidia-docker)

# You should download the model first, here is an example for CodeActAgent-Mistral
cd $YOUR_DIR_TO_DOWNLOADED_MISTRAL_MODEL
git lfs install
git clone https://huggingface.co/xingyaoww/CodeActAgent-Mistral-7b-v0.1
./scripts/chat/start_vllm.sh $YOUR_DIR_TO_DOWNLOADED_MISTRAL_MODEL/CodeActAgent-Mistral-7b-v0.1
# OR
# ./scripts/chat_ui/start_vllm.sh $YOUR_DIR_TO_DOWNLOADED_LLAMA_MODEL/CodeActAgent-Llama-7b

This script (docker-required) will start hosting the model based on `CUDA_VISIBLE_DEVICES` to port `8080` and you may access the model via OPENAI_API_BASE of `http://localhost:8080/v1` (by default). You may check the [OpenAI API's official documentation](https://platform.openai.com/docs/api-reference/chat/create) for detailed instruction. You may also check vLLM's [official instruction](https://vllm.ai/) for more information.

#### Using LLama.cpp (for laptop!)

[](https://github.com/xingyaoww/code-act#using-llamacpp-for-laptop)
This is tested on MacOS (M2 Max, Ventura 13.6).

**Install LLama.cpp**

git clone https://github.com/ggerganov/llama.cpp.git
# optionally create a conda environment for installation
conda create -n llamacpp python=3.10
# Install dependencies for llama cpp
cd llama.cpp
conda activate llamacpp
pip install -r requirements.txt
# Build (refer to https://github.com/ggerganov/llama.cpp?tab=readme-ov-file#build for more details)
make

**(Optional) Convert Model into [gguf](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md) Format**

OR you can skip the following commands by downloading the pre-converted quantized version (q8_0) [here](https://huggingface.co/xingyaoww/CodeActAgent-Mistral-7b-v0.1.q8_0.gguf).

# Download the model if you haven't
git lfs install
git clone https://huggingface.co/xingyaoww/CodeActAgent-Mistral-7b-v0.1
# Assume you are in the directory of llama.cpp
python convert.py ./CodeActAgent-Mistral-7b-v0.1 --outtype f16 --outfile CodeActAgent-Mistral-7b-v0.1.f16.gguf
# (optional) Quantize for faster inference
./quantize CodeActAgent-Mistral-7b-v0.1.f16.gguf CodeActAgent-Mistral-7b-v0.1.q8_0.gguf Q8_0

**Serve into OpenAI compatible API**

See [this](https://github.com/ggerganov/llama.cpp/tree/master/examples/server#llamacpp-http-server) for a detailed description of the arguments.

./server -m CodeActAgent-Mistral-7b-v0.1.q8_0.gguf -c 8192 --port 8080

Now you can access the OpenAI compatible server on `http://localhost:8080/v1` with model name being `CodeActAgent-Mistral-7b-v0.1.q8_0.gguf`. **You need to change model name from `CodeActAgent-Mistral-7b-v0.1` to `CodeActAgent-Mistral-7b-v0.1.q8_0.gguf` for the interaction interface** in the following section (in chat-ui configuration file or in the Python script)!

#### (Optional) Test if OpenAI-compatible API is working

[](https://github.com/xingyaoww/code-act#optional-test-if-openai-compatible-api-is-working)

curl -X POST 'http://localhost:8080/v1/chat/completions' -d '{
 "model": "CodeActAgent-Mistral-7b-v0.1.q8_0.gguf",
 "messages": [
 {"role": "system", "content": "You are a helpful assistant."},
 {"role": "user", "content": "How to build a website?"}
 ]
}'

### Start your Code Execution Engine!

[](https://github.com/xingyaoww/code-act#start-your-code-execution-engine)
We implemented a containerized code execution engine based on [JupyterKernelGateway](https://github.com/jupyter-server/kernel_gateway). The idea is to start a Jupyter server inside a [docker container](https://github.com/xingyaoww/code-act/blob/main/scripts/chat_ui/code_execution/Dockerfile)_per chat session_ to support code execution request from the model (the session will timeout in a fixed period of time). It requires docker to be installed locally.

# Start a code execution server at 8081
./scripts/chat/code_execution/start_jupyter_server.sh 8081

### Interact with the system!

[](https://github.com/xingyaoww/code-act#interact-with-the-system)
#### via simple Python script

[](https://github.com/xingyaoww/code-act#via-simple-python-script)
If you don't want to spin up a fancy interface and just want to play with it from the command line, we got you covered!

# Make sure you started model server (vLLM or llama.cpp) and code execution engine before running this!
python3 scripts/chat/demo.py --model_name xingyaoww/CodeActAgent-Mistral-7b-v0.1 --openai_api_base http://$YOUR_API_HOST:$YOUR_API_PORT/v1 --jupyter_kernel_url http://$YOUR_CODE_EXEC_ENGINE_HOST:$YOUR_CODE_EXEC_ENGINE_PORT/execute

#### via Chat-UI

[](https://github.com/xingyaoww/code-act#via-chat-ui)
If you've served the model and the code execution engine, you can run your own chat interface just like [this](https://chat.xwang.dev/)!

If you want user management, you may need to start your own mongoDB instance:

./scripts/chat/start_mongodb.sh $YOUR_MONGO_DB_PASSWORD
# The database will be created at `pwd`/data/mongodb and available at localhost:27017

Then, you can configure your `chat-ui` interface.

cp chat-ui/.env.template chat-ui/.env.local
# Make sure you modify .env.local to your configuration by correctly fill-in
# 1. JUPYTER_API_URL
# 2. model endpoint (search for 'TODO_OPENAI_BASE_URL');
# You also need to change the model name to CodeActAgent-Mistral-7b-v0.1.q8_0.gguf if you are using llama.cpp to infer the model
# 3. MONGODB_URL - You may leave this empty, the chat-ui will automatically start a database (but it will be deleted once the container is stopped)

Now you can build and start your own web application (docker-required)!

./scripts/chat/run_chat_ui.sh
# It will starts the interface on localhost:5173 by default

# Run this script for debug mode
# ./scripts/chat/run_chat_ui_debug.sh

For more information (e.g., if you don't want to use docker), please check-out chat-ui's [documentation](https://github.com/huggingface/chat-ui)!

🎥 Reproduce Experiments in the Paper
-------------------------------------

[](https://github.com/xingyaoww/code-act#-reproduce-experiments-in-the-paper)

git clone https://github.com/xingyaoww/code-act
# To clone all submodules
git submodule update --init --recursive

### 📂 Data Generation (Optional)

[](https://github.com/xingyaoww/code-act#-data-generation-optional)
**Recommended:** You may download the processed **CodeActInstruct** from [huggingface dataset 🤗](https://huggingface.co/datasets/xingyaoww/code-act).

**For reproducibility:** You can optionally generate data follow instructions in [docs/DATA_GENERATION.md](https://github.com/xingyaoww/code-act/blob/main/docs/DATA_GENERATION.md) to generate interaction data.

### 📘 Model Training

[](https://github.com/xingyaoww/code-act#-model-training)
We use a fork of [Megatron-LLM](https://github.com/xingyaoww/Megatron-LLM) for training. You can follow [docs/MODEL_TRAINING.md](https://github.com/xingyaoww/code-act/blob/main/docs/MODEL_TRAINING.md) for detailed instructions.

### 📊 Evaluation

[](https://github.com/xingyaoww/code-act#-evaluation)
Please refer to [docs/EVALUATION.md](https://github.com/xingyaoww/code-act/blob/main/docs/EVALUATION.md) for detailed instruction.

📚 Citation
-----------

[](https://github.com/xingyaoww/code-act#-citation)

@inproceedings{wang2024executable,
      title={Executable Code Actions Elicit Better LLM Agents}, 
      author={Xingyao Wang and Yangyi Chen and Lifan Yuan and Yizhe Zhang and Yunzhu Li and Hao Peng and Heng Ji},
      year={2024},
      eprint={2402.01030},
      booktitle={ICML}
}
