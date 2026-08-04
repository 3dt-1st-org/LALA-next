"""Comprehensive offline tests for P3-M3 AI classifier contract.

These tests verify the strict contract requirements without making any live AI calls.
All tests use mock responses and deterministic inputs to ensure the classifier
behaves correctly in all scenarios.
"""

from datetime import UTC, datetime

import pytest

from apps.api.app.services.review_ai_classifier import (
    CONFIDENCE_THRESHOLD,
    RECHECK_THRESHOLD,
    AIClassificationResult,
    AIClassifierConfigurationError,
    AIClassifierValidationError,
    MockAIResponse,
    apply_ai_classification,
    build_system_prompt,
    parse_ai_response,
    resolve_bulk_model,
)
from apps.api.app.services.review_mention_ingest import (
    ReviewMentionDecision,
    ReviewMentionPlace,
    ReviewMentionPost,
)


class TestAIClassifierConfiguration:
    """Test model-role resolution and configuration."""

    def test_resolve_bulk_model_returns_valid_model_id(self):
        """Should resolve to a valid model ID string."""
        model_id = resolve_bulk_model()
        assert isinstance(model_id, str)
        assert len(model_id) > 0
        # Should be a standard OpenAI model format
        assert model_id.startswith("gpt-") or "model" in model_id.lower()

    def test_resolve_bulk_model_raises_on_configuration_error(self, monkeypatch):
        """Should raise configuration error when resolution fails."""

        def failing_resolve(*args, **kwargs):
            raise ValueError("Model not found")

        monkeypatch.setattr("apps.api.app.services.review_ai_classifier.resolve", failing_resolve)

        with pytest.raises(AIClassifierConfigurationError):
            resolve_bulk_model()


class TestSystemPrompt:
    """Test system prompt generation."""

    def test_build_system_prompt_returns_string(self):
        """Should return a non-empty prompt string."""
        prompt = build_system_prompt()
        assert isinstance(prompt, str)
        assert len(prompt) > 0

    def test_system_prompt_contains_classification_rules(self):
        """Prompt should contain clear classification rules."""
        prompt = build_system_prompt()
        assert "classify" in prompt.lower()
        assert "json" in prompt.lower()
        assert "decision" in prompt.lower()
        assert "confidence" in prompt.lower()

    def test_system_prompt_is_secret_free(self):
        """Prompt should not contain secrets or sensitive data."""
        prompt = build_system_prompt()
        # Should not contain API keys, URLs, or sensitive identifiers
        assert "api_key" not in prompt.lower()
        assert "http" not in prompt.lower()
        assert "password" not in prompt.lower()
        assert "token" not in prompt.lower()


class TestJSONParsingStrict:
    """Test strict JSON parsing with fail-closed behavior."""

    def test_parse_valid_organic_response(self):
        """Should parse valid organic classification."""
        response = MockAIResponse.organic(confidence=0.9)
        results = parse_ai_response(response.raw, expected_count=1)

        assert len(results) == 1
        result = results[0]
        assert result.decision == "organic"
        assert result.is_ad is False
        assert result.is_relevant is True
        assert result.ad_confidence == 0.9
        assert result.relevance_confidence == 0.9
        assert result.reason_code == "organic_mention"

    def test_parse_valid_ad_filtered_response(self):
        """Should parse valid ad filtered classification."""
        response = MockAIResponse.ad_filtered(confidence=0.95)
        results = parse_ai_response(response.raw, expected_count=1)

        assert len(results) == 1
        result = results[0]
        assert result.decision == "ad_filtered"
        assert result.is_ad is True
        assert result.is_relevant is False
        assert result.ad_confidence == 0.95

    def test_parse_uncertain_response(self):
        """Should parse uncertain classification."""
        response = MockAIResponse.uncertain(confidence=0.4)
        results = parse_ai_response(response.raw, expected_count=1)

        assert len(results) == 1
        result = results[0]
        assert result.decision == "uncertain"
        assert result.ad_confidence == 0.4
        assert result.relevance_confidence == 0.4
        assert result.reason_code == "low_confidence"

    def test_parse_multiple_results(self):
        """Should parse multiple results correctly."""
        import json

        multi_response = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "organic",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": 0.9,
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    },
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "ad_filtered",
                        "is_ad": True,
                        "is_relevant": False,
                        "ad_confidence": 0.85,
                        "relevance_confidence": 0.3,
                        "reason_code": "advertising_detected",
                    },
                ]
            }
        )

        results = parse_ai_response(multi_response, expected_count=2)
        assert len(results) == 2
        assert results[0].decision == "organic"
        assert results[1].decision == "ad_filtered"

    def test_fail_on_malformed_json(self):
        """Should raise validation error for malformed JSON."""
        response = MockAIResponse.malformed()

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response.raw, expected_count=1)

    def test_fail_on_missing_required_fields(self):
        """Should raise validation error for missing required fields."""
        response = MockAIResponse.missing_fields()

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response.raw, expected_count=1)

    def test_fail_on_extra_forbidden_fields(self):
        """Should raise validation error for extra fields."""
        response = MockAIResponse.extra_fields()

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response.raw, expected_count=1)

    def test_fail_on_wrong_result_count(self):
        """Should raise validation error for incorrect result count."""
        response = MockAIResponse.organic()

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response.raw, expected_count=2)

    def test_fail_on_invalid_decision_value(self):
        """Should raise validation error for invalid decision."""
        import json

        response = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "invalid_decision",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": 0.9,
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    }
                ]
            }
        )

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)

    def test_fail_on_invalid_confidence_range(self):
        """Should raise validation error for confidence out of range."""
        import json

        response = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "organic",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": 1.5,  # Invalid: > 1.0
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    }
                ]
            }
        )

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)

    def test_fail_on_wrong_confidence_type(self):
        """Should raise validation error for non-numeric confidence."""
        import json

        response = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "organic",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": "high",  # Invalid: not a number
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    }
                ]
            }
        )

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)

    def test_fail_on_non_object_root(self):
        """Should raise validation error for non-object root."""
        import json

        response = json.dumps(["not", "an", "object"])

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)

    def test_fail_on_missing_results_list(self):
        """Should raise validation error for missing results list."""
        import json

        response = json.dumps({"not_results": []})

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)

    def test_fail_on_non_list_results(self):
        """Should raise validation error for non-list results."""
        import json

        response = json.dumps({"results": "not a list"})

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)

    def test_fail_on_non_object_result_item(self):
        """Should raise validation error for non-object result item."""
        import json

        response = json.dumps({"results": ["not an object"]})

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)


class TestBoundedFields:
    """Test that all result fields are properly bounded and validated."""

    def test_schema_version_is_fixed(self):
        """Schema version should always be the fixed value."""
        result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,
            is_relevant=True,
            ad_confidence=0.9,
            relevance_confidence=0.9,
            reason_code="organic_mention",
        )
        assert result.schema_version == "review-ai-classifier-v1"

    def test_decision_values_are_bounded(self):
        """Decision field should only accept allowed values."""
        from apps.api.app.services.review_ai_classifier import ALLOWED_DECISIONS

        for decision in ALLOWED_DECISIONS:
            result = AIClassificationResult(
                schema_version="review-ai-classifier-v1",
                decision=decision,
                is_ad=False,
                is_relevant=True,
                ad_confidence=0.8,
                relevance_confidence=0.8,
                reason_code="organic_mention",
            )
            assert result.decision == decision

    def test_reason_code_values_are_bounded(self):
        """Reason code field should only accept allowed values."""
        from apps.api.app.services.review_ai_classifier import ALLOWED_REASON_CODES

        for reason_code in ALLOWED_REASON_CODES:
            result = AIClassificationResult(
                schema_version="review-ai-classifier-v1",
                decision="organic",
                is_ad=False,
                is_relevant=True,
                ad_confidence=0.8,
                relevance_confidence=0.8,
                reason_code=reason_code,
            )
            assert result.reason_code == reason_code

    def test_confidence_values_are_bounded(self):
        """Confidence values should always be between 0 and 1."""
        for confidence in [0.0, 0.5, 0.7, 1.0]:
            result = AIClassificationResult(
                schema_version="review-ai-classifier-v1",
                decision="organic",
                is_ad=False,
                is_relevant=True,
                ad_confidence=confidence,
                relevance_confidence=confidence,
                reason_code="organic_mention",
            )
            assert 0.0 <= result.ad_confidence <= 1.0
            assert 0.0 <= result.relevance_confidence <= 1.0

    def test_public_dict_contains_no_sensitive_data(self):
        """Public dict should contain only safe, bounded fields."""
        result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,
            is_relevant=True,
            ad_confidence=0.9,
            relevance_confidence=0.9,
            reason_code="organic_mention",
        )

        public = result.to_public_dict()

        # Should only contain the bounded fields
        expected_keys = {
            "schema_version",
            "decision",
            "is_ad",
            "is_relevant",
            "ad_confidence",
            "relevance_confidence",
            "reason_code",
        }
        assert set(public.keys()) == expected_keys

        # Should not contain raw text or excerpts
        assert "text" not in str(public).lower()
        assert "excerpt" not in str(public).lower()
        assert "content" not in str(public).lower()


def _create_decision(
    retained: bool = True,
    is_ad: bool = False,
    is_relevant: bool = True,
    reason: str = "organic_retained",
) -> ReviewMentionDecision:
    """Helper to create test decisions."""
    post = ReviewMentionPost(
        provider="test_provider",
        external_key="test_key",
        keyword=None,
        region_slug=None,
        title=None,
        body="Test content",
        post_url=None,
        created_at_source=datetime.now(UTC),
        collected_at=datetime.now(UTC),
    )

    place = ReviewMentionPlace(
        place_id="test_place",
        name_ko="테스트 장소",
        category="attraction",
        region_name_ko="서울",
    )

    return ReviewMentionDecision(
        post=post,
        place=place,
        normalized_text="test content",
        content_sha256="abc123",
        is_ad=is_ad,
        is_relevant=is_relevant,
        retained=retained,
        reason=reason,
        match_confidence=0.9,
        match_method="exact_name_in_text",
        category_policy="place_experience_terms_retained",
        week_start=datetime.now(UTC).date(),
        top_terms=(),
    )


class TestPromptBuilderSecurity:
    """Test that prompt builder doesn't expose sensitive data."""

    def test_no_raw_text_in_classification_input(self):
        """Classification input must not contain raw or normalized review text."""
        from apps.api.app.services.review_ai_classifier import AIClassifierPrompt

        # Create a decision with a unique secret-shaped review string
        secret_review = (
            "SECRET_REVIEW_CONTENT_12345678_UNIQUE_IDENTIFIER"  # pragma: allowlist secret
        )

        post = ReviewMentionPost(
            provider="test_provider",
            external_key="test_key",
            keyword=None,
            region_slug=None,
            title=None,
            body=secret_review,
            post_url=None,
            created_at_source=datetime.now(UTC),
            collected_at=datetime.now(UTC),
        )

        place = ReviewMentionPlace(
            place_id="test_place",
            name_ko="테스트 장소",
            category="attraction",
            region_name_ko="서울",
        )

        decision = ReviewMentionDecision(
            post=post,
            place=place,
            normalized_text=secret_review,
            content_sha256="abc123",
            is_ad=False,
            is_relevant=True,
            retained=True,
            reason="organic_retained",
            match_confidence=0.9,
            match_method="exact_name_in_text",
            category_policy="place_experience_terms_retained",
            week_start=datetime.now(UTC).date(),
            top_terms=(),
        )

        prompt = AIClassifierPrompt()
        result = prompt.build_classification_input([decision])

        # Assert the secret is NOT present in the result
        result_str = str(result)
        assert secret_review not in result_str

        # Assert no text fields are present
        assert "normalized_text" not in result_str
        assert "text" not in result_str
        # "content_hash" is OK (just hash), but not "content" fields with actual data
        assert "body" not in result_str
        assert "excerpt" not in result_str

        # Assert only bounded metadata fields are present
        assert "external_key" in result_str
        assert "provider" in result_str
        assert "place_id" in result_str
        assert "category" in result_str
        assert "content_hash" in result_str


class TestGenericErrorMessages:
    """Test that all validation errors use generic messages."""

    def test_error_messages_do_not_contain_input_details(self):
        """Generic error messages must not expose input values, field names, or indices."""
        import json

        secret_value = "SECRET_INPUT_98765_ZYXW"  # pragma: allowlist secret

        # Test with unknown key containing secret
        response_with_secret = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "organic",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": 0.9,
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                        secret_value: "should_not_appear",  # Unknown field  # pragma: allowlist secret
                    }
                ]
            }
        )

        with pytest.raises(AIClassifierValidationError) as exc_info:
            parse_ai_response(response_with_secret, expected_count=1)

        error_message = str(exc_info.value)
        # Assert the generic message is used
        assert error_message == "Invalid AI classifier response"

        # Assert the secret does NOT appear in the error message
        assert secret_value not in error_message
        assert "should_not_appear" not in error_message

        # Assert no field names, indices, or technical details appear
        assert "Result" not in error_message
        assert "field" not in error_message.lower()
        assert "decision" not in error_message
        assert "confidence" not in error_message
        assert "0" not in error_message  # No indices
        assert "1" not in error_message

    def test_invalid_decision_shows_generic_error(self):
        """Invalid decision value must not appear in error message."""
        import json

        response = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "INVALID_SECRET_DECISION_VALUE",  # pragma: allowlist secret
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": 0.9,
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    }
                ]
            }
        )

        with pytest.raises(AIClassifierValidationError) as exc_info:
            parse_ai_response(response, expected_count=1)

        error_message = str(exc_info.value)
        assert error_message == "Invalid AI classifier response"
        assert "INVALID_SECRET_DECISION_VALUE" not in error_message
        assert "invalid decision" not in error_message.lower()

    def test_invalid_confidence_shows_generic_error(self):
        """Invalid confidence value must not appear in error message."""
        import json

        response = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "organic",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": "INVALID_SECRET_CONFIDENCE",  # pragma: allowlist secret
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    }
                ]
            }
        )

        with pytest.raises(AIClassifierValidationError) as exc_info:
            parse_ai_response(response, expected_count=1)

        error_message = str(exc_info.value)
        assert error_message == "Invalid AI classifier response"
        assert "INVALID_SECRET_CONFIDENCE" not in error_message


class TestSchemaVersionStrictness:
    """Test strict schema version validation."""

    def test_exact_schema_version_required(self):
        """Schema version must match exactly."""
        import json

        response = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "review-ai-classifier-v1",
                        "decision": "organic",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": 0.9,
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    }
                ]
            }
        )

        results = parse_ai_response(response, expected_count=1)
        assert results[0].schema_version == "review-ai-classifier-v1"

    def test_missing_schema_version_rejected(self):
        """Missing schema version must be rejected."""
        import json

        response = json.dumps(
            {
                "results": [
                    {
                        "decision": "organic",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": 0.9,
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    }
                ]
            }
        )

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)

    def test_wrong_schema_version_rejected(self):
        """Wrong schema version must be rejected."""
        import json

        response = json.dumps(
            {
                "results": [
                    {
                        "schema_version": "wrong-version-v2",
                        "decision": "organic",
                        "is_ad": False,
                        "is_relevant": True,
                        "ad_confidence": 0.9,
                        "relevance_confidence": 0.9,
                        "reason_code": "organic_mention",
                    }
                ]
            }
        )

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(response, expected_count=1)

    def test_schema_version_in_prompt(self):
        """System prompt must show the required schema version field."""
        from apps.api.app.services.review_ai_classifier import SCHEMA_VERSION

        prompt = build_system_prompt()
        assert "schema_version" in prompt
        assert SCHEMA_VERSION in prompt


class TestFailClosedApplication:
    """Test fail-closed decision and confidence application."""

    def test_uncertain_always_recheck_required(self):
        """Decision 'uncertain' must always become recheck_required regardless of confidence."""
        deterministic = _create_decision(retained=True)
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="uncertain",
            is_ad=False,
            is_relevant=True,
            ad_confidence=0.9,  # High confidence but uncertain decision
            relevance_confidence=0.9,
            reason_code="low_confidence",
        )

        result = apply_ai_classification(deterministic, ai_result)

        assert result.retained is False
        assert result.reason == "recheck_required"

    def test_non_definitive_confidence_requires_recheck(self):
        """Confidence in [0.5, 0.7) must become recheck_required, not organic."""
        deterministic = _create_decision(retained=True)
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,
            is_relevant=True,
            ad_confidence=0.6,  # In non-definitive band
            relevance_confidence=0.8,  # Above threshold
            reason_code="organic_mention",
        )

        result = apply_ai_classification(deterministic, ai_result)

        # Must be recheck_required, not retained as organic
        assert result.retained is False
        assert result.reason == "recheck_required"

    def test_inconsistent_ad_flag_rejected(self):
        """High ad_confidence with non-ad_filtered decision must fail closed."""
        deterministic = _create_decision(retained=True)
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",  # Inconsistent with is_ad=True
            is_ad=True,  # Inconsistent with organic decision
            is_relevant=True,
            ad_confidence=0.9,
            relevance_confidence=0.9,
            reason_code="organic_mention",
        )

        result = apply_ai_classification(deterministic, ai_result)

        # Must fail closed to recheck, not promote to organic
        assert result.retained is False
        assert result.reason == "recheck_required"

    def test_inconsistent_irrelevant_flag_rejected(self):
        """High relevance_confidence with irrelevant decision must fail closed."""
        deterministic = _create_decision(retained=True)
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",  # Inconsistent with is_relevant=False
            is_ad=False,
            is_relevant=False,  # Inconsistent with organic decision
            ad_confidence=0.9,
            relevance_confidence=0.9,
            reason_code="organic_mention",
        )

        result = apply_ai_classification(deterministic, ai_result)

        # Must fail closed to recheck, not promote to organic
        assert result.retained is False
        assert result.reason == "recheck_required"

    def test_markdown_fences_rejected(self):
        """Markdown fences must be rejected, not stripped."""
        markdown_wrapped = f"""```json
{MockAIResponse.organic().raw}
```"""

        with pytest.raises(AIClassifierValidationError, match="Invalid AI classifier response"):
            parse_ai_response(markdown_wrapped, expected_count=1)


class TestApplyAIClassification:
    """Test application of AI classification to deterministic results."""

    def test_preserves_deterministic_rejections(self):
        """Should never override deterministic rejections."""
        deterministic = _create_decision(retained=False, reason="no_place_match")
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,
            is_relevant=True,
            ad_confidence=0.95,
            relevance_confidence=0.95,
            reason_code="organic_mention",
        )

        result = apply_ai_classification(deterministic, ai_result)

        # Should still be rejected
        assert result.retained is False
        assert result.reason == "no_place_match"

    def test_preserves_deterministic_ad_detection(self):
        """Should never override deterministic ad detection."""
        deterministic = _create_decision(is_ad=True, retained=True, reason="advertising_filtered")
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,  # AI says not ad
            is_relevant=True,
            ad_confidence=0.95,
            relevance_confidence=0.95,
            reason_code="organic_mention",
        )

        result = apply_ai_classification(deterministic, ai_result)

        # Should still be marked as ad
        assert result.is_ad is True

    def test_low_confidence_marks_recheck_required(self):
        """Should mark for recheck when confidence is below threshold."""
        deterministic = _create_decision(retained=True)
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="uncertain",
            is_ad=False,
            is_relevant=True,
            ad_confidence=RECHECK_THRESHOLD - 0.1,
            relevance_confidence=RECHECK_THRESHOLD - 0.1,
            reason_code="low_confidence",
        )

        result = apply_ai_classification(deterministic, ai_result)

        assert result.retained is False
        assert result.reason == "recheck_required"

    def test_high_confidence_ad_detection_gets_filtered(self):
        """Should filter ads when AI confidence is high."""
        deterministic = _create_decision(retained=True)
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="ad_filtered",
            is_ad=True,
            is_relevant=False,
            ad_confidence=CONFIDENCE_THRESHOLD + 0.1,
            relevance_confidence=0.3,
            reason_code="advertising_detected",
        )

        result = apply_ai_classification(deterministic, ai_result)

        assert result.retained is False
        # is_ad should be True based on AI result, not deterministic (original is_ad=False)
        assert result.is_ad is True
        assert result.reason == "advertising_filtered"

    def test_high_confidence_irrelevant_gets_filtered(self):
        """Should filter irrelevant content when AI confidence is high."""
        deterministic = _create_decision(retained=True)
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="irrelevant",
            is_ad=False,
            is_relevant=False,
            ad_confidence=0.3,
            relevance_confidence=CONFIDENCE_THRESHOLD + 0.1,
            reason_code="off_topic_content",
        )

        result = apply_ai_classification(deterministic, ai_result)

        assert result.retained is False
        assert result.is_relevant is False
        assert result.reason == "ai_classified_irrelevant"

    def test_high_confidence_organic_gets_confirmed(self):
        """Should confirm and retain high-confidence organic content."""
        deterministic = _create_decision(retained=True)
        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,
            is_relevant=True,
            ad_confidence=CONFIDENCE_THRESHOLD + 0.1,
            relevance_confidence=CONFIDENCE_THRESHOLD + 0.1,
            reason_code="organic_mention",
        )

        result = apply_ai_classification(deterministic, ai_result)

        assert result.retained is True
        assert result.is_ad is False
        assert result.is_relevant is True
        assert result.reason == "ai_confirmed_organic"

    def test_preserves_immutable_fields(self):
        """Should preserve all immutable fields from original decision."""
        deterministic = _create_decision(retained=True)
        original_values = {
            "post": deterministic.post,
            "place": deterministic.place,
            "normalized_text": deterministic.normalized_text,
            "content_sha256": deterministic.content_sha256,
            "match_confidence": deterministic.match_confidence,
            "match_method": deterministic.match_method,
            "category_policy": deterministic.category_policy,
            "week_start": deterministic.week_start,
            "top_terms": deterministic.top_terms,
        }

        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,
            is_relevant=True,
            ad_confidence=0.9,
            relevance_confidence=0.9,
            reason_code="organic_mention",
        )

        result = apply_ai_classification(deterministic, ai_result)

        # All immutable fields should be preserved
        assert result.post == original_values["post"]
        assert result.place == original_values["place"]
        assert result.normalized_text == original_values["normalized_text"]
        assert result.content_sha256 == original_values["content_sha256"]
        assert result.match_confidence == original_values["match_confidence"]
        assert result.match_method == original_values["match_method"]
        assert result.category_policy == original_values["category_policy"]
        assert result.week_start == original_values["week_start"]
        assert result.top_terms == original_values["top_terms"]


class TestCategoryPolicyPreservation:
    """Test that category policies are preserved through AI classification."""

    def test_restaurant_food_terms_are_preserved(self):
        """Restaurant food terms should be preserved as valid content."""
        post = ReviewMentionPost(
            provider="test",
            external_key="restaurant_review",
            keyword=None,
            region_slug=None,
            title="맛집 리뷰",
            body="맛있는 고기와 친절한 서비스",
            post_url=None,
            created_at_source=datetime.now(UTC),
            collected_at=datetime.now(UTC),
        )

        place = ReviewMentionPlace(
            place_id="restaurant_1",
            name_ko="테스트 식당",
            category="restaurant",
            region_name_ko="서울",
        )

        decision = ReviewMentionDecision(
            post=post,
            place=place,
            normalized_text="맛있는 고기와 친절한 서비스",
            content_sha256="hash123",
            is_ad=False,
            is_relevant=True,
            retained=True,
            reason="organic_retained",
            match_confidence=0.9,
            match_method="exact_name_in_text",
            category_policy="restaurant_food_terms_retained",
            week_start=datetime.now(UTC).date(),
            top_terms=("고기", "친절"),
        )

        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,
            is_relevant=True,
            ad_confidence=0.9,
            relevance_confidence=0.9,
            reason_code="organic_mention",
        )

        result = apply_ai_classification(decision, ai_result)

        # Category policy should be preserved
        assert result.category_policy == "restaurant_food_terms_retained"
        assert result.retained is True

    def test_attraction_food_only_rejection_is_preserved(self):
        """Attraction food-only reviews should remain rejected."""
        decision = ReviewMentionDecision(
            post=ReviewMentionPost(
                provider="test",
                external_key="attraction_food_review",
                keyword=None,
                region_slug=None,
                title="카페 리뷰",
                body="맛있는 디저트와 커피",
                post_url=None,
                created_at_source=datetime.now(UTC),
                collected_at=datetime.now(UTC),
            ),
            place=ReviewMentionPlace(
                place_id="attraction_1",
                name_ko="테스트 미술관",
                category="attraction",
                region_name_ko="서울",
            ),
            normalized_text="맛있는 디저트와 커피",
            content_sha256="hash456",
            is_ad=False,
            is_relevant=False,
            retained=False,
            reason="attraction_food_only_review_rejected",
            match_confidence=0.9,
            match_method="exact_name_in_text",
            category_policy="attraction_food_only_review_rejected",
            week_start=datetime.now(UTC).date(),
            top_terms=("디저트", "커피"),
        )

        ai_result = AIClassificationResult(
            schema_version="review-ai-classifier-v1",
            decision="organic",
            is_ad=False,
            is_relevant=True,
            ad_confidence=0.9,
            relevance_confidence=0.9,
            reason_code="organic_mention",
        )

        result = apply_ai_classification(decision, ai_result)

        # Should remain rejected due to category policy
        assert result.retained is False
        assert result.reason == "attraction_food_only_review_rejected"
        assert result.category_policy == "attraction_food_only_review_rejected"


class TestMockAIResponse:
    """Test MockAIResponse helpers for testing."""

    def test_organic_mock_creates_valid_json(self):
        """Organic mock should create valid JSON that parses correctly."""
        response = MockAIResponse.organic(confidence=0.85)
        results = parse_ai_response(response.raw, expected_count=1)

        assert len(results) == 1
        assert results[0].decision == "organic"
        assert results[0].ad_confidence == 0.85

    def test_ad_filtered_mock_creates_valid_json(self):
        """Ad filtered mock should create valid JSON that parses correctly."""
        response = MockAIResponse.ad_filtered(confidence=0.92)
        results = parse_ai_response(response.raw, expected_count=1)

        assert len(results) == 1
        assert results[0].decision == "ad_filtered"
        assert results[0].is_ad is True

    def test_uncertain_mock_creates_valid_json(self):
        """Uncertain mock should create valid JSON that parses correctly."""
        response = MockAIResponse.uncertain(confidence=0.35)
        results = parse_ai_response(response.raw, expected_count=1)

        assert len(results) == 1
        assert results[0].decision == "uncertain"
        assert results[0].ad_confidence == 0.35

    def test_malformed_mock_creates_invalid_json(self):
        """Malformed mock should create invalid JSON."""
        response = MockAIResponse.malformed()

        with pytest.raises(AIClassifierValidationError):
            parse_ai_response(response.raw, expected_count=1)


# Helper function for test readability
def _create(
    retained: bool = True,
    is_ad: bool = False,
    is_relevant: bool = True,
    reason: str = "organic_retained",
) -> ReviewMentionDecision:
    """Helper to create test decisions - duplicated for compatibility."""
    post = ReviewMentionPost(
        provider="test_provider",
        external_key="test_key",
        keyword=None,
        region_slug=None,
        title=None,
        body="Test content",
        post_url=None,
        created_at_source=datetime.now(UTC),
        collected_at=datetime.now(UTC),
    )

    place = ReviewMentionPlace(
        place_id="test_place",
        name_ko="테스트 장소",
        category="attraction",
        region_name_ko="서울",
    )

    return ReviewMentionDecision(
        post=post,
        place=place,
        normalized_text="test content",
        content_sha256="abc123",
        is_ad=is_ad,
        is_relevant=is_relevant,
        retained=retained,
        reason=reason,
        match_confidence=0.9,
        match_method="exact_name_in_text",
        category_policy="place_experience_terms_retained",
        week_start=datetime.now(UTC).date(),
        top_terms=(),
    )
