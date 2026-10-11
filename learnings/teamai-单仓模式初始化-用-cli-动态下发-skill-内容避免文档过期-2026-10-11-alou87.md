---
title: "teamai 单仓模式初始化：用 CLI 动态下发 skill 内容避免文档过期"
author: wyq09
date: 2026-10-10
tags: [workflow, tool-usage, best-practice, config]
confidence: 0.85
source_mr: "https://github.com/wyq09/kunpeng-voice/pull/1"
---

## 背景

团队需要把 AI 编码工具的 skills、rules、docs 和环境配置在成员之间统一同步，避免出现"各人本地 AI 配置漂移、团队知识沉淀不下来"的问题。本 MR 在 clone-voice 仓库完成了 teamai 单仓模式初始化，并推送了第一个团队资源：`teamai` skill 的发现 stub（`.teamai/skills/teamai/SKILL.md`）。

一个关键的设计痛点是：skill 的使用说明如果直接写在仓库里，CLI 升级后仓库里的文档就会过期，团队成员照着旧文档操作新 CLI 必然踩坑。

## 解决方案

采用"发现 stub + CLI 动态下发"的两层结构：

1. **仓库只放不可变的发现 stub**：`SKILL.md` 不包含具体用法，只描述 skill 的触发场景（team 仓库搭建、成员加入、pull/push 同步、session learnings 分享、codebase 知识库构建等），并指向 CLI。
2. **用法由 CLI 按版本动态提供**：通过 `teamai skill get core / setup / wiki / share` 拉取与当前安装版本完全匹配的工作流文档，保证"说明永远不过期"。
3. **按需加载控制上下文成本**：`--full` 才展开完整命令参考和故障排查；`teamai skill list` 列出当前版本支持的全部 skill；`teamai skill path <name>` 定位脚本与模板目录。
4. **行为约定写入 stub**：如 turn 结束时的 friction reminder 触发 `teamai skill get share`；发布已有的 skill/rule/doc 走 `core`，不依赖 recall。

## 经验总结

- 分发工具类 skill 时，把"稳定的触发描述"和"易变的操作手册"分离：前者入库做发现入口，后者由 CLI 按版本下发，根治文档与实现不同步的问题。
- skill 的 `description` 要写全触发短语（如 "set up teamai"、"share what I learned"、"team wiki"），直接决定 AI 能否在正确场景自动命中该 skill。
- 团队知识沉淀要嵌入工作流闭环：friction reminder → share skill → learning 入库，让"踩坑经验"在会话结束时自动转化为团队资产，而不是依赖成员自觉。
- 多仓大项目的架构逆向与知识库构建（wiki skill）应与日常配置同步（core skill）拆分为独立入口，避免单一 skill 臃肿。

## 相关 Skills

- teamai