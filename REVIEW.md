
Here's an example of how you could create a daily notes file in Markdown format, including a section for adding PR reviews:

---
layout: post
title: Daily Notes - YYYY-MM-DD
categories: [daily-notes]
tags: [daily-notes]
---

## Work Summary

Today I worked on:

* Project/Ticket A
* Project/Ticket B
* Project/Ticket C

## PR Reviews

> Last updated: YYYY-MM-DD HH:MM:SS | Total PRs: XX

**PRs Ready for Merge:**
*All checks passing, no unresolved comments, no changes requested, no conflicts, not a draft*

### Project/Ticket A

* Category: Ready for Merge (no issues)
* Reason: All checks passing, no unresolved comments, no changes requested, no conflicts, not a draft

### Project/Ticket B

* Category: Needs Attention (PRs with failing checks, unresolved comments, conflicts, or other issues)
* Reason: Has failing checks

### Project/Ticket C

* Category: Other Tasks
* Reason:

## Notes & Observations

* Observation 1
* Observation 2

---

This file uses the `daily-notes` layout and includes sections for work summary, PR reviews, other tasks, and notes & observations. The PR review section is generated using a script that retrieves the relevant information from GitHub and adds it to the daily notes file.

