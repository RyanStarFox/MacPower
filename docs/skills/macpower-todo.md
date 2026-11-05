---
name: macpower-todo
description: >-
  Update the MacPower task list in docs/todo.md. Use when the user adds a task,
  starts one, finishes one, moves one between sections, or asks to change
  todo.md. A newly added task is committed and pushed to main.
---

# MacPower todo

The shared copy is `docs/skills/macpower-todo.md` in the MacPower repository. The local copy is `~/.cursor/skills/macpower-todo/SKILL.md`. When these instructions change, update both files so they stay the same.

Edit only `docs/todo.md` in the MacPower repository, plus these two skill files and `CONTRIBUTING.md` when the task-list rules themselves change. Do not rewrite `MacPower/ReleaseNotes.json` for a task-list change. Do not commit `scripts/__pycache__` or unrelated dirty files. Never force-push `main`.

One task lives in one section. Change only the lines that move. Leave archived versions in their existing order.

## Tags

Every open task starts with one or more tags, written with no space between them: `- [bug][UI] 说明`. Use `[bug]`, `[feature]`, and `[UI]`. Add another tag in the same bracket form when the work needs one. Leave archived tasks as they are; do not backfill tags.

## Where a task goes

- A new task goes under `## 待做`.
- Claiming a task moves it to `## 正在做`, written as `- [标签] 任务说明（姓名）`. Use the name the user gives in that request. If they did not give a name, ask before editing. Do not invent one. Do this on a new branch from `origin/main`, push that branch, open a pull request, and merge the pull request into `main`. Do not commit the claim directly on `main`.
- After that work is merged to `main`, move it from `正在做` to `## 已做完归档`, under `### 下一个版本`. Do not invent a version number.
- A released version keeps its number as the heading, for example `### 2.1.2`. Renaming `下一个版本` to a version number happens when publishing, not while filing tasks.
- Work that needs an Apple Developer account stays under `## 有开发者账号之后做`. Do not start it before the account exists.
- A section that becomes empty keeps its heading and the line `目前没有。`

## Pushing

A newly added task is committed on `main` and pushed there directly, with no branch and no pull request. Commit `docs/todo.md`. If this same change also updates the task-list rules, include `docs/skills/macpower-todo.md` and `CONTRIBUTING.md`. Pull so the push can fast-forward, then `git push origin HEAD`. If the push is rejected, fetch and merge, then push. Do not force-push.

Claiming uses the branch and pull request above, not a direct push to `main`. Archiving a finished task stays local until the user asks to push.
