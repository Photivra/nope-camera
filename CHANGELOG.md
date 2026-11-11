# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [semantic versioning](https://semver.org).

## [Unreleased]

### Added
- Repository setup: license documents, agent instructions, contribution and security policies, and repository checks.
- `llms.txt` index for language models, and documentation and readability rules for code.
- Security checks on every pull request: banned networking, web, SDK and logging APIs; dependency, entitlement and Unsafe allowlists; privacy manifest checks.
- Localization rules: eleven launch languages, String Catalogs, right-to-left readiness, AI translations to start, and human review required for honesty, privacy and store listing text.
- Accessibility rules: WCAG 2.2 AA and Apple's guidelines, every applicable App Store Accessibility Nutrition Label, eyes-free capture, and automated accessibility audits.
- Name and wordmark rules: "nope." when used alone, and the "nope." / "Photivra Nope Camera" lockup.
- Font rule: only fonts that are free to use; the wordmark is Inter (SIL OFL) in outlines.
- Architecture rules: the interface is a replaceable layer over interface-free logic modules, with import boundaries checked in CI.
- Documentation rules: complete DocC documentation for every symbol, `NopeCore` documented as the interface contract, Markdown API export for agents, and documentation checks in CI.
- Research: C2PA signing with offline, per-photo keys, a device capability survey, and verified wording and sources for every privacy statement.
