# cj-harness

Claude Code 용 일반 에이전트 하네스. 여러 프로젝트에 복붙해서 같은 협업 모델 (Lead + worker + lint/sfx peer 검증 + test-writer TDD 게이트 + designer + reviewer + 결정 로그 + 보호 브랜치 훅) 을 재사용한다.

원본은 [matchmaker](https://github.com/wodn5515/angie-matchmaker) 의 `.claude/` 를 추출·일반화한 것.

---

## 무엇이 들어있나

```
cj-harness/
├── install.sh                # 셸 진입점 (인터랙티브 또는 -y 비대화형)
├── INSTALL-AI.md             # AI 진입점 (Claude Code 가 fetch 해서 따라하는 가이드)
├── README.md
├── .gitignore
├── payload/                  # 대상 프로젝트로 배포되는 페이로드 (install.sh 가 명시적 매핑으로 복사)
│   ├── agents/               # 6 개 에이전트  → 대상의 .claude/agents/
│   │   ├── worker.md          # 코드 작업자
│   │   ├── lint-checker.md    # 린트/포매팅 peer
│   │   ├── side-effect-checker.md  # 사이드이펙트·보안 peer
│   │   ├── test-writer.md     # TDD 선작성 (단발 호출)
│   │   ├── designer.md        # UI 골격 (단발 호출)
│   │   └── reviewer.md        # PR 리뷰 (별도 세션)
│   ├── skills/               # 9 개 슬래시 스킬  → 대상의 .claude/skills/
│   │   ├── work/              # 새 기능 작업 시작
│   │   ├── hotfix/            # 긴급 수정
│   │   ├── meta/              # 문서·설정 변경
│   │   ├── pr/                # PR 생성
│   │   ├── sync/              # base → staging 동기화
│   │   ├── deploy/            # staging → base release PR
│   │   ├── followup/          # PR 후속 처리
│   │   ├── review/            # PR 리뷰
│   │   └── prd-interview/     # 신규 기능 기획 인터뷰
│   ├── hooks/                # → 대상의 .claude/hooks/
│   │   ├── validate-git.sh    # 보호 브랜치 / force push / 머지된 PR 차단
│   │   └── validate-aws.sh    # AWS MCP --profile read-only 강제 (옵션)
│   ├── settings.json         # 기본 settings  → 대상의 .claude/settings.json
│   ├── project.example.json  # 프로젝트 설정 예시  → 대상의 .claude/project.json (install.sh 가 인터랙티브 생성)
│   ├── AGENTS.md             # 협업 규칙 템플릿  → 대상 루트 AGENTS.md
│   └── CLAUDE.md             # 프로젝트 컨텍스트 템플릿  → 대상 루트 CLAUDE.md
└── templates/
    └── project.schema.json   # 프로젝트 설정 스키마 (참고용 메타 문서 — 대상에는 복사 안 됨)
```

> cj-harness 자체에는 `.claude/` 가 없다 (의도적). 페이로드는 `payload/` 라는 평범한 디렉토리에 있어 `ls` 로 다 보이고 의미가 명확하다. 추후 하네스 자체를 손볼 때 쓸 에이전트·스킬이 생기면 그제서야 `.claude/` 를 만든다.

---

## 핵심 아이디어 — `.claude/project.json` 단일 진실 원천

브랜치명·테스트 명령·디렉토리 구조 등 **프로젝트별로 달라지는 모든 값**은 프로젝트 루트의 `.claude/project.json` 에 정의한다. 모든 에이전트와 스킬은 이 파일을 읽어 동작하므로, 하네스 자체는 손댈 필요 없다.

예시 (`payload/project.example.json` 참고):

```json
{
  "name": "my-app",
  "language": "ko",
  "git": {
    "baseBranch": "main",
    "stagingBranch": null,
    "protectedBranches": ["main"],
    "workTreeDir": ".worktrees",
    "branchPrefix": { "feature": "feature/", "hotfix": "hotfix/", "meta": "meta/" }
  },
  "paths": {
    "decisions": "docs/decisions",
    "implementation": ["src/**", "app/**", "components/**", "lib/**"],
    "testGlobs": ["tests/**", "e2e/**"]
  },
  "commands": {
    "test": "npm test",
    "lint": "npm run lint",
    "build": "npm run build"
  },
  "gates": {
    "designer": true,
    "tdd": true,
    "peerReview": true
  }
}
```

전체 스키마: [`templates/project.schema.json`](./templates/project.schema.json).

---

## 설치

### 방법 1 — AI 진입점 (권장, Claude Code 안에서)

새 레포 또는 기존 레포 디렉토리에서 Claude Code 실행 후 한 줄:

```
cj-harness 깔아줘 — https://github.com/wodn5515/cj-harness
```

AI 가 자동으로 [`INSTALL-AI.md`](./INSTALL-AI.md) 를 fetch 해서 단계대로 진행:

- **기존 레포** (코드·`package.json` 등 존재): `commands.{test,lint,build}` 자동 추정, 모호한 것만 사용자에게 묻기 → 페이로드 복사. 자동 커밋은 안 함 (사용자 작업과 섞이지 않게).
- **빈 레포** (아무것도 없음): 시작 질문 (이름·brancha·GitHub remote·인터뷰 여부) → `git init` + 페이로드 복사 + 첫 커밋 → **PRD 인터뷰** (페이로드의 `prd-interview/SKILL.md` 정직 참조) → 인터뷰 결과로 `project.json`·`CLAUDE.md` 일괄 갱신 + 두 번째 커밋 → (선택) `gh repo create --private --push` 까지.

설치 후 Claude Code 세션 재시작하면 슬래시 스킬 (`/work`, `/pr`, `/meta`, ...) 활성.

### 방법 2 — 셸 진입점 (CI·자동화 / 사람 직접)

#### 2a. 하네스 자체 clone (최초 1 회)

```bash
git clone https://github.com/wodn5515/cj-harness ~/cj-harness
```

#### 2b. 대상 프로젝트에 설치

```bash
cd /path/to/your-project
~/cj-harness/install.sh        # 인터랙티브 (권장)
```

또는 비대화형:

```bash
HARNESS_BASE_BRANCH=main HARNESS_STAGING_BRANCH=stage \
HARNESS_TEST_CMD="pnpm test" \
~/cj-harness/install.sh -y
```

옵션:

| 옵션 | 의미 |
|---|---|
| `(none)` | 현재 디렉토리에 복사 |
| `<target>` | 특정 디렉토리에 설치 |
| `--symlink` | 심링크로 (하네스 `git pull` 만으로 자동 반영) |
| `--update` | agents/skills/hooks 만 갱신 (settings·project.json 보존) |
| `-y` / `--non-interactive` | ENV 또는 default 값으로 자동 진행 |
| `--help` | 사용법 출력 |

비대화형 모드 ENV 변수:

| ENV | 의미 | default |
|---|---|---|
| `HARNESS_NAME` | 프로젝트 이름 | 디렉토리명 |
| `HARNESS_LANG` | ko / en | ko |
| `HARNESS_BASE_BRANCH` | base 브랜치 | origin/HEAD 추정 → main |
| `HARNESS_STAGING_BRANCH` | staging 브랜치 (빈 값 → null) | (없음) |
| `HARNESS_TEST_CMD` | commands.test (`none` → null) | `npm test` |
| `HARNESS_LINT_CMD` | commands.lint | `npm run lint` |
| `HARNESS_BUILD_CMD` | commands.build | `npm run build` |
| `HARNESS_E2E_CMD` | commands.testE2e | (없음 → null) |
| `HARNESS_GATES_DESIGNER` | true / false | true |
| `HARNESS_GATES_TDD` | true / false | true |
| `HARNESS_GATES_PEER` | true / false | true |

설치 후 다음 단계:

1. `.claude/project.json` 검토 — 브랜치명·테스트 명령 맞는지
2. `CLAUDE.md` 채우기 — 프로젝트 컨텍스트 (도메인, 데이터 모델, 디자인 시스템)
3. `AGENTS.md` 검토 — 협업 규약. 보통 그대로 두면 됨
4. `.gitignore` 에 추가:
   ```
   .claude/settings.local.json
   .worktrees/
   ```
5. 팀 모드 활성:
   ```bash
   echo '{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}' > .claude/settings.local.json
   ```

---

## 사용

설치 후 Claude Code 에서 슬래시 명령:

```
/work feature-name 새 기능 X 추가
/hotfix bug-name   prod 버그 Y 수정
/meta docs-update  README 보강
/pr                # PR 생성
/followup 123      # PR #123 후속 처리
/sync              # base → staging 동기화 (stagingBranch 있을 때)
/deploy            # staging → base release PR
/review 123        # PR #123 리뷰
/prd-interview     # 신규 기능 기획
```

전체 흐름은 `AGENTS.md` §5 참고.

---

## 업데이트

```bash
cd ~/cj-harness
git pull                              # 하네스 자체 업데이트

# 각 프로젝트에서:
cd /path/to/project
~/cj-harness/install.sh --update      # agents/skills/hooks 갱신 (settings·project.json 건드리지 않음)
```

심링크로 설치한 프로젝트는 `git pull` 만으로 자동 반영.

---

## 게이트 끄기

특정 프로젝트에서 일부 단계를 건너뛰고 싶으면 `.claude/project.json` 의 `gates` 에서:

- `designer: false` — UI 없는 프로젝트 (CLI / API / 라이브러리)
- `tdd: false` — 테스트 인프라가 아직 없는 부트스트랩 단계
- `peerReview: false` — 1 인 빠른 토이. Lead 단독 모드 (worker / lint / sfx 팀 spawn 생략)

---

## 라이선스

원본 matchmaker 와 동일.
