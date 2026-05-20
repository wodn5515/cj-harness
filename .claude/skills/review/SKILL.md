---
name: review
description: PR 코드 리뷰가 필요할 때 사용한다. PR 의 변경사항을 분석하고 리뷰 코멘트 템플릿에 맞게 GitHub 에 코멘트를 남긴다. reviewer 에이전트로 위임할 수도 있다.
argument-hint: "<PR번호>"
---

# PR 리뷰

## 절차

### 1. PR 정보 확인
```bash
gh pr view $0
gh pr diff $0
```

### 2. 변경 파일 분석
- 변경된 파일을 직접 읽어서 전체 맥락 파악
- diff 만 보지 말고 관련 코드도 함께 확인
- `paths.implementation` 안의 변경인지 / 테스트인지 / 문서인지 분류

### 3. 체크리스트
- [ ] 다른 기능에 영향이 없는가 (호출처 추적)
- [ ] 보안 취약점은 없는가 (injection / XSS / 인가 누락 / 시크릿 노출)
- [ ] 로직 오류 / 엣지 케이스 누락은 없는가
- [ ] 성능 문제는 없는가 (N+1, 큰 트랜잭션, 불필요한 fetch)
- [ ] 코드 스타일이 기존과 일관되는가 (CLAUDE.md 컨벤션 대조)
- [ ] 테스트 커버리지 — 사용자 행동 흐름 변경인데 E2E 없는지, 비즈니스 룰 변경인데 단위 테스트 없는지
- [ ] 문서 동기화 — 사용자 가시 변경인데 README / CLAUDE.md 사실 영역 그대로인지

### 4. 리뷰 코멘트 작성

GitHub PR 에 코멘트를 남긴다 (`gh api` 또는 `gh pr comment`).
코멘트 언어는 `project.json` 의 `language` 따름.

리뷰 코멘트 템플릿:

```
[심각도] 카테고리: 제목

내용 설명

> 제안: 수정 방향 (있으면)
```

심각도:
- 🔴 must: 반드시 수정 (머지 전 필수)
- 🟡 should: 수정 권장 (사유 있으면 스킵 가능)
- 🟢 nit: 사소한 개선 (선택)
- 💬 question: 질문/확인 (답변 필요)

카테고리: 버그, 보안, 성능, 로직, 스타일, 설계, 테스트, 문서

### 5. 종합 의견
- PR 전체에 대한 종합 코멘트를 남긴다
- 발견된 이슈 요약
- 전반적인 코드 품질 평가

## 옵션: reviewer 에이전트 위임

본 세션에서 직접 리뷰하지 않고 별도 세션의 `reviewer` 에이전트에 위임하려면:

```
Agent({
  subagent_type: "reviewer",
  description: "PR #$0 코드 리뷰",
  prompt: "PR #$0 을 리뷰하고 결과를 GitHub 코멘트로 남겨라. 프로젝트 .claude/project.json 과 CLAUDE.md 의 컨벤션을 참고. 직접 작업 세션과 별도이므로 plain text 보고로 끝내지 말고 반드시 GitHub 코멘트로 — 작업 세션이 /followup 으로 수집할 수 있어야 함."
})
```

## 절대 금지
- 코드를 직접 수정하지 않는다
- PR 을 승인하거나 머지하지 않는다
- 리뷰 결과는 반드시 GitHub 코멘트로 남긴다 (plain text 출력만 X)
