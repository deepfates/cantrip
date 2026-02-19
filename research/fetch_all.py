#!/usr/bin/env python3
"""
Fetch all research URLs and save as clean markdown files.
Handles PDFs (PyMuPDF), web pages (Jina reader), Twitter threads, and auth-gated stubs.
"""

import os
import re
import subprocess
import tempfile
import time
from datetime import date
from urllib.parse import urlparse

import fitz  # PyMuPDF

OUTPUT_DIR = "/Users/deepfates/intent/workspaces/code-refactor/cantrip/research/raw"
DATE_FETCHED = "2026-02-16"

# ---------------------------------------------------------------------------
# URL lists
# ---------------------------------------------------------------------------

PDF_URLS = [
    "https://arxiv.org/pdf/2402.01030",
    "https://arxiv.org/pdf/2505.22954",
    "https://arxiv.org/pdf/2501.10114",
]

TWITTER_URLS = [
    "https://x.com/a1zhang/status/2014337263287804260?rw_tt_thread=True",
    "https://x.com/buckeyevn/status/2014171253045960803?rw_tt_thread=True",
    "https://x.com/lateinteraction/status/2014685012994515206?rw_tt_thread=True",
    "https://x.com/julianeagu/status/1964704824299253888?s=09&t=A3yGaeNJQYUXMoSGx7ls_Q&rw_tt_thread=True",
]

AUTH_GATED_URLS = [
    "https://readwise.io/reader/document_raw_content/287027807",
    "https://readwise.io/reader/document_raw_content/328524244",
    "https://chatgpt.com/c/69937615-e3bc-8323-a308-0e7d70c421da",
]

WEB_URLS = [
    "https://github.com/deepfates/cantrip",
    "https://www.anthropic.com/engineering/building-effective-agents",
    "https://www.generativist.com/notes/2026/Feb/10/pi-is-vim",
    "https://www.dbreunig.com/2026/01/08/a-software-library-with-no-code.html",
    "https://mariozechner.at/posts/2025-11-30-pi-coding-agent/",
    "https://ampcode.com/notes/feedback-loopable",
    "https://github.com/samuelmtimbo/unit/blob/main/src/docs/concept/README.md",
    "https://www.robkopel.me/field-notes/ax-agent-experience/",
    "https://sunilpai.dev/posts/seven-ways/",
    "https://sunilpai.dev/posts/an-event-bus-for-ai-agents/",
    "https://sunilpai.dev/posts/local-first-ai-agents/",
    "https://scale.com/blog/text-universal-interface",
    "https://raw.works/ypi-a-recursive-coding-agent/",
    "https://aifoc.us/the-browser-is-the-sandbox/",
    "https://openai.com/index/unrolling-the-codex-agent-loop/",
    "https://alexisgallagher.com/posts/2026/why-claude-code-won/",
    "https://jakobemmerling.de/posts/fuse-is-all-you-need/",
    "https://sankalp.bearblog.dev/my-claude-code-experience-after-2-weeks-of-usage/",
    "https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents",
    "https://epoch.ai/gradient-updates/state-of-rl-envs",
    "https://www.dbreunig.com/2025/06/10/let-the-model-write-the-prompt.html",
    "https://joodaloop.com/design-dislikes/",
    "https://www.lesswrong.com/posts/HnWN6v4wHQwmYQCLX/mythic-mode",
    "https://snavsoft.com/blog/02-trellis",
    "https://christophlocher.com/notes/screen-as-room",
    "https://arxiv.org/abs/2404.04289",
    "https://docs.racket-lang.org/pollen/index.html",
    "https://elliecheng.com/blog/2026/01/20/enabling-rlm-with-shared-program-state/",
    "https://alexzhang13.github.io/blog/2025/rlm/",
    "https://alignment.anthropic.com/2025/automated-auditing/",
    "https://lethain.com/agents-series/",
    "https://www.generalintelligencecompany.com/writing/agent-native-engineering",
    "https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents",
    "https://www.benedict.dev/closing-the-software-loop",
    "https://www.lesswrong.com/posts/YEioD8YLgxih3ydxP/why-simulator-ais-want-to-be-active-inference-ais",
    "https://saurabhalone.com/blog/agent",
    "https://seconds0.substack.com/p/heres-whats-next-in-agentic-coding",
    "https://cursor.com/blog/self-driving-codebases",
    "https://benanderson.work/blog/async-coding-agents/",
    "https://danielkim.sh/blog/the-war-on-slop",
    "https://teltam.github.io/posts/using-cc.html",
    "https://sankalp.bearblog.dev/my-experience-with-claude-code-20-and-how-to-get-better-at-using-coding-agents/",
    "https://simonwillison.net/2026/Feb/7/software-factory/",
    "https://machinelearning.apple.com/research/codeact",
    "https://huggingface.co/blog/smolagents",
    "https://blog.cloudflare.com/code-mode/",
    "https://www.deepfates.com/software-recursion",
    "https://www.deepfates.com/recursive-language-models",
    "https://www.deepfates.com/the-future-belongs-to-wizards",
    "https://www.deepfates.com/artificial-general-intellect",
    "https://www.deepfates.com/christmas-ai-talk",
    "https://www.deepfates.com/claude-opus-4-5",
    "https://www.deepfates.com/magic-crystals",
    "https://www.deepfates.com/what_is_ai_engineering_anyway",
    "https://www.deepfates.com/incredible-prompt",
    "https://www.deepfates.com/ecology-of-intelligences",
    "https://www.deepfates.com/your-opinion-about-ai",
    "https://www.deepfates.com/when-will-a-human-level-ai-be-built",
    "https://www.deepfates.com/dismantling-invocations",
    "https://www.deepfates.com/the-mirror-of-language",
    "https://www.deepfates.com/ai-as-planar-binding",
    "https://www.deepfates.com/robot-face-autocomplete-everywhere",
    "https://www.deepfates.com/do-you-visit-the-library",
    "https://www.deepfates.com/robot-face-learning-loops",
    "https://www.deepfates.com/robot-face-see-and-point",
    "https://www.deepfates.com/robot-face-accelerating-succession",
    "https://browser-use.com/posts/bitter-lesson-agent-frameworks",
    "https://fly.io/blog/code-and-let-live/",
    "https://fly.io/blog/design-and-implementation/",
    "https://simonwillison.net/2026/Jan/9/sprites-dev/",
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def to_kebab(text: str) -> str:
    """Convert text to kebab-case filename (no extension)."""
    text = text.lower()
    # Remove common URL cruft
    text = re.sub(r'https?://(www\.)?', '', text)
    # Replace non-alphanumeric with hyphens
    text = re.sub(r'[^a-z0-9]+', '-', text)
    # Collapse multiple hyphens and strip leading/trailing
    text = re.sub(r'-+', '-', text).strip('-')
    # Truncate to reasonable length
    if len(text) > 80:
        text = text[:80].rsplit('-', 1)[0]
    return text


def filename_from_url(url: str) -> str:
    """Derive a kebab-case filename from a URL."""
    parsed = urlparse(url)
    path = parsed.path.rstrip('/')

    # Special cases for known patterns
    if 'arxiv.org/pdf/' in url:
        paper_id = path.split('/')[-1]
        return f"arxiv-{paper_id}"
    if 'arxiv.org/abs/' in url:
        paper_id = path.split('/')[-1]
        return f"arxiv-{paper_id}"
    if 'x.com' in url or 'twitter.com' in url:
        parts = path.split('/')
        # e.g. /username/status/id
        if len(parts) >= 3:
            username = parts[1]
            status_id = parts[3] if len(parts) >= 4 else parts[-1]
            return f"x-{username}-{status_id}"
        return to_kebab(url)
    if 'readwise.io' in url:
        doc_id = path.split('/')[-1]
        return f"readwise-{doc_id}"
    if 'chatgpt.com' in url:
        chat_id = path.split('/')[-1]
        return f"chatgpt-{chat_id}"
    if 'github.com' in url:
        # e.g. /deepfates/cantrip or /samuelmtimbo/unit/blob/...
        parts = [p for p in path.split('/') if p]
        return to_kebab('-'.join(parts[:3]))  # owner/repo or owner/repo/blob
    if 'lesswrong.com' in url:
        slug = path.split('/')[-1]
        return to_kebab(slug)

    # General: use the last meaningful path segments
    domain = parsed.netloc.replace('www.', '')
    segments = [s for s in path.split('/') if s and s not in ('index.html', 'index.htm')]
    if segments:
        slug = '-'.join(segments[-2:]) if len(segments) > 1 else segments[-1]
        # Remove file extensions
        slug = re.sub(r'\.(html?|php|aspx?)$', '', slug)
        return to_kebab(f"{domain}-{slug}")
    return to_kebab(domain)


def make_frontmatter(title: str, url: str, content_type: str) -> str:
    return f"""---
title: "{title}"
url: "{url}"
date_fetched: "{DATE_FETCHED}"
type: {content_type}
---

"""


def save_file(filename: str, content: str):
    path = os.path.join(OUTPUT_DIR, f"{filename}.md")
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    return path


def create_stub(url: str, filename: str, content_type: str, reason: str) -> str:
    title = filename.replace('-', ' ').title()
    body = make_frontmatter(title, url, content_type)
    body += f"# {title}\n\n"
    body += f"**Status:** Could not fetch content.\n\n"
    body += f"**Reason:** {reason}\n\n"
    body += f"**Original URL:** {url}\n"
    return save_file(filename, body)


# ---------------------------------------------------------------------------
# Fetchers
# ---------------------------------------------------------------------------

def fetch_pdf(url: str) -> tuple[bool, str]:
    """Download PDF and extract text with PyMuPDF."""
    filename = filename_from_url(url)
    print(f"  [PDF] Downloading {url} ...")

    try:
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as tmp:
            tmp_path = tmp.name

        result = subprocess.run(
            ['curl', '-sL', '-o', tmp_path, '--max-time', '60', url],
            capture_output=True, text=True, timeout=90
        )
        if result.returncode != 0:
            path = create_stub(url, filename, 'pdf', f"curl failed: {result.stderr[:200]}")
            return False, path

        doc = fitz.open(tmp_path)
        pages_text = []
        title = ""
        for i, page in enumerate(doc):
            text = page.get_text()
            if i == 0 and not title:
                # Try to extract title from first non-empty lines
                lines = [l.strip() for l in text.split('\n') if l.strip()]
                if lines:
                    title = lines[0][:120]
            pages_text.append(text)
        doc.close()
        os.unlink(tmp_path)

        if not title:
            title = filename.replace('-', ' ').title()

        full_text = '\n\n---\n\n'.join(pages_text)
        content = make_frontmatter(title, url, 'pdf')
        content += f"# {title}\n\n"
        content += full_text
        path = save_file(filename, content)
        print(f"  [PDF] Saved {path} ({len(pages_text)} pages)")
        return True, path

    except Exception as e:
        try:
            os.unlink(tmp_path)
        except:
            pass
        path = create_stub(url, filename, 'pdf', str(e))
        print(f"  [PDF] FAILED: {e}")
        return False, path


def fetch_via_jina(url: str, content_type: str = 'webpage') -> tuple[bool, str]:
    """Fetch content via Jina reader API."""
    filename = filename_from_url(url)
    jina_url = f"https://r.jina.ai/{url}"
    print(f"  [WEB] Fetching {url} ...")

    try:
        result = subprocess.run(
            [
                'curl', '-sL',
                '--max-time', '45',
                '-H', 'Accept: text/markdown',
                jina_url
            ],
            capture_output=True, text=True, timeout=60
        )

        if result.returncode != 0:
            path = create_stub(url, filename, content_type, f"curl failed (exit {result.returncode}): {result.stderr[:200]}")
            print(f"  [WEB] FAILED: curl error for {url}")
            return False, path

        body = result.stdout
        if not body or len(body.strip()) < 50:
            path = create_stub(url, filename, content_type, "Empty or too-short response from Jina reader.")
            print(f"  [WEB] FAILED: empty response for {url}")
            return False, path

        # Parse Jina response format:
        # Title: ...
        # URL Source: ...
        # Markdown Content:
        # ...actual content...
        title = filename.replace('-', ' ').title()
        markdown_body = body

        lines = body.split('\n')
        content_start = 0
        for i, line in enumerate(lines):
            if line.startswith('Title:'):
                title = line[len('Title:'):].strip()
            elif line.startswith('URL Source:'):
                pass
            elif line.startswith('Markdown Content:'):
                content_start = i + 1
                break
            elif line.strip() == '' and i < 5:
                continue
            else:
                # No Jina headers found, use raw body
                content_start = 0
                break

        if content_start > 0:
            markdown_body = '\n'.join(lines[content_start:])
        # If no Jina header was found, use the full body as-is

        # Clean the title for YAML
        title = title.replace('"', '\\"').strip()
        if not title:
            title = filename.replace('-', ' ').title()

        content = make_frontmatter(title, url, content_type)
        content += markdown_body
        path = save_file(filename, content)
        print(f"  [WEB] Saved {path} ({len(markdown_body)} chars)")
        return True, path

    except Exception as e:
        path = create_stub(url, filename, content_type, str(e))
        print(f"  [WEB] FAILED: {e}")
        return False, path


def create_auth_stub(url: str) -> tuple[bool, str]:
    """Create a stub for auth-gated URLs."""
    filename = filename_from_url(url)
    path = create_stub(url, filename, 'auth-gated', "This URL requires authentication and cannot be fetched automatically.")
    print(f"  [AUTH] Created stub {path}")
    return True, path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    successes = []
    failures = []

    total = len(PDF_URLS) + len(WEB_URLS) + len(TWITTER_URLS) + len(AUTH_GATED_URLS)
    processed = 0

    # --- PDFs ---
    print(f"\n{'='*60}")
    print(f"Processing {len(PDF_URLS)} PDFs")
    print(f"{'='*60}")
    for url in PDF_URLS:
        processed += 1
        print(f"\n[{processed}/{total}]")
        ok, path = fetch_pdf(url)
        (successes if ok else failures).append((url, path))
        time.sleep(1)

    # --- Web pages ---
    print(f"\n{'='*60}")
    print(f"Processing {len(WEB_URLS)} web pages")
    print(f"{'='*60}")
    for url in WEB_URLS:
        processed += 1
        print(f"\n[{processed}/{total}]")
        ok, path = fetch_via_jina(url, 'webpage')
        (successes if ok else failures).append((url, path))
        time.sleep(2)

    # --- Twitter ---
    print(f"\n{'='*60}")
    print(f"Processing {len(TWITTER_URLS)} Twitter threads")
    print(f"{'='*60}")
    for url in TWITTER_URLS:
        processed += 1
        print(f"\n[{processed}/{total}]")
        ok, path = fetch_via_jina(url, 'twitter')
        (successes if ok else failures).append((url, path))
        time.sleep(2)

    # --- Auth-gated ---
    print(f"\n{'='*60}")
    print(f"Processing {len(AUTH_GATED_URLS)} auth-gated URLs (stubs)")
    print(f"{'='*60}")
    for url in AUTH_GATED_URLS:
        processed += 1
        print(f"\n[{processed}/{total}]")
        ok, path = create_auth_stub(url)
        (successes if ok else failures).append((url, path))

    # --- Summary ---
    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    print(f"Total URLs: {total}")
    print(f"Successes:  {len(successes)}")
    print(f"Failures:   {len(failures)}")

    if failures:
        print(f"\nFailed URLs:")
        for url, path in failures:
            print(f"  - {url}")
            print(f"    -> stub at {path}")

    # List all files created
    files = sorted(os.listdir(OUTPUT_DIR))
    print(f"\nFiles created: {len(files)}")
    for f in files:
        fpath = os.path.join(OUTPUT_DIR, f)
        size = os.path.getsize(fpath)
        print(f"  {f} ({size:,} bytes)")


if __name__ == '__main__':
    main()
