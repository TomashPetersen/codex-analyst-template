# Third-party notices

## OpenAI and Codex

The template documents workflows for Codex and links to official OpenAI documentation. OpenAI, ChatGPT and Codex are trademarks of their respective owner. No OpenAI software or service credentials are redistributed by this repository.

## Context7 remote service configuration

The template includes project-scoped configuration pointing to the public Context7 MCP endpoint `https://mcp.context7.com/mcp`. It does not redistribute the Context7 server, client package, API key, access token or other credentials. Context7 and Upstash names and services remain the property of their respective owners.

- Configuration verified: `2026-08-30`
- Official client setup: https://github.com/upstash/context7/blob/master/docs/resources/all-clients.mdx
- Configured tools: `resolve-library-id`, `query-docs`
- Authentication: none stored; anonymous service limits and availability are controlled by the provider

After a project is trusted, the Codex client may contact Context7 for initialize and tool discovery before an actual documentation query. This can expose ordinary network/client metadata and receive provider-controlled server instructions, tool descriptions and schemas. A tool call additionally sends the technical query. All provider metadata, instructions, schemas and outputs are treated as untrusted external source data and remain subject to the provider's then-current terms, privacy practices and rate limits. The template does not make a successful Context7 response a mandatory runtime dependency.

## Named research methods

Files in `mastery/researcher/` contain original summaries and project-specific operating guidance that may mention authors, books or public methods. Those names and underlying works remain the property of their respective owners. The template does not grant rights to reproduce third-party books, standards, articles or proprietary source material.

Files in `mastery/analyst/` and formal-analysis templates contain original workflow guidance. Names of public standards and notations remain the property of their respective owners; the standards themselves are not redistributed.

## Analyst method references

The template uses only public metadata and original operational summaries. It does not redistribute normative standards, certification materials or proprietary examples and does not claim formal conformance.

| Reference | Version or retrieval state | Verified | Rights and permitted use in this template | Review due |
|---|---|---|---|---|
| IIBA The Business Analysis Standard | 2.0 | 2026-08-29 | International Institute of Business Analysis; concept-level original adaptation only | 2027-02-25 |
| IREB CPRE Foundation Level syllabus | 3.3.0 | 2026-08-29 | International Requirements Engineering Board; concept-level original adaptation only | 2027-02-25 |
| ISO/IEC/IEEE 29148 | 2018, Edition 2 | 2026-08-29 | ISO, IEC and IEEE; public metadata and concepts only | 2027-02-25 |
| ISO/IEC/IEEE 42010 | 2022, Edition 2 | 2026-08-29 | ISO, IEC and IEEE; public architecture-description metadata and concepts only | 2027-02-25 |
| ISO/IEC 25010 | 2023, Edition 2 | 2026-08-29 | ISO and IEC; public quality-model metadata and concepts only | 2027-02-25 |
| OMG BPMN | 2.0.2 | 2026-08-29 | Object Management Group and listed contributors; non-conformant semantic subset only | 2027-02-25 |
| OMG DMN | 1.5 | 2026-08-29 | Object Management Group and listed contributors; non-conformant semantic subset only | 2027-02-25 |
| C4 model | official web guidance retrieved 2026-08-29 | 2026-08-29 | Simon Brown, official site content under CC BY 4.0; view-selection concepts only | 2027-02-25 |
| arc42 quality scenarios | official web guidance retrieved 2026-08-29 | 2026-08-29 | arc42 project, CC BY-SA 4.0; quality-scenario concepts only | 2027-02-25 |

## IBM Solution Architect adaptation

`mastery/analyst/solution-architecture.md` is an original Russian operationalization of selected architectural analysis patterns from the IBM Solution Architect skill. IBM examples, watsonx-specific assumptions, budgets, schedules, preselected technologies and ready-made NFR values are not copied.

- Source repository: `IBM/ibm-watsonx-orchestrate-adk`
- Source path: `skills/solution-architect/SKILL.md`
- Exact commit: `02c6b27d4c942c9685c394cf85416c87151ebeac`
- Extracted: `2026-08-29`
- Source: https://github.com/IBM/ibm-watsonx-orchestrate-adk/blob/02c6b27d4c942c9685c394cf85416c87151ebeac/skills/solution-architect/SKILL.md
- License: MIT

The source license notice follows.

```text
(The MIT License)

Copyright (c) 2024, 2025 IBM Corporation

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## User-added material

Research evidence, RAW, assets, code, plugins, MCP integrations and product content added after initialization may have separate licenses and terms. The product owner is responsible for recording provenance and selecting a product license. The MIT License in this template covers the template materials only.
