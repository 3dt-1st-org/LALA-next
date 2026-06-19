# Terraform Decisions

## 2026-06-20

- Adopt the ONMU-style Terraform directory structure, but keep LALA naming and
  rollout assumptions aligned with the current Azure dev runtime.
- Treat Bicep, Portal export, and `aztfexport` output as comparison and
  rollback references only, not as the long-term source of truth.
- Keep dev as the first-class apply target. `prod` remains a documented
  skeleton until separate hardening and approval gates exist.
- Do not commit live Azure identifiers or secret values. GitHub environment
  vars and secrets feed CI, and CI writes bootstrap runtime secrets into Key
  Vault after Terraform finishes provisioning.
- Preserve the current PostgreSQL + Key Vault + reviewed ingest/RAG path as the
  normal runtime. The bundled snapshot remains a limited read-only fallback for
  DB outage handling only.
