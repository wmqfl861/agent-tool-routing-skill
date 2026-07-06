---
name: read-and-extract-websites
description: >
  Choose tools for reading, scraping, crawling, mapping, summarizing, or
  extracting data from websites and URLs. Use when the user provides a URL,
  wants clean Markdown, page content, website crawl/map, structured extraction,
  or dynamic/protected page retrieval.
---

# Read And Extract Websites

Use this category to choose the right web reading or extraction path.

## Tool Choice

Use `firecrawl-mcp` when the task needs cloud web search, URL scraping, site
mapping, crawling, structured extraction, or a hosted API workflow. Read the
`firecrawl-mcp` tool skill before use.

Use `scrapling-official` when the site needs local browser-backed scraping,
JavaScript rendering, anti-bot handling, adaptive selectors, stealth, or spider
code. Read the `scrapling-official` tool skill before use.

Use `crawl4ai-official` when the user wants local open-source crawling,
LLM-friendly Markdown generation, structured extraction, sessions, hooks,
browser control, proxies, or reusable Python crawlers. Read the
`crawl4ai-official` tool skill before use.

Use a direct HTTP fetch only for simple public pages when no complex extraction,
dynamic rendering, login state, or anti-bot handling is needed. No
tool-specific skill is required for direct fetch.

## Escalation

If direct fetch fails or returns incomplete content, escalate to Firecrawl or a
local crawler. If cloud scraping fails because of rendering or bot defenses,
try a local browser-backed tool. If a local crawler is too heavy for a one-off
page, try Firecrawl first.

## Safety

Do not print API keys, cookies, bearer tokens, session headers, or raw private
page content. Cite URLs or source names when summarizing retrieved content.
