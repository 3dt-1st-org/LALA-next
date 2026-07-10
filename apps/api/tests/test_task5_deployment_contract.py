from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

from scripts import prepare_flutter_vercel_static_output as staging


ROOT = Path(__file__).resolve().parents[3]
REQUIRED_FLUTTER_BUILD_FILES = (
    "index.html",
    "flutter_bootstrap.js",
    "main.dart.js",
    "assets/AssetManifest.bin.json",
    "auth-callback.html",
)


def _text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def _write_flutter_build(build_output: Path) -> None:
    for relative_path in REQUIRED_FLUTTER_BUILD_FILES:
        artifact = build_output / relative_path
        artifact.parent.mkdir(parents=True, exist_ok=True)
        artifact.write_text(f"fixture:{relative_path}\n", encoding="utf-8")


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


def test_flutter_vercel_static_output_uses_isolated_effective_config(
    tmp_path, monkeypatch, capsys
):
    root_config = json.loads(_text("vercel.json"))
    assert root_config["rewrites"][0]["destination"] == "/api/index.py"

    template = json.loads(_text("deploy/vercel/flutter-static.vercel.json"))
    isolated_root = tmp_path / "repo"
    build_output = isolated_root / "build" / "web"
    _write_flutter_build(build_output)
    (build_output / "vercel.json").write_text(
        json.dumps({"rewrites": [{"source": "/(.*)", "destination": "/api/index.py"}]}),
        encoding="utf-8",
    )
    static_output = isolated_root / "static-output"
    monkeypatch.setattr(staging, "ROOT", isolated_root)
    monkeypatch.setattr(staging, "DEFAULT_OUTPUT", static_output)
    org_id = "team_contract_fixture"
    project_id = "prj_contract_fixture"
    monkeypatch.setenv("VERCEL_ORG_ID", org_id)
    monkeypatch.setenv("VERCEL_PROJECT_ID", project_id)
    monkeypatch.setattr(
        sys, "argv", ["prepare_flutter_vercel_static_output.py", "--source", str(build_output)]
    )

    assert staging.main() == 0
    stage_output = capsys.readouterr().out
    assert org_id not in stage_output
    assert project_id not in stage_output

    effective = json.loads((static_output / "vercel.json").read_text(encoding="utf-8"))
    assert effective == template
    assert "/api/index.py" not in json.dumps(effective)
    assert effective["rewrites"] == [{"source": "/(.*)", "destination": "/index.html"}]
    assert (static_output / "index.html").is_file()
    project_path = static_output / ".vercel" / "project.json"
    assert project_path.is_file()
    project_binding = json.loads(project_path.read_text(encoding="utf-8"))
    assert project_binding == {"orgId": org_id, "projectId": project_id}

    monkeypatch.setattr(
        sys,
        "argv",
        ["prepare_flutter_vercel_static_output.py", "--verify-project-binding"],
    )
    assert staging.main() == 0
    verification_output = capsys.readouterr().out
    assert org_id not in verification_output
    assert project_id not in verification_output

    deployment_doc = _text("docs/operations/vercel-deployment.md")
    assert "python3 scripts/prepare_flutter_vercel_static_output.py" in deployment_doc
    assert "VERCEL_ORG_ID" in deployment_doc
    assert "VERCEL_PROJECT_ID" in deployment_doc
    verify_command = (
        "python3 scripts/prepare_flutter_vercel_static_output.py "
        "--verify-project-binding"
    )
    assert verify_command in deployment_doc
    assert "vercel deploy static-output --prod" in deployment_doc
    assert deployment_doc.index(verify_command) < deployment_doc.index(
        "vercel deploy static-output --prod"
    )
    assert "static-output/" in _text(".gitignore")


@pytest.mark.parametrize("missing_name", ["VERCEL_ORG_ID", "VERCEL_PROJECT_ID"])
def test_flutter_vercel_staging_requires_project_binding_before_deleting_output(
    tmp_path, monkeypatch, missing_name
):
    isolated_root = tmp_path / "repo"
    build_output = isolated_root / "build" / "web"
    _write_flutter_build(build_output)
    static_output = isolated_root / "static-output"
    static_output.mkdir(parents=True)
    marker = static_output / "keep.txt"
    marker.write_text("keep", encoding="utf-8")
    monkeypatch.setattr(staging, "ROOT", isolated_root)
    monkeypatch.setattr(staging, "DEFAULT_OUTPUT", static_output)
    monkeypatch.setenv("VERCEL_ORG_ID", "team_contract_fixture")
    monkeypatch.setenv("VERCEL_PROJECT_ID", "prj_contract_fixture")
    monkeypatch.delenv(missing_name)
    monkeypatch.setattr(
        sys, "argv", ["prepare_flutter_vercel_static_output.py", "--source", str(build_output)]
    )

    with pytest.raises(SystemExit):
        staging.main()

    assert marker.read_text(encoding="utf-8") == "keep"


@pytest.mark.parametrize(
    ("name", "invalid_value"),
    [
        ("VERCEL_ORG_ID", "contains whitespace"),
        ("VERCEL_PROJECT_ID", "../project"),
    ],
)
def test_flutter_vercel_staging_rejects_invalid_project_binding_without_logging_it(
    tmp_path, monkeypatch, capsys, name, invalid_value
):
    isolated_root = tmp_path / "repo"
    build_output = isolated_root / "build" / "web"
    _write_flutter_build(build_output)
    monkeypatch.setattr(staging, "ROOT", isolated_root)
    monkeypatch.setattr(staging, "DEFAULT_OUTPUT", isolated_root / "static-output")
    monkeypatch.setenv("VERCEL_ORG_ID", "team_contract_fixture")
    monkeypatch.setenv("VERCEL_PROJECT_ID", "prj_contract_fixture")
    monkeypatch.setenv(name, invalid_value)
    monkeypatch.setattr(
        sys, "argv", ["prepare_flutter_vercel_static_output.py", "--source", str(build_output)]
    )

    with pytest.raises(SystemExit):
        staging.main()

    captured = capsys.readouterr()
    assert invalid_value not in captured.out
    assert invalid_value not in captured.err


@pytest.mark.parametrize(
    "tamper",
    ["config", "missing-org", "wrong-project", "extra-project-key"],
)
def test_flutter_vercel_binding_verification_rejects_tampered_staged_contract(
    tmp_path, monkeypatch, tamper
):
    isolated_root = tmp_path / "repo"
    build_output = isolated_root / "build" / "web"
    _write_flutter_build(build_output)
    static_output = isolated_root / "static-output"
    monkeypatch.setattr(staging, "ROOT", isolated_root)
    monkeypatch.setattr(staging, "DEFAULT_OUTPUT", static_output)
    monkeypatch.setenv("VERCEL_ORG_ID", "team_contract_fixture")
    monkeypatch.setenv("VERCEL_PROJECT_ID", "prj_contract_fixture")
    monkeypatch.setattr(
        sys, "argv", ["prepare_flutter_vercel_static_output.py", "--source", str(build_output)]
    )
    assert staging.main() == 0

    project_path = static_output / ".vercel" / "project.json"
    assert project_path.is_file()
    if tamper == "config":
        (static_output / "vercel.json").write_text("{}\n", encoding="utf-8")
    else:
        project = json.loads(project_path.read_text(encoding="utf-8"))
        if tamper == "missing-org":
            project.pop("orgId")
        elif tamper == "wrong-project":
            project["projectId"] = "prj_other_fixture"
        else:
            project["unexpected"] = True
        project_path.write_text(json.dumps(project), encoding="utf-8")
    monkeypatch.setattr(
        sys,
        "argv",
        ["prepare_flutter_vercel_static_output.py", "--verify-project-binding"],
    )

    with pytest.raises(SystemExit):
        staging.main()


def test_flutter_vercel_staging_cli_rejects_arbitrary_output(tmp_path):
    build_output = tmp_path / "build" / "web"
    _write_flutter_build(build_output)
    unrelated = tmp_path / "unrelated-output"
    unrelated.mkdir()
    marker = unrelated / "keep.txt"
    marker.write_text("keep", encoding="utf-8")

    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts" / "prepare_flutter_vercel_static_output.py"),
            "--source",
            str(build_output),
            "--output",
            str(unrelated),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert marker.read_text(encoding="utf-8") == "keep"


@pytest.mark.parametrize(
    "output_case",
    ["symlink", "out-of-root", "parent", "absolute-sibling", "source", "file"],
)
def test_flutter_vercel_staging_rejects_unsafe_output_without_deleting(
    tmp_path, output_case
):
    test_root = tmp_path / "repo"
    build_output = test_root / "build" / "web"
    _write_flutter_build(build_output)
    sibling = tmp_path / "sibling"
    sibling.mkdir()
    sibling_marker = sibling / "keep.txt"
    sibling_marker.write_text("keep", encoding="utf-8")

    if output_case == "symlink":
        output = test_root / "static-output"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.symlink_to(sibling, target_is_directory=True)
        marker = sibling_marker
    elif output_case == "out-of-root":
        output = test_root / ".." / "sibling"
        marker = sibling_marker
    elif output_case == "parent":
        output = test_root
        marker = build_output / "index.html"
    elif output_case == "absolute-sibling":
        output = sibling.resolve()
        marker = sibling_marker
    elif output_case == "source":
        output = build_output
        marker = build_output / "index.html"
    else:
        output = test_root / "static-output"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text("keep", encoding="utf-8")
        marker = output
    marker_contents = marker.read_text(encoding="utf-8")

    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts" / "prepare_flutter_vercel_static_output.py"),
            "--source",
            str(build_output),
            "--output",
            str(output),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert marker.is_file()
    assert marker.read_text(encoding="utf-8") == marker_contents


def test_flutter_vercel_staging_rejects_default_output_symlink_before_deletion(
    tmp_path, monkeypatch
):
    isolated_root = tmp_path / "repo"
    build_output = isolated_root / "build" / "web"
    _write_flutter_build(build_output)
    target = tmp_path / "outside"
    target.mkdir()
    marker = target / "keep.txt"
    marker.write_text("keep", encoding="utf-8")
    default_output = isolated_root / "static-output"
    default_output.symlink_to(target, target_is_directory=True)
    monkeypatch.setattr(staging, "ROOT", isolated_root)
    monkeypatch.setattr(staging, "DEFAULT_OUTPUT", default_output)
    monkeypatch.setattr(
        sys, "argv", ["prepare_flutter_vercel_static_output.py", "--source", str(build_output)]
    )

    with pytest.raises(SystemExit):
        staging.main()

    assert marker.read_text(encoding="utf-8") == "keep"


@pytest.mark.parametrize("missing_path", REQUIRED_FLUTTER_BUILD_FILES)
def test_flutter_vercel_staging_rejects_each_missing_release_artifact_before_deletion(
    tmp_path, monkeypatch, missing_path
):
    isolated_root = tmp_path / "repo"
    build_output = isolated_root / "build" / "web"
    _write_flutter_build(build_output)
    (build_output / missing_path).unlink()
    default_output = isolated_root / "static-output"
    default_output.mkdir(parents=True)
    marker = default_output / "keep.txt"
    marker.write_text("keep", encoding="utf-8")
    monkeypatch.setattr(staging, "ROOT", isolated_root)
    monkeypatch.setattr(staging, "DEFAULT_OUTPUT", default_output)
    monkeypatch.setenv("VERCEL_ORG_ID", "team_contract_fixture")
    monkeypatch.setenv("VERCEL_PROJECT_ID", "prj_contract_fixture")
    monkeypatch.setattr(
        sys, "argv", ["prepare_flutter_vercel_static_output.py", "--source", str(build_output)]
    )

    with pytest.raises(SystemExit):
        staging.main()

    assert marker.read_text(encoding="utf-8") == "keep"


@pytest.mark.parametrize(
    "source_case",
    [
        "source-root",
        "required-file",
        "nested-file",
        "nested-directory",
    ],
)
def test_flutter_vercel_staging_rejects_source_symlinks_before_deletion(
    tmp_path, monkeypatch, source_case
):
    isolated_root = tmp_path / "repo"
    build_output = isolated_root / "build" / "web"
    source = build_output
    outside = tmp_path / "outside"

    if source_case == "source-root":
        _write_flutter_build(outside)
        build_output.parent.mkdir(parents=True)
        build_output.symlink_to(outside, target_is_directory=True)
        copied_path = Path("index.html")
    else:
        _write_flutter_build(build_output)
        outside.mkdir()
        if source_case == "required-file":
            external_payload = outside / "auth-callback.html"
            external_payload.write_text("outside-required", encoding="utf-8")
            linked_path = build_output / "auth-callback.html"
            linked_path.unlink()
            linked_path.symlink_to(external_payload)
            copied_path = Path("auth-callback.html")
        elif source_case == "nested-file":
            external_payload = outside / "payload.txt"
            external_payload.write_text("outside-file", encoding="utf-8")
            linked_path = build_output / "nested" / "payload.txt"
            linked_path.parent.mkdir()
            linked_path.symlink_to(external_payload)
            copied_path = Path("nested/payload.txt")
        else:
            external_directory = outside / "external-directory"
            external_directory.mkdir()
            (external_directory / "payload.txt").write_text(
                "outside-directory", encoding="utf-8"
            )
            linked_path = build_output / "nested-directory"
            linked_path.symlink_to(external_directory, target_is_directory=True)
            copied_path = Path("nested-directory/payload.txt")

    static_output = isolated_root / "static-output"
    static_output.mkdir(parents=True)
    marker = static_output / "keep.txt"
    marker.write_text("keep", encoding="utf-8")
    monkeypatch.setattr(staging, "ROOT", isolated_root)
    monkeypatch.setattr(staging, "DEFAULT_OUTPUT", static_output)
    monkeypatch.setenv("VERCEL_ORG_ID", "team_contract_fixture")
    monkeypatch.setenv("VERCEL_PROJECT_ID", "prj_contract_fixture")

    with pytest.raises(SystemExit):
        staging.main(["--source", str(source)])

    assert marker.read_text(encoding="utf-8") == "keep"
    assert not (static_output / copied_path).exists()


def test_flutter_vercel_binding_verification_rejects_required_artifact_symlink(
    tmp_path, monkeypatch
):
    isolated_root = tmp_path / "repo"
    build_output = isolated_root / "build" / "web"
    _write_flutter_build(build_output)
    static_output = isolated_root / "static-output"
    monkeypatch.setattr(staging, "ROOT", isolated_root)
    monkeypatch.setattr(staging, "DEFAULT_OUTPUT", static_output)
    monkeypatch.setenv("VERCEL_ORG_ID", "team_contract_fixture")
    monkeypatch.setenv("VERCEL_PROJECT_ID", "prj_contract_fixture")
    assert staging.main(["--source", str(build_output)]) == 0

    external_payload = tmp_path / "outside-auth-callback.html"
    external_payload.write_text("outside-required", encoding="utf-8")
    staged_artifact = static_output / "auth-callback.html"
    staged_artifact.unlink()
    staged_artifact.symlink_to(external_payload)

    with pytest.raises(SystemExit):
        staging.main(["--verify-project-binding"])


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
