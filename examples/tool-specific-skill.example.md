---
name: example-crawler
description: >
  Use Example Crawler for local website crawling, clean Markdown generation,
  link extraction, JavaScript rendering, and structured extraction. Use when a
  task needs repeatable crawler code, local browser sessions, or fallback after
  simple fetch fails.
---

# Example Crawler

Use this file as a template for an A-class tool-specific skill.

## When To Use

Use this tool for:

- repeated crawling workflows;
- JavaScript-rendered pages;
- structured extraction;
- link discovery;
- local browser sessions;
- fallback after simple fetch is incomplete.

Do not use it for:

- broad open-ended research when a search router is better;
- private or authenticated content without explicit user authorization;
- one-line live data that has a direct structured helper.

## Setup Check

Run the tool's doctor or version command before first use:

```bash
example-crawler --version
example-crawler doctor --json
```

## Basic Workflow

1. Confirm the target URL and desired output.
2. Start with the lightest mode that can satisfy the task.
3. Escalate to browser rendering only if static retrieval is incomplete.
4. Save temporary outputs outside the project unless the user asked for a file.
5. Validate extracted records against the page or a sample of source Markdown.
6. Cite source URLs in the final answer.

## Failure Routing

- Network failure: retry once, then report the exact failure.
- Incomplete static content: retry with browser rendering.
- Bot protection: use the approved anti-bot-capable tool for this category.
- Auth required: ask the user for authorization or login context.

## Safety

Do not print secrets. Do not persist cookies or browser profiles unless the user
explicitly approves. Do not perform write actions on websites unless explicitly
requested.
