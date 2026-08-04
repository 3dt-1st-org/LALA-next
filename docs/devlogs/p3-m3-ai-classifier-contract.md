# P3-M3: AI Classifier Contract Implementation

## Summary
Implemented a provider-neutral, offline-testable contract for the second-stage AI ad/relevance classifier. This is the second-stage AI classifier that processes deterministic preprocessing results to detect ads and determine relevance with strict fail-closed behavior.

## Security Corrections (2026-08-05)
Addressed independent audit findings with minimal fixes:
- **Privacy**: Removed all raw/normalized review text from prompt builder return value
- **Error messages**: Made all parser errors generic without input details
- **Schema version**: Added strict validation requiring exact SCHEMA_VERSION match
- **Fail-closed logic**: Implemented strict decision/confidence validation with recheck requirements
- **Construction validation**: Added frozen dataclass __post_init__ validation enforcing bounded schema with generic errors

## Implementation Date
2026-08-05

## Scope and Boundaries
**OFFLINE CONTRACT ONLY** - This implementation deliberately excludes:
- Live OpenAI API calls (uses Standard OpenAI bulk role: `review_bulk`, recommended `gpt-5.4-nano`)
- Naver acquisition/scraping
- Worker/DB migration
- Apply mode integration
- API route exposure
- Recheck execution workflow

All AI interactions are mocked using `MockAIResponse` helpers. This is an offline contract definition only.

## Core Contract Requirements Implemented

### 1. Deterministic Filter Prerequisite
- AI classifier only processes results that pass deterministic preprocessing
- `apply_ai_classification()` preserves deterministic rejections without override
- Category policy preservation (attraction food-only reviews remain rejected)
- Restaurant food term preservation vs attraction experience term policies

### 2. Fail-Closed JSON Parsing
- Strict schema validation with `AIClassificationResult` frozen dataclass
- Bounded field values: `ALLOWED_DECISIONS`, `ALLOWED_REASON_CODES`
- Confidence range validation: 0.0 to 1.0
- `parse_ai_response()` raises `AIClassifierValidationError` on any deviation
- No partial parsing or silent acceptance of malformed responses

### 3. Model-Role Resolution
- Uses existing `model_client.resolve()` infrastructure
- Resolves to `review_bulk` role (gpt-5.4-nano) by default
- Supports `LALA_MODEL_ROLE_REVIEW_BULK` environment override
- Provider-agnostic design (OpenAI only, Azure rejected at base URL level)

### 4. Immutable Classification Results
- `AIClassificationResult` frozen dataclass with bounded fields:
  - `schema_version`, `decision`, `is_ad`, `is_relevant`
  - `ad_confidence`, `relevance_confidence`, `reason_code`
- No raw text or free-form AI responses persisted
- Public dict contains only safe, bounded fields

### 5. Safe Exception Handling
- `AIClassifierError` base class with safe messages only
- `AIClassifierValidationError` for schema failures
- `AIClassifierConfigurationError` for setup issues
- No input content, secrets, or provider details in exceptions

### 6. Pure Function Application
- `apply_ai_classification(deterministic_decision, ai_result)` returns new decision
- Never mutates input objects
- Preserves all immutable fields from deterministic preprocessing
- Confidence thresholds: 0.7 for high confidence, 0.5 for recheck

### 7. Low Confidence Handling
- Results below `RECHECK_THRESHOLD` (0.5) get `retained=False, reason="recheck_required"`
- Recheck items are not filtered but deferred to human/higher-confidence review
- Prevents false positives from low-confidence AI predictions

### 8. Category Policy Preservation
- Restaurant: food term reviews retained (if organic)
- Attraction: food-only reviews rejected (even if AI says organic)
- Policy field preserved through AI application
- AI cannot override deterministic category policies

### 9. Secret-Free Prompt Building
- `AIClassifierPrompt` dataclass with versioned prompts
- No secrets or API keys in prompt construction
- Structured input only, no raw prompt text for logging
- Version tracking for prompt evolution

## Architecture Decisions

### Offline Boundary
All AI interactions are mocked using `MockAIResponse` helpers. The contract defines:
- What inputs the AI receives (structured prompts)
- What outputs the AI must produce (schema-compliant JSON)
- How to validate and apply those outputs deterministically

### Model-Role Split
- **Bulk processing**: `review_bulk` role → gpt-5.4-nano (high volume, low cost)
- **Recheck processing**: `review_recheck` role → gpt-5.4-mini (low volume, higher quality)
- This implementation uses bulk model only; recheck is separate workflow

### Confidence Thresholds
- **CONFIDENCE_THRESHOLD = 0.7**: High confidence for definitive actions
- **RECHECK_THRESHOLD = 0.5**: Minimum confidence for any retention
- **0.5-0.7 range**: Recheck required (not rejected, not retained)
- **<0.5**: Effectively rejected as too uncertain

## Test Coverage
63 comprehensive test cases covering:
- Model-role resolution and configuration
- System prompt building and versioning
- JSON parsing with strict validation
- Bounded field validation (decisions, reason codes, confidence)
- Classification application logic
- Deterministic rejection preservation
- Category policy preservation
- Mock response helpers for all scenarios
- **Security-focused tests**:
  - Prompt builder privacy (no raw text exposure)
  - Generic error messages (no input leakage)
  - Schema version strictness
  - Fail-closed decision/confidence application
  - Direct construction validation (invalid schema/version/decision/reason/confidence)

## Remaining Gates
This implementation is complete for the **offline contract only**. Remaining work for production:
1. **Live AI Integration**: Wire up actual OpenAI client calls
2. **Worker Integration**: Add to batch processing workflow
3. **DB Schema**: Add AI classification fields to attributes table
4. **Monitoring**: Add metrics for confidence distribution, recheck rate
5. **Prompt Engineering**: Iterate on prompt based on production data
6. **Recheck Workflow**: Implement human review or higher-confidence recheck

## Files Created
- `apps/api/app/services/review_ai_classifier.py` - Main implementation
- `apps/api/tests/test_review_ai_classifier.py` - Comprehensive test suite (63 tests)
- `docs/devlogs/p3-m3-ai-classifier-contract.md` - This documentation

## Verification
- ✅ All 63 tests passing
- ✅ Ruff linting passed with auto-fixes applied
- ✅ Pre-commit hooks passed (ruff, format, detect-secrets, trailing whitespace, EOF)
- ✅ No live AI calls (all mocks)
- ✅ No database migrations (offline contract only)
- ✅ No Naver/scraping integration (out of scope)

## Next Steps
1. Create Draft PR with conventional commit format
2. Merge offline contract implementation
3. Subsequent work for live AI integration and worker deployment
