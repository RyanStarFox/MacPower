---
name: macpower-merge
description: >-
  把 MacPower 当前功能分支合进 main 并推到远端。用户说合并、合进 main、开 Pull Request
  再合并、把这条分支收进主干时都要用。合并前先按任务清单 skill 归档「正在做」。不要用来发版。
---

# 合并进 main

合并只是把做完的分支收进 `main`。发版是另一件事：不要跑打包脚本，不要改 `MacPower/ReleaseNotes.json`，不要替换或重启 `/Applications/MacPower.app`。

## 合并前改任务清单

先读 `docs/skills/macpower-todo.md`，按它改 `docs/todo.md`。

当前分支对应的「正在做」剪到「已做完归档」下面的「下一个版本」。用一句话写清这次做了什么，让人看升级点就能知道。不要编版本号。「正在做」空了就留标题，并写「目前没有。」。其他小节不动。

「下一个版本」是还没发布的升级点。已发布版本的文案留在 `MacPower/ReleaseNotes.json`，发版时再写。

## 提交什么

功能改动、任务清单、这份 skill、`docs/CONTRIBUTING.md` 里对它的指引，都留在当前分支上，随这次 Pull Request 进 `main`。

不要提交 `__pycache__`、`dist`、`.superpowers`、`DerivedData`、`build`，也不要提交令牌或本机凭据。

## 推送和合并

1. 把当前分支推到远端。
2. 用 `gh` 开 Pull Request，标题和正文用中文，写清这次做了什么。
3. 用 `gh pr merge` 合进 `main`。不要 `--force`，不要跳过 hook。
4. 把 `main` 推到远端。推送被拒绝时先拉取再合并，然后推。不要强推。

署名用提出这次修改的人。任务清单上的名字以用户当次说的为准。

## 冲突

可以自动处理的冲突，保留双方意图。任务清单以 `main` 上更新过的其他任务为准，再补上本分支这一条归档，不要用旧清单盖掉别人刚加的任务。

解决不了就停下来。说清哪些文件冲突、为什么对不上，通知用户。不要强推，不要 `--force`，不要跳过 hook。
