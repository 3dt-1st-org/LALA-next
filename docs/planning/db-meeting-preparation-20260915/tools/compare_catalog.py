"""Compare the extracted code inventory with a separately collected catalog JSON.

No network or database connection. CHECK expression equivalence, default expression
equivalence and view/index semantics are deliberately not claimed by this report.
Run: python <this-file> /private/path/to/db-metadata-rds.json
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]


def normalize_type(value):
    value = value.lower().replace(", ", ",")
    return {
        "timestamp with time zone": "timestamptz",
        "int": "integer",
        "int4": "integer",
        "int8": "bigint",
        "bool": "boolean",
    }.get(value, value)


def compare(actual_path):
    code = json.loads((BASE / "assets/schema-code.json").read_text())
    actual = json.loads(actual_path.read_text())
    assert actual["transaction_read_only"] == "on"
    assert actual["user_rows_read"] is False
    relations = {f"{r['schema']}.{r['name']}": r for r in actual["relations"]}
    columns = {(f"{r['schema']}.{r['table']}", r["name"]): r for r in actual["columns"]}
    constraints = {}
    for item in actual["constraints"]:
        constraints.setdefault(f"{item['schema']}.{item['table']}", []).append(item)
    result = {
        "baseline_sha": code["baseline_sha"],
        "server_checkout_sha": actual.get("server_checkout_sha"),
        "checked_at": actual["checked_at"],
        "server_version": actual["server_version"],
        "read_scope": "catalog metadata only; repeatable read/read only; no user rows",
        "code_counts": {
            "tables": len(code["tables"]),
            "columns": sum(len(t["columns"]) for t in code["tables"].values()),
            "views": len(code["views"]),
        },
        "db_counts": dict(Counter(r["kind"] for r in actual["relations"])),
        "extensions": [e for e in actual["extensions"] if e["name"] in code["extensions"]],
        "missing_tables": sorted(set(code["tables"]) - set(relations)),
        "missing_views": sorted(set(code["views"]) - set(relations)),
        "extra_relations": sorted(set(relations) - set(code["tables"]) - set(code["views"])),
        "column_differences": [],
        "extra_columns": [],
        "constraint_differences": [],
        "missing_explicit_indexes": [],
        "table_status": {},
        "matched_column_shape_count": 0,
        "matched_key_signature_count": 0,
        "matched_named_check_presence_count": 0,
        "not_tested": [
            "CHECK/default expression equivalence",
            "view/index full semantics",
            "DDL execution history",
            "roles/RLS/grants",
            "business records",
            "API/Flutter runtime",
            "migration execution",
        ],
    }
    kinds = {"PRIMARY": "p", "UNIQUE": "u", "FOREIGN": "f"}
    delete_actions = {
        "NO ACTION": "a",
        "RESTRICT": "r",
        "CASCADE": "c",
        "SET NULL": "n",
        "SET DEFAULT": "d",
    }
    for table_name, table in code["tables"].items():
        if table_name in result["missing_tables"]:
            result["table_status"][table_name] = "missing"
            continue
        before = len(result["column_differences"]) + len(result["constraint_differences"])
        for col_name, col in table["columns"].items():
            other = columns.get((table_name, col_name))
            if other is None:
                result["column_differences"].append(
                    {"table": table_name, "column": col_name, "difference": "missing"}
                )
            elif (
                normalize_type(col["type"]) != normalize_type(other["type"])
                or col["nullable"] != other["nullable"]
            ):
                result["column_differences"].append(
                    {
                        "table": table_name,
                        "column": col_name,
                        "difference": "type_or_nullable",
                        "code": {k: col[k] for k in ("type", "nullable")},
                        "db": {k: other[k] for k in ("type", "nullable")},
                    }
                )
            else:
                result["matched_column_shape_count"] += 1
        for (tn, cn), col in columns.items():
            if tn == table_name and cn not in table["columns"]:
                result["extra_columns"].append(
                    {
                        "table": tn,
                        "column": cn,
                        "type": col["type"],
                        "nullable": col["nullable"],
                        "default": col["default"],
                    }
                )
        for con in table["constraints"]:
            candidates = constraints.get(table_name, [])
            if con["kind"] == "CHECK":
                assert con["name"], "Unnamed CHECK requires explicit handling"
                found = any(
                    c["name"] == con["name"] and c["type"] == "c" and c["validated"]
                    for c in candidates
                )
                if found:
                    result["matched_named_check_presence_count"] += 1
            else:
                found = any(
                    c["type"] == kinds[con["kind"]]
                    and c["columns"] == con["columns"]
                    and c["validated"]
                    and (
                        con["kind"] != "FOREIGN"
                        or (
                            f"{c['ref_schema']}.{c['ref_table']}" == con["ref_table"]
                            and c["ref_columns"] == con["ref_columns"]
                            and c["on_delete"] == delete_actions[con["on_delete"]]
                        )
                    )
                    for c in candidates
                )
                if found:
                    result["matched_key_signature_count"] += 1
            if not found:
                result["constraint_differences"].append(
                    {
                        "table": table_name,
                        "name": con["name"],
                        "kind": con["kind"],
                        "columns": con["columns"],
                    }
                )
        after = len(result["column_differences"]) + len(result["constraint_differences"])
        result["table_status"][table_name] = (
            "difference" if after != before else "column_and_key_shape_matched"
        )
    actual_indexes = {(r["schema"] + "." + r["table"], r["name"]) for r in actual["indexes"]}
    for index in code["indexes"].values():
        if (index["table"], index["name"]) not in actual_indexes:
            result["missing_explicit_indexes"].append(
                {"table": index["table"], "name": index["name"]}
            )
    (BASE / "assets/schema-db-comparison.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    )
    print(
        json.dumps(
            {k: v for k, v in result.items() if k != "table_status"}, ensure_ascii=False, indent=2
        )
    )


if __name__ == "__main__":
    compare(Path(sys.argv[1]))
