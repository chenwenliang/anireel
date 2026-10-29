#!/usr/bin/env bash
# One step from a clean checkout to bundled style models (macOS or Linux):
# downloads the official AnimeGANv3 Core ML models (sha256-pinned), resizes them to the app's
# portrait sizes and, on macOS, checks Core ML output against the official ONNX model.
# Result: AniReel/Resources/Models/<slot>_<512|384|256>.mlmodel (gitignored); run `xcodegen generate` after.
#
# Everything lives in .model-cache/ (gitignored): a private Python 3.11 fetched by uv and a venv
# with pinned packages. The system Python and the Xcode setup are not touched.
# License: non-commercial use only, see docs/MODELS.md before using the models.
set -euo pipefail
cd "$(dirname "$0")/.."

CACHE=.model-cache
VENV="$CACHE/venv"
export UV_PYTHON_INSTALL_DIR="$PWD/$CACHE/python"
UV="$CACHE/bootstrap/bin/uv"

if [ ! -x "$UV" ]; then
  python3 -m venv "$CACHE/bootstrap"
  "$CACHE/bootstrap/bin/pip" install --quiet "uv==0.4.30"
fi
if [ ! -x "$VENV/bin/python" ]; then
  "$UV" venv --quiet --python 3.11 "$VENV"
fi
VIRTUAL_ENV="$VENV" "$UV" pip install --quiet \
  "coremltools==8.3.0" "numpy==1.26.4" "onnxruntime==1.19.2" "pillow==10.4.0" "certifi==2024.8.30"

# The uv-fetched standalone Python does not see the macOS CA store, so urllib fails with
# CERTIFICATE_VERIFY_FAILED on CI machines. Point OpenSSL at certifi's bundle (verification stays on;
# downloads are additionally sha256-pinned in convert_animegan.py).
SSL_CERT_FILE="$("$VENV/bin/python" -c 'import certifi; print(certifi.where())')"
export SSL_CERT_FILE

"$VENV/bin/python" -I scripts/convert_animegan.py "$@"
