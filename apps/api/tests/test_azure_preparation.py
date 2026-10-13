from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

from scripts.production_deploy_gate import should_deploy
from scripts.validate_azure_rollout import validate

ROOT = Path(__file__).resolve().parents[3]
SHA = "a" * 40
REPOSITORY = "example/lala"


def successful_ci():
    return {
        "workflow_run": {
            "conclusion": "success",
            "event": "push",
            "head_branch": "main",
            "head_repository": {"full_name": REPOSITORY},
            "head_sha": SHA,
            "head_commit": {"id": SHA, "message": "fix(api): reviewed release"},
        }
    }


def test_normal_successful_current_main_can_deploy():
    assert should_deploy(successful_ci(), repository=REPOSITORY, current_main_sha=SHA)


@pytest.mark.parametrize(
    "patch",
    [
        {"conclusion": "failure"},
        {"conclusion": "cancelled"},
        {"event": "pull_request"},
        {"head_branch": "dev"},
        {"head_repository": {"full_name": "fork/lala"}},
        {"head_sha": "b" * 40},
        {"head_commit": {"id": "b" * 40, "message": "mismatch"}},
        {"head_commit": None},
        {"head_commit": {"id": SHA, "message": ""}},
        {"head_commit": {"id": SHA, "message": "chore: preparation [skip deploy]"}},
        {"head_commit": {"id": SHA, "message": "chore: prepare\n\n[SKIP DEPLOY]"}},
    ],
)
def test_production_deploy_gate_denies_non_release_events(patch):
    event = copy.deepcopy(successful_ci())
    event["workflow_run"].update(patch)
    assert not should_deploy(event, repository=REPOSITORY, current_main_sha=SHA)


def test_deploy_gate_cli_fails_closed_for_bad_payload(tmp_path):
    event_file = tmp_path / "event.json"
    event_file.write_text("invalid JSON with private provider data")
    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/production_deploy_gate.py"),
            "--event-file",
            str(event_file),
            "--repository",
            REPOSITORY,
            "--main-sha",
            SHA,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout.strip() == "deploy=false"
    assert result.stderr == ""


def rollout_env():
    return {
        "AZURE_MANAGED_INFRA_READY": "true",
        "ROLLOUT_TARGET": "staging",
        "SOURCE_SHA": SHA,
        "AZURE_RESOURCE_GROUP": "fixture-group",
        "AZURE_CONTAINER_APP_NAME": "fixture-app",
        "AZURE_REGISTRY_NAME": "fixtureregistry",
    }


def test_staging_inputs_and_production_promotion():
    env = rollout_env()
    validate(env)
    env.update(
        ROLLOUT_TARGET="prod",
        AZURE_STAGING_VERIFIED_SHA=SHA,
        AZURE_STAGING_VERIFIED_IMAGE="fixture.azurecr.io/lala-api@sha256:" + "b" * 64,
        AZURE_STAGING_REGISTRY_ID="/subscriptions/"
        + "0" * 36
        + "/resourceGroups/fixture/providers/Microsoft.ContainerRegistry/registries/fixture",
    )
    validate(env)
    env["AZURE_STAGING_VERIFIED_SHA"] = "c" * 40
    with pytest.raises(ValueError, match="does not match"):
        validate(env)


@pytest.mark.parametrize(
    "patch",
    [
        {"AZURE_MANAGED_INFRA_READY": "false"},
        {"SOURCE_SHA": "main"},
        {"SOURCE_SHA": "a" * 39},
        {"ROLLOUT_TARGET": "dev"},
        {"ROLLOUT_TARGET": "prod"},
        {"AZURE_REGISTRY_NAME": "invalid\nprivate-value"},
        {"AZURE_CONTAINER_APP_NAME": ""},
    ],
)
def test_unprepared_rollout_is_rejected_without_echoing_values(patch):
    with pytest.raises(ValueError) as exc:
        validate(rollout_env() | patch)
    assert "private-value" not in str(exc.value)


def test_workflow_wiring_has_no_automatic_azure_or_unguarded_production_lane():
    # Inspect the wiring as well as executing the actual gate above: a correct
    # function is useless if a deployment job can bypass it.
    def workflow(name):
        return yaml.safe_load((ROOT / ".github/workflows" / name).read_text())

    for name in ("deploy.yml", "deploy-flutter-web.yml"):
        config = workflow(name)
        job = config["jobs"]["deploy"]
        assert job["needs"] == "gate"
        assert "needs.gate.outputs.deploy == 'true'" in job["if"]
        gate = config["jobs"]["gate"]
        assert gate["permissions"] == {"contents": "read"}
        assert any("production_deploy_gate.py" in step.get("run", "") for step in gate["steps"])

    for name in ("azure-dev-deploy.yml", "azure-managed-rollout-candidate.yml"):
        config = workflow(name)
        triggers = config.get("on", config.get(True))  # YAML 1.1 treats 'on' as boolean.
        assert set(triggers) == {"workflow_dispatch"}
    legacy = workflow("azure-dev-deploy.yml")
    assert legacy["permissions"] == {"contents": "read"}
    assert all("uses" not in step for step in legacy["jobs"]["retired"]["steps"])
    managed = workflow("azure-managed-rollout-candidate.yml")["jobs"]["rollout"]
    steps = managed["steps"]
    login_index = next(i for i, step in enumerate(steps) if step.get("uses") == "azure/login@v2")
    before_login = json.dumps(steps[:login_index])
    assert 'test \\"$AZURE_MANAGED_INFRA_READY\\" = true' in before_login
    assert "validate_azure_rollout.py" in before_login
    assert "--frozen" in before_login
    assert "secrets." not in before_login
    assert "az deployment" not in json.dumps(managed)
    assert "az group create" not in json.dumps(managed)
