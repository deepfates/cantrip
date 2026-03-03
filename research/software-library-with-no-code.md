---
title: "A Software Library with No Code"
url: https://www.dbreunig.com/2026/01/08/a-software-library-with-no-code.html
date_fetched: 2026-02-16
author: Drew Breunig
---

# A Software Library with No Code

**Author:** Drew Breunig
**Date:** January 8, 2026

## Summary

Breunig released `whenwords`, a relative time formatting library distinguished by containing no actual code--instead relying on detailed specifications and language-agnostic test cases. The library supports implementation across seven programming languages plus Excel.

Rather than traditional code repositories, the project consists of three components: a behavioral specification document, a YAML file with test cases, and installation instructions simple enough to paste into AI coding assistants like Claude.

## Key Arguments for Spec-Only Libraries

The author identifies when this approach works well:

1. **Performance**: Complex systems requiring optimization and extensive real-world testing (browsers, databases) still need actual code implementations with established communities fixing discovered issues.

2. **Testing Complexity**: Maintaining consistency across multiple language implementations and AI models creates significant testing burdens--comparing to SQLite's 51,445 tests versus `whenwords`' 125.

3. **Support & Bug Fixes**: Probabilistic AI models produce inconsistent results, making debugging customer issues nearly impossible without a reference implementation.

4. **Ongoing Updates**: Libraries requiring continuous security patches and feature additions benefit from dedicated maintainers, unlike "implement-and-forget" utilities.

5. **Community**: Established communities provide bug discovery, fixes, support, and cultural investment that spec-only libraries cannot replicate.

Breunig concludes this experimental model suits simple utilities but lacks the community infrastructure essential for foundational software.
