#!/usr/bin/env bash
# Assembles assets/map/open-map-embed.html from the committed template plus a
# version-pinned MapLibre GL JS runtime. The runtime is verified against
# pinned SHA-256 hashes so the bundled embed is reproducible; nothing is ever
# fetched from an unpinned "latest" URL.
#
# Usage (from anywhere):
#   apps/flutter_app/tool/build_open_map_embed.sh
#
# Optional: LALA_MAPLIBRE_DIST_DIR=/path/with/{maplibre-gl.js,maplibre-gl.css}
# reuses already-downloaded dist files (hashes are still verified).
set -euo pipefail

VERSION="3.6.2"
# Public upstream dist checksums (integrity pins, not credentials).
JS_SHA256="c46084df69bbaa995b301a515274a86ec53905c78459b80dccbc27a0c0b8d13b"   # pragma: allowlist secret
CSS_SHA256="731181d400d65a8b09d842f55b70bc4dc11010b15b8549e2c65a69d233fbdd2e" # pragma: allowlist secret
BASE_URL="https://unpkg.com/maplibre-gl@${VERSION}/dist"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${APP_DIR}/assets/map/open-map-embed.template.html"
OUTPUT="${APP_DIR}/assets/map/open-map-embed.html"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if [[ -n "${LALA_MAPLIBRE_DIST_DIR:-}" && -f "${LALA_MAPLIBRE_DIST_DIR}/maplibre-gl.js" && -f "${LALA_MAPLIBRE_DIST_DIR}/maplibre-gl.css" ]]; then
  cp "${LALA_MAPLIBRE_DIST_DIR}/maplibre-gl.js" "${WORK_DIR}/"
  cp "${LALA_MAPLIBRE_DIST_DIR}/maplibre-gl.css" "${WORK_DIR}/"
else
  curl -sSL --fail --max-time 120 -o "${WORK_DIR}/maplibre-gl.js" "${BASE_URL}/maplibre-gl.js"
  curl -sSL --fail --max-time 60 -o "${WORK_DIR}/maplibre-gl.css" "${BASE_URL}/maplibre-gl.css"
fi

verify_hash() {
  local file="$1" expected="$2"
  local actual
  actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERROR: SHA-256 mismatch for ${file}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
}

verify_hash "${WORK_DIR}/maplibre-gl.js" "${JS_SHA256}"
verify_hash "${WORK_DIR}/maplibre-gl.css" "${CSS_SHA256}"

python3 - "${TEMPLATE}" "${OUTPUT}" "${WORK_DIR}" "${VERSION}" "${JS_SHA256}" "${CSS_SHA256}" <<'PY'
import pathlib
import re
import sys

template_path, output_path, work_dir, version, js_sha, css_sha = sys.argv[1:7]

template = pathlib.Path(template_path).read_text(encoding="utf-8")
js = pathlib.Path(work_dir, "maplibre-gl.js").read_text(encoding="utf-8")
css = pathlib.Path(work_dir, "maplibre-gl.css").read_text(encoding="utf-8")

# Drop sourcemap pointers: they would 404 from the bundled asset.
js = re.sub(r"^//# sourceMappingURL=.*$\n?", "", js, flags=re.M)
css = re.sub(r"^/\*# sourceMappingURL=.*$\n?", "", css, flags=re.M)

# Safety: the runtime must not contain HTML parser-breaking tokens.
for token in ("</script", "<!--", "</style"):
    if token in js:
        sys.exit(f"ERROR: runtime JS contains {token!r}; refusing to inline")
if "</style" in css:
    sys.exit("ERROR: runtime CSS contains '</style>'; refusing to inline")

js_block = (
    f"/* MapLibre GL JS v{version} — BSD-3-Clause.\n"
    f" * Source: https://unpkg.com/maplibre-gl@{version}/dist/maplibre-gl.js\n"
    f" * SHA-256: {js_sha}\n"
    f" * License: https://github.com/maplibre/maplibre-gl-js/blob/v{version}/LICENSE.txt\n"
    f" */\n" + js
)
css_block = (
    f"/* MapLibre GL JS v{version} stylesheet — BSD-3-Clause.\n"
    f" * Source: https://unpkg.com/maplibre-gl@{version}/dist/maplibre-gl.css\n"
    f" * SHA-256: {css_sha}\n"
    f" */\n" + css
)

for marker in ("__MAPLIBRE_GL_JS__", "__MAPLIBRE_GL_CSS__"):
    if marker not in template:
        sys.exit(f"ERROR: template is missing the {marker} placeholder")

assembled = template.replace("__MAPLIBRE_GL_JS__", js_block, 1)
assembled = assembled.replace("__MAPLIBRE_GL_CSS__", css_block, 1)
assembled = assembled.replace("__MAPLIBRE_GL_VERSION__", f"v{version} (pinned)", 1)

if "__MAPLIBRE_GL_" in assembled:
    sys.exit("ERROR: unresolved placeholder remains in assembled embed")

pathlib.Path(output_path).write_text(assembled, encoding="utf-8", newline="\n")
print(f"wrote {output_path} ({len(assembled)} bytes)")
PY
