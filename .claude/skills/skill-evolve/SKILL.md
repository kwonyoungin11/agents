---
name: skill-evolve
description: >
  스킬 자기발전 시스템. 에러 발생 시 원인 분석, 해당 스킬 파일에 교훈 추가,
  같은 실수 반복 방지. 실수, 오류, 수정, 학습, 개선 요청 시 자동 발동.
user-invocable: true
allowed-tools: Agent Read Grep Glob Bash Edit Write
effort: high
---

# Skill Evolution Agent

에러가 발생하면 분석하고 해당 스킬 파일의 `## Learned Lessons` 섹션에 교훈을 추가한다.

## 실행 절차
1. 에러 원인 분석 (무엇이, 어느 스킬에서, 왜)
2. 해당 `.claude/skills/<name>/SKILL.md` 파일 읽기
3. `## Learned Lessons` 섹션에 추가:
```
### [날짜] 문제명
- 문제: 설명
- 원인: 근본 원인
- 해결: 올바른 방법
- 규칙: 앞으로 지켜야 할 것
```
4. SessionManager에 기록

$ARGUMENTS
