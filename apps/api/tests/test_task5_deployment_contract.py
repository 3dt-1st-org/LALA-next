from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


def _text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_env_example_documents_guest_logto_and_public_flutter_configuration():
    env = _text(".env.example")

    for assignment in (
        "LALA_GUEST_ACCESS=false",
        "LOGTO_ENDPOINT=",
        "LOGTO_API_AUDIENCE=",
        "LOGTO_NATIVE_APP_ID=",
        "LOGTO_WEB_APP_ID=",
        "LOGTO_REDIRECT_URI=",
        "LOGTO_POST_LOGOUT_REDIRECT_URI=",
        "LOGTO_MANAGEMENT_ENDPOINT=",
        "LOGTO_MANAGEMENT_CLIENT_ID=",
        "LOGTO_MANAGEMENT_CLIENT_SECRET=",
    ):
        assert assignment in env
    assert re.search(r"^LOGTO_MANAGEMENT_CLIENT_SECRET=$", env, re.MULTILINE)


def test_current_deployment_docs_describe_aws_api_rds_and_vercel_flutter():
    aws = _text("docs/operations/aws-deployment-runbook.md")
    vercel = _text("docs/operations/vercel-deployment.md")

    for term in ("Flutter web", "Vercel", "FastAPI", "EC2", "nginx", "Cloudflare", "RDS"):
        assert term in aws
    assert "Flutter web" in vercel
    assert "AWS EC2" in vercel
    assert "FastAPI backend" not in vercel.split("## Historical", maxsplit=1)[0]


def test_flutter_vercel_static_output_uses_isolated_effective_config(tmp_path):
    root_config = json.loads(_text("vercel.json"))
    assert root_config["rewrites"][0]["destination"] == "/api/index.py"

    template = json.loads(_text("deploy/vercel/flutter-static.vercel.json"))
    build_output = tmp_path / "build" / "web"
    build_output.mkdir(parents=True)
    (build_output / "index.html").write_text("<html></html>", encoding="utf-8")
    (build_output / "vercel.json").write_text(
        json.dumps({"rewrites": [{"source": "/(.*)", "destination": "/api/index.py"}]}),
        encoding="utf-8",
    )
    static_output = tmp_path / "static-output"

    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts" / "prepare_flutter_vercel_static_output.py"),
            "--source",
            str(build_output),
            "--output",
            str(static_output),
        ],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )

    effective = json.loads((static_output / "vercel.json").read_text(encoding="utf-8"))
    assert effective == template
    assert "/api/index.py" not in json.dumps(effective)
    assert effective["rewrites"] == [{"source": "/(.*)", "destination": "/index.html"}]
    assert (static_output / "index.html").is_file()

    deployment_doc = _text("docs/operations/vercel-deployment.md")
    assert "python3 scripts/prepare_flutter_vercel_static_output.py" in deployment_doc
    assert "vercel deploy static-output --prod" in deployment_doc
    assert "static-output/" in _text(".gitignore")


def test_aws_logto_rollout_covers_schema_secrets_clients_connectors_smoke_and_rollback():
    aws = _text("docs/operations/aws-deployment-runbook.md")

    for term in (
        "sql/canonical/005_identity_users.sql",
        "Secrets Manager",
        "LALA_GUEST_ACCESS",
        "LOGTO_ENDPOINT",
        "LOGTO_API_AUDIENCE",
        "LOGTO_MANAGEMENT_CLIENT_ID",
        "LOGTO_MANAGEMENT_CLIENT_SECRET",
        "LOGTO_NATIVE_APP_ID",
        "LOGTO_WEB_APP_ID",
        "LOGTO_REDIRECT_URI",
        "LOGTO_POST_LOGOUT_REDIRECT_URI",
        "Google",
        "Apple",
        "M2M",
        "/api/v1/me",
        "rollback",
    ):
        assert term in aws


def test_apple_upstream_revoke_is_an_explicit_live_release_gate_without_fake_fallback():
    aws = _text("docs/operations/aws-deployment-runbook.md")

    assert "release gate" in aws
    assert "live connector integration" in aws
    assert "provider refresh token" in aws
    assert "block launch" in aws
    assert "direct `/auth/revoke` fallback" not in aws
    assert "server fallback is not supported" in aws


def test_current_handoff_docs_are_guest_first_and_keep_me_oauth_only():
    docs = "\n".join(
        _text(path)
        for path in (
            "docs/api/flutter-contract.md",
            "docs/api/flutter-handoff-checklist.md",
            "docs/api/openapi-usage.md",
        )
    )

    assert "LALA_GUEST_ACCESS" in docs
    assert "guest" in docs.lower()
    assert "GET /api/v1/me" in docs
    assert "DELETE /api/v1/me" in docs
    assert "Bearer-only" in docs
    assert "presented credentials" in docs


def test_aws_runbook_has_no_plaintext_password_or_live_dsn_example():
    aws = _text("docs/operations/aws-deployment-runbook.md")

    assert "PGPASSWORD='" not in aws
    assert "LalaNext2024" not in aws
    assert not re.search(r"postgres(?:ql)?://[^\s<>]+", aws)
    assert "aws secretsmanager get-secret-value" in aws
