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

    topology = f"{aws}\n{vercel}".lower()
    for term in ("flutter web", "vercel", "fastapi", "ec2", "nginx", "cloudflare", "rds"):
        assert term in topology
    assert "Flutter web" in vercel
    assert "AWS EC2" in vercel
    assert "legacy Vercel API fallback, not the primary API" in vercel


def test_flutter_vercel_static_output_uses_isolated_effective_config(tmp_path, monkeypatch, capsys):
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

    deployment_doc = _text("docs/operations/post-merge-auth-deployment-guide.md")
    assert "python3 scripts/prepare_flutter_vercel_static_output.py" in deployment_doc
    assert "VERCEL_ORG_ID" in deployment_doc
    assert "VERCEL_PROJECT_ID" in deployment_doc
    verify_command = (
        "python3 scripts/prepare_flutter_vercel_static_output.py --verify-project-binding"
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
def test_flutter_vercel_staging_rejects_unsafe_output_without_deleting(tmp_path, output_case):
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
            (external_directory / "payload.txt").write_text("outside-directory", encoding="utf-8")
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
    auth_rollout = _text("docs/operations/post-merge-auth-deployment-guide.md")

    for term in (
        "sql/canonical/005_identity_users.sql",
        "python -m apps.api.app.tools.verify_db_schema --json",
        "identity_schema=configured",
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
        "롤백",
    ):
        assert term in auth_rollout


def test_apple_upstream_revoke_is_an_explicit_live_release_gate_without_fake_fallback():
    auth_rollout = _text("docs/operations/post-merge-auth-deployment-guide.md")

    assert "release gate" in auth_rollout
    assert "live connector integration" in auth_rollout
    assert "provider refresh token" in auth_rollout
    assert "block launch" in auth_rollout
    assert "direct `/auth/revoke` fallback" not in auth_rollout
    assert re.search(r"server\s+fallback is not supported", auth_rollout)


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


def test_post_merge_auth_guide_is_numbered_copy_safe_and_matches_supported_login_scope():
    guide = _text("docs/operations/post-merge-auth-deployment-guide.md")

    assert len(re.findall(r"^## \d+\.", guide, re.MULTILINE)) == 10
    for term in (
        "Google",
        "Apple",
        "Email verification code",
        "Magic Link는 구현하지 않았다",
        "000_extensions_and_schemas.sql",
        "005_identity_users.sql",
        "identity_schema=configured",
        "PREVIOUS_API_SHA",
        "vercel deploy static-output --prod",
        "git switch --detach",
    ):
        assert term in guide

    assert guide.index("000_extensions_and_schemas.sql") < guide.index("005_identity_users.sql")
    assert "export VERCEL_ORG_ID=<" not in guide
    assert "export VERCEL_PROJECT_ID=<" not in guide
    assert "LalaNext2024" not in guide
    assert not re.search(r"postgres(?:ql)?://[^\s<>]+", guide)


def test_aws_deploy_yml_contains_no_literal_account_or_resource_identifiers():
    deploy_yml = _text(".github/workflows/deploy.yml")

    # No literal 12-digit AWS account numbers
    assert not re.search(r"\b\d{12}\b", deploy_yml), (
        "AWS deploy workflow must not contain literal 12-digit account numbers"
    )
    # No literal role ARNs with account numbers
    assert not re.search(r"arn:aws:iam::\d{12}:role/", deploy_yml), (
        "AWS deploy workflow must not contain literal role ARNs"
    )
    # No literal EC2 instance IDs (i-*)
    assert not re.search(r"\bi-[0-9a-f]{17}\b", deploy_yml), (
        "AWS deploy workflow must not contain literal EC2 instance IDs"
    )
    # Must reference GitHub Actions variables
    assert "${{ vars.AWS_DEPLOY_ROLE_ARN }}" in deploy_yml, (
        "AWS deploy workflow must reference AWS_DEPLOY_ROLE_ARN variable"
    )
    assert "${{ vars.AWS_EC2_INSTANCE_ID }}" in deploy_yml, (
        "AWS deploy workflow must reference AWS_EC2_INSTANCE_ID variable"
    )


def test_aws_deploy_yml_installs_systemd_unit_and_enforces_runtime_contract():
    deploy_yml = _text(".github/workflows/deploy.yml")

    # Must install the tracked systemd unit
    assert "infra/systemd/lala-next-api.service" in deploy_yml, (
        "Deploy workflow must install tracked systemd unit"
    )
    assert "/etc/systemd/system/lala-next.service" in deploy_yml, (
        "Deploy workflow must install to system path"
    )
    assert "systemctl daemon-reload" in deploy_yml, "Deploy workflow must run daemon-reload"
    assert "systemctl restart lala-next" in deploy_yml, (
        "Deploy workflow must restart lala-next service"
    )
    assert "systemctl is-active lala-next" in deploy_yml, (
        "Deploy workflow must verify service is active"
    )

    # Must enforce runtime contract in health check
    assert "['runtime_profile']=='api'" in deploy_yml, (
        "Health check must enforce runtime_profile=api"
    )
    assert "['static_snapshot_fallback']=='disabled'" in deploy_yml, (
        "Health check must enforce static_snapshot_fallback=disabled"
    )
    assert "['overall']=='db-backed'" in deploy_yml, "Health check must enforce db-backed mode"


def test_aws_runbook_documents_github_actions_variables_and_runtime_profile():
    aws = _text("docs/operations/aws-deployment-runbook.md")

    # Must document GitHub Actions variables by name
    assert "AWS_DEPLOY_ROLE_ARN" in aws, "AWS runbook must document AWS_DEPLOY_ROLE_ARN variable"
    assert "AWS_EC2_INSTANCE_ID" in aws, "AWS runbook must document AWS_EC2_INSTANCE_ID variable"

    # Must state runtime profile usage
    assert "runtime profile api" in aws or "runtime_profile=api" in aws, (
        "AWS runbook must document api runtime profile"
    )
    assert "Secrets Manager" in aws, "AWS runbook must mention Secrets Manager"

    # Must state that actual values must not be committed
    assert (
        "must not be committed" in aws.lower()
        or "must not appear in" in aws.lower()
        or "실제 값은" in aws
    ), "AWS runbook must state that values must not be committed"


def test_aws_runbook_delegates_secret_management_to_secrets_manager():
    aws = _text("docs/operations/aws-deployment-runbook.md")

    # Should not imply /opt/lala-next/.env is the normal secret source for API runtime
    # The runbook should mention Secrets Manager as the source
    assert "Secrets Manager" in aws or "secretsmanager" in aws.lower(), (
        "AWS runbook should reference Secrets Manager"
    )
    # Check that .env is not positioned as the primary secret source in the configuration table
    config_section = aws[aws.find("## 6. 구성 파일 위치") : aws.find("## 7. 보안 주의사항")]
    env_lines = [line for line in config_section.split("\n") if ".env" in line.lower()]
    if env_lines:
        # Ensure .env mentions in config table are about configuration, not secrets
        for line in env_lines:
            assert "password" not in line.lower(), (
                f"Config table .env line must not mention passwords: {line}"
            )
            # Allow "비밀이 아닌" (not secret) as it explicitly denies .env contains secrets
            if "비밀" in line:
                assert "아닌" in line, (
                    f"Config table .env line with '비밀' must explicitly deny it (include '아닌'): {line}"
                )
