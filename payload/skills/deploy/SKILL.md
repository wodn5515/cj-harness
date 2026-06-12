---
name: deploy
description: stagingBranch 의 변경을 prod (baseBranch) 로 반영하는 release PR 을 생성한다. base..staging diff 를 분석해 변경 요약 / 배포 전 체크리스트 / 머지 후 검증 plan / 관련 결정 로그·docs 링크까지 PR 본문에 자동 작성한다. Lead 단독 작업 — 팀·게이트 생략. stagingBranch 가 null 인 프로젝트는 해당 없음.
---

# stagingBranch → baseBranch 배포 PR 생성

이 스킬은 `.claude/project.json` 의 `git.stagingBranch` 가 설정된 프로젝트에만 의미가 있다. `stagingBranch` 가 `null` 이면 staging 단계 자체가 없으므로 별도 release PR 불필요 — 작업 PR 이 곧장 baseBranch 로 머지됨.

## 1단계: 사전 점검 (필수)

### stagingBranch 존재 확인
```!
jq -r '.git.stagingBranch // "NONE"' .claude/project.json
```
출력이 `NONE` 이면 즉시 종료 — release PR 개념 자체가 없는 프로젝트.

### 기존 release PR 확인
```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)
gh pr list --base ${BASE} --head ${STAGE} --state open
```
- 열린 PR 이 있으면 그 URL 안내 + 종료 (중복 생성 금지)
- 없으면 진행

### base ↔ staging diff 확인
```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)
git fetch origin
git log --oneline origin/${BASE}..origin/${STAGE}
git diff --stat origin/${BASE}..origin/${STAGE} | tail -3
```

- commits 0 → "배포할 변경 없음" 안내 후 종료
- commits N → 변경 영역 분석 시작

## 2단계: 변경 분석

### 포함되는 PR 목록 추출
```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)
git log --oneline origin/${BASE}..origin/${STAGE} | grep -oE '\(#[0-9]+\)' | tr -d '()#' | sort -u
```

각 PR 번호로 `gh pr view <N> --json title,body,mergedAt -q '{title, body}'` 호출해 제목·본문 가져오기. 본문에서 핵심 결정 로그 링크·destructive 표기·검증 결과 추출.

### 변경 영역 분류

`git diff --name-only origin/${BASE}..origin/${STAGE}` 결과를 카테고리별로 분류한다. 프로젝트마다 카테고리가 다르므로 `paths.implementation` / 프로젝트 CLAUDE.md 의 디렉토리 구조를 참고해 직접 매핑:

- **DB / 마이그레이션**: 마이그레이션 디렉토리 변경 → 🚨 destructive 검사 필수
- **인증·라우팅 / 권한**: 가드·인가 헬퍼 변경 → 환경 설정 영향 확인
- **사용자 측 UI**: 사용자 페이지·컴포넌트 변경
- **관리/운영 측 UI** (있는 경우): 운영자 페이지 변경
- **DB 헬퍼 / 비즈니스 로직**: 내부 로직
- **테스트**: 테스트 인프라 / spec
- **문서**: PRD / README / CLAUDE.md / AGENTS.md
- **운영 도구**: `.claude/**`
- **환경변수**: env 추가/변경/제거

### Destructive SQL 검사 (마이그레이션 있는 프로젝트)
```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)
# 마이그레이션 디렉토리 경로는 프로젝트마다 다름 — 보통 supabase/migrations, prisma/migrations, migrations 등
MIG_DIR=$(jq -r '.paths.migrations // "supabase/migrations"' .claude/project.json 2>/dev/null)
git diff origin/${BASE}..origin/${STAGE} -- "${MIG_DIR}/" 2>/dev/null \
  | grep -iE '(drop column|drop table|delete from|alter table .* drop|truncate)'
```
- 매치 있음 → "destructive 마이그레이션" 항목 PR 본문에 강조 + 사용자 보존 데이터 확인 안내
- 매치 없음 → "데이터 안전" 표시

### 환경변수 변경 검사
```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)
git diff origin/${BASE}..origin/${STAGE} -- CLAUDE.md README.md docs/ \
  | grep -iE '^[+-].*(_KEY|_EMAIL|_URL|_TOKEN|_SECRET|env|NEXT_PUBLIC_|PUBLIC_|PRIVATE_)'
```
- 매치 있음 → "환경변수 점검" 항목에 변경된 env 명시
- 매치 없음 → "추가 env 없음"

### 결정 로그 추출
```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)
DEC=$(jq -r '.paths.decisions // "docs/decisions"' .claude/project.json)
git diff --name-only origin/${BASE}..origin/${STAGE} -- "${DEC}/"
```
- 변경된 파일 목록을 PR 본문 하단 "관련 결정 로그" 섹션에 링크

## 3단계: PR 본문 작성

다음 템플릿 그대로 채워 작성. 빈 섹션 (변경 없음) 은 "변동 없음" 한 줄로 명시 (섹션 자체는 유지 — 일관 톤).

언어는 `project.json` 의 `language` 따름. 아래는 한국어 템플릿:

```markdown
## 요약

<한 줄 컨셉 — 가장 큰 변경의 1 줄 요약>

| PR | 영역 | 내용 |
|---|---|---|
| #N | <카테고리> | <title 한 줄> |
| ... | ... | ... |

<N> files / +<I> / -<D>.

---

## 🚨 배포 전 필수 체크리스트 — 순서대로 실행

### 1. DB 마이그레이션 적용 — 코드 deploy 전에 먼저

코드 deploy 가 먼저 떨어지고 마이그레이션이 안 가면 **<영향>**. 반드시 마이그레이션 우선.

<각 마이그레이션 파일별 한 줄 요약>
- `<마이그레이션 경로>` — <목적 한 줄>
  - <destructive 항목 강조 — 있으면 ⚠️ + 보존 데이터 확인 안내>

<destructive 한 항목 있으면>
> ⚠️ **destructive 적용 전 데이터 보존 확인** — 필요 시 콘솔에서 export

### 2. 인증 / 외부 콘솔 — <변경 있을 때만>

- OAuth provider 콘솔 / Redirect URLs 변경 확인
- 외부 서비스 인증 콘솔 점검

### 3. 환경 변수 — <변경 있을 때만>

prod 환경에 다음 env 갱신:
- `<ENV_NAME>` — <설명>

<변경 없으면>
> 추가 / 변경된 env 없음. 기존 설정 그대로 유지.

### 4. 머지 후 수동 검증 항목 — <PR 본문에서 추출>

PR 본문에 명시된 사용자 측 수동 검증 항목 모음:
- <항목 1> (PR #N)
- <항목 2> (PR #N)

---

## 머지 후 검증 plan (골든 패스)

영역별 핵심 시나리오:

1. **<영역 1>**: <시나리오>
2. **<영역 2>**: <시나리오>
3. <필요한 만큼>

장애 발생 시 rollback 절차 안내. 단 마이그레이션은 rollback 안 됨 — destructive 변경 있으면 사용자 데이터 영향 인지.

---

## 후속 검토 항목 (이번 배포 미포함)

<머지된 PR 들 본문에서 "후속" / "백로그" 항목 모아 정리. 없으면 "현재 백로그 없음" 한 줄>

---

## 관련 결정 로그 / docs

<paths.decisions 변경 파일 링크>
- [`<paths.decisions>/<NNN-slug>.md`](https://github.com/<owner>/<repo>/blob/<staging>/<paths.decisions>/<NNN-slug>.md) — <한 줄 제목>

<PRD / CLAUDE.md / README 변경 영역>
- <변경 요약>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## 4단계: PR 생성

```bash
BASE=$(jq -r '.git.baseBranch' .claude/project.json)
STAGE=$(jq -r '.git.stagingBranch' .claude/project.json)

gh pr create --base ${BASE} --head ${STAGE} \
  --title "[release] <한 줄 요약>" \
  --body-file - <<'EOF'
<3단계에서 작성한 본문>
EOF
```

PR URL 반환.

## 5단계: 결과 보고

```
🚀 release PR #N 생성 — <URL>

- ${BASE}..${STAGE}: <N> commits / <P> 개 PR (#x, #y, ...)
- <N> files / +<I> / -<D>
- destructive 마이그레이션: <있음/없음>
- 환경변수 변경: <있음/없음>
- 머지 후 수동 검증 항목 <M> 건

배포 진행 시 PR 본문 1번 체크리스트 (마이그레이션) 부터 순서대로.
```

## 주의 사항

- **사용자만 머지 가능** — Lead 는 PR 생성까지. 머지는 사용자가 GitHub UI 또는 `gh pr merge` 로 수행
- **base / head 는 project.json 에서 자동** — 직접 박지 마라
- **PR 본문 자동 생성이 핵심** — 변경 분석 결과를 정확히 본문에 담는 게 가치
- **destructive 마이그레이션 누락 금지** — 사용자가 모르고 머지하면 데이터 손실 가능. PR 본문 §1 에서 ⚠️ 강조 필수
- **결정 로그 링크** — diff 에 등장하면 자동으로 PR 본문 하단에 추가 (사용자가 배포 의도·근거 추적 가능)
