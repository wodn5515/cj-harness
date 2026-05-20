---
name: sync
description: baseBranch (예 main/master) 에서 hotfix 가 머지된 후 stagingBranch 에 동기화가 필요할 때 사용한다. base 의 변경사항을 staging 에 반영하는 PR 을 생성한다. stagingBranch 가 null 인 프로젝트는 해당 없음.
---

# baseBranch → stagingBranch 동기화

이 스킬은 `.claude/project.json` 의 `git.stagingBranch` 가 설정된 프로젝트에만 의미가 있다. `stagingBranch` 가 `null` 이면 staging 단계 자체가 없으므로 동기화도 불필요 — 그냥 hotfix 가 곧장 baseBranch 에 반영된 것으로 종료.

## 언제 사용하는가
- hotfix 가 `git.baseBranch` 에 머지된 후
- baseBranch 에 직접 변경이 있은 후
- stagingBranch 가 baseBranch 보다 뒤처져 있을 때

## 절차

### 0. stagingBranch 존재 확인
```!
jq -r '.git.stagingBranch // "NONE"' .claude/project.json
```
출력이 `NONE` 이면 — 이 프로젝트는 staging 단계 없음. 동기화 불필요. 즉시 종료.

### 1. 상태 확인
```!
git fetch origin
```
```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)
git log --oneline origin/${BASE}..origin/${STAGE}
git log --oneline origin/${STAGE}..origin/${BASE}
```

- baseBranch 에 있고 stagingBranch 에 없는 커밋 확인
- 동기화가 필요한지 판단

### 2. 동기화 브랜치 생성
```bash
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
git checkout ${STAGE}
git pull origin ${STAGE}
git checkout -b sync/${BASE}-to-${STAGE}
```

### 3. baseBranch 변경사항 merge commit 으로 반영
```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
git merge origin/${BASE} --no-edit
```
- 충돌 발생 시 해결하고 커밋

### 4. PR 생성
- sync 브랜치 → stagingBranch 로 PR 생성
- 제목 (한국어): `[sync] ${BASE} → ${STAGE} 동기화`
- 제목 (영어): `[sync] ${BASE} → ${STAGE}`
- 본문에 동기화되는 커밋 목록 포함

## 주의
- rebase 가 아닌 merge commit 사용 (협업 안전성, 보호 브랜치는 force push 불가)
- PR 머지는 사용자가 직접 수행
- `stagingBranch` 가 공유 브랜치이므로 절대 rebase 하지 마라
