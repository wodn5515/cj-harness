# INSTALL-AI.md — AI 에이전트용 cj-harness 설치 가이드

> AI 에이전트가 이 문서를 `WebFetch` 로 받아 그 자리에서 따라하면 cj-harness 페이로드가 대상 레포에 설치된다.
> 사람용 진입점은 [`install.sh`](./install.sh) 참고. 이 문서는 **Claude Code 안에서 자연어로** 트리거하는 흐름이다.
>
> 트리거 예: `cj-harness 깔아줘 — https://github.com/wodn5515/cj-harness`

---

## 사전 조건

- 현재 작업 디렉토리 = 설치 대상 (대상 레포 루트)
- `git`, `curl` 사용 가능
- (선택) GitHub remote 생성하려면 `gh` CLI + `gh auth status` OK

## 도구 가정

이 가이드는 **AI 의 일반 도구만**으로 완결한다 — 슬래시 스킬에 의존하지 않는다 (페이로드가 깔리기 전이라 미활성):
- `WebFetch` — 이 가이드 자체 fetch
- `Bash` — git, mkdir, cp, chmod, mktemp, jq 등
- `Read` — 페이로드 파일 (특히 `prd-interview/SKILL.md`) 참조
- `Edit` / `Write` — `project.json`, `CLAUDE.md`, `docs/PRD.md` 등 생성·수정
- `AskUserQuestion` — 사용자에게 묻기 (한 번에 묶어서)

---

## 단계 0 — 환경 점검 (분기)

```bash
# 빈 레포 / 기존 레포 판정 신호 수집
test -d .git && echo "✓ git initialized" || echo "✗ no git"
ls -1 package.json pyproject.toml Cargo.toml go.mod composer.json Gemfile 2>/dev/null || echo "✗ no stack manifest"
ls -1 src app components lib 2>/dev/null || echo "✗ no code dir"
ls -A | head -10
```

분기 판정:
- **기존 레포** = git init 됨 **그리고** 스택 매니페스트 (`package.json` 등) 또는 코드 디렉토리 (`src/`, `app/` 등) 존재
- **빈 레포** = 그 외 모두 (git init 안 됨, 또는 git init 됐어도 코드 없음)

애매하면 사용자에게 한 번 묻기 — "기존 코드가 있는 레포인지 새로 시작하는 레포인지".

---

## 단계 1 — 페이로드 fetch (공통)

```bash
TMP=$(mktemp -d)
git clone --depth 1 https://github.com/wodn5515/cj-harness "$TMP/cj-harness"
echo "✓ 페이로드 위치: $TMP/cj-harness/payload"
```

이 임시 디렉토리는 **마지막 단계에서 `rm -rf`** 한다 (중간에 실패해도 결국 임시라 무방).

---

## 단계 2A — 기존 레포 흐름

### 2A-1. 자동 추정

```bash
cd <대상 레포>

# 스택 추정
[ -f package.json ] && jq -r '.scripts | {test: .test, lint: .lint, build: .build}' package.json
[ -f pyproject.toml ] && grep -E '^\[tool\.(pytest|ruff|black|poetry)' pyproject.toml
[ -f Cargo.toml ] && echo "rust"
[ -f go.mod ] && echo "go"

# 디렉토리 추정
ls -d src/ app/ components/ lib/ tests/ e2e/ docs/ 2>/dev/null

# 현재 default 브랜치
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@refs/remotes/origin/@@'
```

추정 결과를 메모 (이후 `project.json` 자동 채움).

### 2A-2. 사용자에게 묻기 (모호한 것만, 한 번에)

`AskUserQuestion` 한 번에 묶어:
- `name` (default: 디렉토리명)
- `language` (`ko` / `en`, default `ko`)
- `baseBranch` (default: 위에서 감지한 origin/HEAD)
- `stagingBranch` 쓸지 (default: null)
- `gates.designer` (UI 있는 프로젝트? default: 코드 디렉토리에 `components/` 또는 `app/` 있으면 true)
- `gates.tdd` (테스트 인프라 결정됨? default: `tests/` 또는 `e2e/` 디렉토리 또는 `package.json` 의 `test` 스크립트 있으면 true)
- `gates.peerReview` (default: true)

### 2A-3. 페이로드 복사

```bash
mkdir -p .claude/agents .claude/skills .claude/hooks

cp "$TMP/cj-harness/payload/agents"/*.md         .claude/agents/
cp -R "$TMP/cj-harness/payload/skills"/*         .claude/skills/
cp "$TMP/cj-harness/payload/hooks"/*.sh          .claude/hooks/
chmod +x .claude/hooks/*.sh

# settings.json — 없을 때만
[ -f .claude/settings.json ] || cp "$TMP/cj-harness/payload/settings.json" .claude/settings.json

# AGENTS.md / CLAUDE.md — 없을 때만 (기존 거 덮어쓰지 않는다)
[ -f AGENTS.md ] || cp "$TMP/cj-harness/payload/AGENTS.md" AGENTS.md
[ -f CLAUDE.md ] || cp "$TMP/cj-harness/payload/CLAUDE.md" CLAUDE.md
```

### 2A-4. `project.json` 생성 (자동 추정 + 사용자 답 반영)

`payload/project.example.json` 을 참고해 작성. **이미 `.claude/project.json` 이 있으면 건드리지 않는다.**

```bash
[ -f .claude/project.json ] && echo "이미 존재 — 건너뜀" || cat > .claude/project.json <<EOF
{
  "name": "<답>",
  "language": "<ko|en>",
  "git": {
    "baseBranch": "<답>",
    "stagingBranch": <null 또는 "<답>">,
    "protectedBranches": [<baseBranch + stagingBranch>],
    "workTreeDir": ".worktrees",
    "branchPrefix": {"feature": "feature/", "hotfix": "hotfix/", "meta": "meta/"},
    "symlinkFromMain": [".claude/settings.local.json"]
  },
  "paths": {
    "docs": "docs",
    "decisions": "docs/decisions",
    "prd": null,
    "implementation": [<감지된 디렉토리 glob>],
    "tests": {"unit": <감지 또는 null>, "integration": <...>, "e2e": <...>},
    "testGlobs": ["tests/**", "e2e/**", "vitest.config.*", "playwright.config.*"]
  },
  "commands": {
    "test": <package.json scripts.test 또는 null>,
    "testE2e": <감지 또는 null>,
    "lint": <package.json scripts.lint 또는 null>,
    "typecheck": <감지 또는 null>,
    "build": <package.json scripts.build 또는 null>
  },
  "gates": {"designer": <답>, "tdd": <답>, "peerReview": <답>},
  "pr": {"titleMaxChars": 70, "mergeStrategy": "squash"},
  "hooks": {"aws": {"requireReadOnlyProfile": false}}
}
EOF
```

### 2A-5. `.gitignore` + 팀 모드 활성

```bash
# .gitignore 보강 (이미 있는 항목은 건드리지 않음)
grep -qxF '.claude/settings.local.json' .gitignore 2>/dev/null || echo '.claude/settings.local.json' >> .gitignore
grep -qxF '.worktrees/' .gitignore 2>/dev/null || echo '.worktrees/' >> .gitignore

# 팀 모드 (gitignored)
echo '{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}' > .claude/settings.local.json
```

### 2A-6. JSON 검증

```bash
jq empty .claude/project.json && jq empty .claude/settings.json && jq empty .claude/settings.local.json
```

### 2A-7. 단계 4 (정리) 로 진입

기존 레포는 사용자가 직접 변경분을 검토 후 커밋. AI 가 자동 커밋하지 않는다 (사용자 진행 중 작업과 섞일 수 있어서).

---

## 단계 2B — 빈 레포 흐름

### 2B-1. 시작 질문 (한 번에 묶음)

`AskUserQuestion` 한 번에:
- 프로젝트 이름 (default: 디렉토리명)
- `baseBranch` (default: main)
- GitHub remote: `private` / `public` / `안 만들기` (default: private)
- PRD 인터뷰 진행: `yes` / `no` (default: yes)

### 2B-2. git init + 페이로드 복사 (보수적 default)

```bash
# git init (이미 됐으면 skip)
[ -d .git ] || git init -b <baseBranch>

mkdir -p .claude/agents .claude/skills .claude/hooks docs/decisions

cp "$TMP/cj-harness/payload/agents"/*.md         .claude/agents/
cp -R "$TMP/cj-harness/payload/skills"/*         .claude/skills/
cp "$TMP/cj-harness/payload/hooks"/*.sh          .claude/hooks/
chmod +x .claude/hooks/*.sh
cp "$TMP/cj-harness/payload/settings.json"       .claude/settings.json
cp "$TMP/cj-harness/payload/AGENTS.md"           AGENTS.md
cp "$TMP/cj-harness/payload/CLAUDE.md"           CLAUDE.md

# .gitignore + 팀 모드
cat > .gitignore <<'EOF'
.claude/settings.local.json
.worktrees/
.DS_Store
node_modules/
EOF
echo '{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}' > .claude/settings.local.json
```

`project.json` 은 **보수적 default** 로 작성 (commands 전부 null, gates.tdd: false):

```json
{
  "name": "<답>",
  "language": "ko",
  "git": {
    "baseBranch": "<답>",
    "stagingBranch": null,
    "protectedBranches": ["<baseBranch>"],
    "workTreeDir": ".worktrees",
    "branchPrefix": {"feature": "feature/", "hotfix": "hotfix/", "meta": "meta/"},
    "symlinkFromMain": [".claude/settings.local.json"]
  },
  "paths": {
    "docs": "docs",
    "decisions": "docs/decisions",
    "prd": null,
    "implementation": ["src/**", "app/**", "components/**", "lib/**"],
    "tests": {"unit": null, "integration": null, "e2e": null},
    "testGlobs": ["tests/**", "e2e/**"]
  },
  "commands": {
    "test": null, "testUnit": null, "testIntegration": null, "testE2e": null,
    "lint": null, "typecheck": null, "build": null
  },
  "gates": {"designer": true, "tdd": false, "peerReview": true},
  "pr": {"titleMaxChars": 70, "mergeStrategy": "squash"},
  "hooks": {"aws": {"requireReadOnlyProfile": false}}
}
```

### 2B-3. 첫 커밋

```bash
git add -A
git commit -m "[init] cj-harness 페이로드 설치 (PRD 작성 대기)"
```

### 2B-4. PRD 인터뷰 (인터뷰 yes 했으면)

**AI 가 방금 깐 `.claude/skills/prd-interview/SKILL.md` 를 `Read` 로 직접 읽고 그 흐름 그대로 따라한다.** 흉내가 아니라 정직 참조.

핵심 원칙 (SKILL.md 에서 따옴):
- **사용자가 "ready to build" / "OK 인터뷰 끝" 같은 명시적 종료 신호를 줄 때까지 끝내지 않는다**
- 깊이 우선 — 한 가지 주제씩 드릴 다운
- 한 턴에 한 질문 (옵션 라벨링 포함 가능)
- 추측 말고 사용자에게 묻기 (모호하면)
- 4~6 branch 마다 결정 정리 (`## 🌳 정리`)

Greenfield 커버 순서 (SKILL.md 참조):
1. 컨셉 / value prop
2. 사용자 / 액터
3. 핵심 엔티티 / 데이터 모델
4. 핵심 액션 / 워크플로우
5. 결정 로직 (recommendation·scoring·matching·...)
6. 인증 / 권한
7. UI / UX 톤
8. **기술 스택** ← 여기서 commands·gates 결정 근거가 모임
9. 비용 / 배포
10. 비-목표 / 엣지 케이스

### 2B-5. 인터뷰 종료 → 일괄 반영 (두 번째 커밋)

**파일 갱신:**

1. **`.claude/project.json`**:
   - `commands.{test,lint,build}` — Branch 8 스택 기반 (예: Next.js → `"npm test"` / `"npm run lint"` / `"npm run build"`; Vite → `"vitest"` 등)
   - `commands.testE2e` — Playwright 결정 시 `"npm run test:e2e"` 등
   - `gates.tdd: true` — Branch 8 에서 테스트 인프라 결정됨
   - `gates.designer` — Branch 7 UI 비중에 따라
   - `paths.implementation` — 스택 관례 (Next.js App Router → `["app/**", "components/**", "lib/**"]`)
   - `paths.tests.{unit,integration,e2e}` — 도구 결정 따라
   - `paths.prd: "docs/PRD.md"` ← PRD 작성하므로

2. **`CLAUDE.md` 자동 채움 (사실 영역 + 정책 영역 일부)**:
   - §1 한 줄 요약 ← Branch 1
   - §2 핵심 가치 + Non-goal ← Branch 1, 10
   - §3 기술 스택 ← Branch 8
   - §4 디렉토리 구조 ← 스택 관례
   - §5 디자인 시스템 ← Branch 7 (UI 있는 경우만)
   - §6 데이터 모델 ← Branch 3
   - §7 라우팅 / 사이트맵 ← Branch 4 (API/CLI 면 그 형식)
   - §11 환경 변수 ← Branch 8, 9

3. **`docs/PRD.md` 생성** — prd-interview SKILL.md 의 greenfield 템플릿 그대로:
   ```
   1. Product Overview
   2. User Roles
   3. Feature List
   4. Data Model
   5. Sitemap & Routing
   6. UX Detail
   7. Tech Stack (with rationale)
   8. Environment Variables
   9. Out of Scope (V1)
   10. Success Criteria
   11. Definition of Done (V1)
   ```

4. **`docs/decisions/000-initial-decisions.md` 생성** — 비자명한 결정 + 거절된 대안 + 근거. 한 결정당:
   ```
   ## N. <주제>
   - **결정:** <뭐로 정했는지>
   - **근거:** <왜>
   - **거절된 대안:** <대안 + 안 한 이유>
   ```

**두 번째 커밋:**
```bash
git add -A
git commit -m "[init] PRD + 초기 컨텍스트 (스택: <결정된 스택>)"
```

### 2B-6. GitHub remote (yes 했으면)

```bash
# gh 인증 점검
gh auth status 2>&1 | grep -q "Logged in" || { echo "⚠️ gh CLI 인증 필요 — 사용자에게 'gh auth login' 안내"; exit 1; }

# 생성 + push
VISIBILITY="--private"   # 또는 --public
gh repo create "<name>" $VISIBILITY --source=. --remote=origin --push
```

**중요:** 첫 push 는 `main` 직접 — 이번 세션엔 `.claude/settings.json` 의 보호 브랜치 훅이 아직 활성 안 됐으므로 (Claude Code 가 시작 시점 settings 로드) 통과. 재시작 후부터 `main` 직접 push 차단됨.

### 2B-7. 단계 4 (정리) 로 진입

---

## 단계 3 — JSON / 셸 syntax 검증

```bash
# project.json + settings 둘 다 유효한 JSON 인지
jq empty .claude/project.json
jq empty .claude/settings.json
jq empty .claude/settings.local.json

# hooks shell syntax
for f in .claude/hooks/*.sh; do bash -n "$f" || echo "syntax 오류: $f"; done
```

## 단계 4 — 정리 + 마무리 보고

```bash
rm -rf "$TMP"
```

사용자에게 다음 보고:

```
✅ cj-harness 설치 완료

[빈 레포 케이스]
- 두 커밋: [init] 페이로드 + [init] PRD + 초기 컨텍스트
- (yes 했으면) GitHub remote 생성 + push 완료: <URL>
- 결정된 스택: <X> / 테스트 인프라: <Y> / UI 비중: <Z>

[기존 레포 케이스]
- 변경분 확인 후 직접 커밋해 주세요: git status / git diff --cached
- 자동 추정한 commands·gates 검토: cat .claude/project.json

[공통 다음 단계]
1. Claude Code 세션 재시작 → 슬래시 스킬 (/work, /pr, /meta, ...) 활성
2. 첫 기능 작업: /work <브랜치명>
3. (선택) AGENTS.md 검토 — 협업 규약. 보통 그대로 OK
4. (빈 레포 + 인터뷰 안 한 경우) /prd-interview 직접 호출해 PRD 작성
```

---

## 절대 금지

- 이미 존재하는 `AGENTS.md` / `CLAUDE.md` / `.claude/settings.json` / `.claude/project.json` 덮어쓰기 — 사용자 동의 없이 절대 안 됨
- 페이로드 임시 디렉토리 외 영구 위치에 cj-harness clone (`~/.cj-harness` 같은 자동 생성 금지 — 이건 `install.sh --update` 흐름 영역)
- 사용자 명시 동의 없이 GitHub remote 생성 (단계 2B-1 에서 yes 받은 경우만)
- `gh pr merge` / `git push --force` / `git reset --hard` — 보호 브랜치 훅이 차단하는 명령 그대로 회피 금지
- 인터뷰 단계 (2B-4) 를 사용자가 종료 신호 주기 전 임의 종료 — SKILL.md 규약 그대로

## 트러블슈팅

| 상황 | 대응 |
|---|---|
| `git clone` 실패 (네트워크) | 재시도, 또는 사용자에게 ZIP 다운로드 안내 |
| `gh` 미설치 | GitHub remote 생성 단계 건너뛰고 안내만 ("brew install gh" 등) |
| `gh auth` 미인증 | "gh auth login" 사용자에게 안내, remote 생성 건너뜀 |
| `jq` 미설치 | `python3 -c "import json,sys;json.load(open(sys.argv[1]))" <file>` 로 대체 검증 |
| 기존 `.claude/project.json` 존재 | 건드리지 않고 보고에 "기존 파일 보존" 명시 |
| 인터뷰 도중 사용자 중단 | 현재까지 결정 사항을 `docs/decisions/000-...md` 로 부분 저장 + "인터뷰 재개 시 `/prd-interview`" 안내 |
