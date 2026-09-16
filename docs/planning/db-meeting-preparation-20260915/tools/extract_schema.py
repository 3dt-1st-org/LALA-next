"""Extract canonical DDL without connecting to or modifying a database.

Run: uv run --no-project --with pglast==8.4 python <this-file>
Only the SQL constructs present at the recorded baseline are supported.
Unrecognized statements fail rather than silently disappearing from the inventory.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

from pglast import ast, parse_sql
from pglast.stream import RawStream

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parents[1] / "assets" / "schema-code.json"
BASELINE = "765570a21ff5ab5207c627d3659e8051be6dbd98"


def render(node):
    return RawStream()(node) if node is not None else None


def names(items):
    return [item.sval for item in items or ()]


def relation(node):
    return f"{node.schemaname}.{node.relname}"


def extract():
    tables, views, indexes, schemas, extensions, sources = {}, {}, {}, [], [], []
    source = {}

    def constraint(table, node, column=None):
        kind = node.contype.name.removeprefix("CONSTR_")
        cols = names(node.fk_attrs if kind == "FOREIGN" else node.keys)
        if not cols and column:
            cols = [column]
        result = {
            "name": node.conname,
            "kind": kind,
            "columns": cols,
            "definition": render(node),
            "source": source.copy(),
        }
        if kind == "FOREIGN":
            result.update(
                ref_table=relation(node.pktable),
                ref_columns=names(node.pk_attrs),
                on_delete={
                    "a": "NO ACTION",
                    "r": "RESTRICT",
                    "c": "CASCADE",
                    "n": "SET NULL",
                    "d": "SET DEFAULT",
                }[node.fk_del_action],
            )
        table["constraints"].append(result)

    def column(table, node):
        if node.colname in table["columns"]:
            assert table["columns"][node.colname]["type"] == render(node.typeName)
            return
        result = {
            "name": node.colname,
            "type": render(node.typeName),
            "nullable": True,
            "default": None,
            "source": source.copy(),
        }
        table["columns"][node.colname] = result
        for con in node.constraints or ():
            kind = con.contype.name
            if kind == "CONSTR_NOTNULL":
                result["nullable"] = False
            elif kind == "CONSTR_DEFAULT":
                result["default"] = render(con.raw_expr)
            else:
                constraint(table, con, node.colname)

    for path in sorted((ROOT / "sql/canonical").glob("*.sql")):
        raw = path.read_bytes()
        relative = path.relative_to(ROOT).as_posix()
        tracked = subprocess.check_output(["git", "show", f"{BASELINE}:{relative}"], cwd=ROOT)
        assert raw == tracked, f"Source differs from fixed baseline: {relative}"
        sources.append({"path": relative, "sha256": hashlib.sha256(raw).hexdigest()})
        for statement in parse_sql(raw.decode()):
            node = statement.stmt
            location = getattr(getattr(node, "relation", None), "location", None)
            if location is None or location < 0:
                location = statement.stmt_location
            source = {"path": relative, "line": raw[:location].count(b"\n") + 1}
            if isinstance(node, ast.CreateSchemaStmt):
                schemas.append(node.schemaname)
            elif isinstance(node, ast.CreateExtensionStmt):
                extensions.append(node.extname)
            elif isinstance(node, ast.CreateStmt):
                name = relation(node.relation)
                assert name not in tables
                table = tables[name] = {
                    "name": name,
                    "columns": {},
                    "constraints": [],
                    "source": source.copy(),
                }
                for item in node.tableElts or ():
                    if isinstance(item, ast.ColumnDef):
                        column(table, item)
                    elif isinstance(item, ast.Constraint):
                        constraint(table, item)
                    else:
                        raise ValueError(f"Unsupported table element {type(item).__name__}")
            elif isinstance(node, ast.AlterTableStmt):
                table = tables[relation(node.relation)]
                for cmd in node.cmds:
                    if cmd.subtype.name == "AT_AddColumn":
                        column(table, cmd.def_)
                    elif cmd.subtype.name == "AT_DropConstraint":
                        table["constraints"] = [
                            c for c in table["constraints"] if c["name"] != cmd.name
                        ]
                    elif cmd.subtype.name == "AT_AddConstraint":
                        constraint(table, cmd.def_)
                    else:
                        raise ValueError(f"Unsupported ALTER {cmd.subtype.name}")
            elif isinstance(node, ast.IndexStmt):
                indexes[node.idxname] = {
                    "name": node.idxname,
                    "table": relation(node.relation),
                    "unique": node.unique,
                    "definition": render(node),
                    "source": source.copy(),
                }
            elif isinstance(node, ast.ViewStmt):
                name = relation(node.view)
                views[name] = {"name": name, "definition": render(node), "source": source.copy()}
            else:
                raise ValueError(f"Unsupported SQL statement {type(node).__name__}")

    for table in tables.values():
        for con in table["constraints"]:
            if con["kind"] == "PRIMARY":
                for key in con["columns"]:
                    table["columns"][key]["nullable"] = False
            if con["kind"] == "FOREIGN":
                assert con["ref_table"] in tables
                assert all(key in tables[con["ref_table"]]["columns"] for key in con["ref_columns"])
    result = {
        "baseline_sha": BASELINE,
        "scope": "static cumulative canonical SQL; not evidence of DB application",
        "schemas": schemas,
        "extensions": extensions,
        "sources": sources,
        "tables": tables,
        "views": views,
        "indexes": indexes,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(
        json.dumps(
            {
                "sql_files": len(sources),
                "schemas": len(schemas),
                "tables": len(tables),
                "columns": sum(len(t["columns"]) for t in tables.values()),
                "foreign_keys": sum(
                    c["kind"] == "FOREIGN" for t in tables.values() for c in t["constraints"]
                ),
                "views": len(views),
                "explicit_indexes": len(indexes),
            }
        )
    )


if __name__ == "__main__":
    extract()
