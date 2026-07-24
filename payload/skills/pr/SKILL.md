---
name: pr
description: 작업이 완료되어 PR 을 생성할 때 사용한다. 현재 브랜치의 변경사항을 분석하고 PR 템플릿에 맞게 PR 을 생성한다.
argument-hint: "[대상브랜치]"
---

# PR 생성

이 스킬은 `.claude/project.json` 의 `git.baseBranch` / `git.stagingBranch` 를 자동으로 사용한다.

## 절차

### 1. 현재 상태 확인
```!
git status
git log --oneline -10
```

- 현재 브랜치 확인
- 커밋되지 않은 변경사항이 있으면 먼저 커밋 안내

### 2. 대상 브랜치 결정

`project.json` 기반 자동 매핑:
- 현재 브랜치가 `<git.branchPrefix.feature>*` (예: `feature/*`) → `git.stagingBranch` (없으면 `git.baseBranch`)
- 현재 브랜치가 `<git.branchPrefix.meta>*` (예: `meta/*`) → `git.stagingBranch` (없으면 `git.baseBranch`)
- 현재 브랜치가 `<git.branchPrefix.hotfix>*` (예: `hotfix/*`) → `git.baseBranch`
- 인자로 대상 브랜치가 지정되면 그것을 사용 ($0)

```!
jq -r '"feature/meta → \(.git.stagingBranch // .git.baseBranch)", "hotfix → \(.git.baseBranch)"' .claude/project.json
```

### 3. 변경사항 분석
- base 브랜치와의 diff 확인 (`git log --oneline origin/<base>..HEAD`, `git diff --stat origin/<base>..HEAD`)
- 모든 커밋 메시지 확인
- 영향받는 기능/페이지 파악
- 결정 로그 변경 여부 확인 (`git diff --name-only origin/<base>..HEAD -- <paths.decisions>`)

### 4. remote push
```bash
git push -u origin HEAD
```

### 5. PR 생성

PR 제목 / 본문 언어는 `project.json` 의 `language` 따름.
제목 글자수 상한은 `pr.titleMaxChars` (기본 70).

#### 한국어 (language=ko)
```
## 요약
왜 이 변경이 필요한지 한두 줄

## 변경사항
- 변경 1
- 변경 2

## 영향 범위
- 영향받는 기능/페이지
- 사이드이펙트 여부

## 테스트
- [test-writer] 선작성 spec: <경로> (있으면)
- [worker] 구현으로 초록 전환 확인
- 전 레이어 통과: <commands.test> 로그 첨부

## 결정 로그
- `<paths.decisions>/<slug>.md` (있으면)

## 문서 동기화
- [x] 사용자 가시 기능·스택·사이트맵·데이터 모델 변경 → README.md / CLAUDE.md 사실 영역 갱신함
- [ ] 해당 없음 (사유: ...)

## 스크린샷
(UI 변경 시)
```

#### English (language=en)
```
## Summary
Why this change

## Changes
- Change 1

## Impact
- Affected features

## Tests
- [test-writer] Pre-spec: <path> (if any)
- [worker] Green after impl
- All layers pass: <commands.test>

## Decision log
- `<paths.decisions>/<slug>.md` (if any)

## Docs sync
- [x] Updated README / CLAUDE.md fact area
- [ ] N/A (reason: ...)

## Screenshots
(for UI changes)
```

- `gh pr create --base <대상브랜치> --head <현재브랜치>` 사용
- HEREDOC 으로 body 전달

## 절대 금지
- PR 머지 (사용자가 직접 수행)
- 보호 브랜치 (`git.protectedBranches`) 에 직접 push
