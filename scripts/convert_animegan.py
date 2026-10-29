#!/usr/bin/env python3
"""Build the fixed-size Core ML models AniReel loads from the official AnimeGANv3 Core ML release.

For each slot and ladder side S (512, 384, 256) this writes
AniReel/Resources/Models/<slot>_<S>.mlmodel: a portrait W x H model (same pixel count as S x S,
multiples of 8) with an RGB image input and an RGB image output.
The app picks the largest bundled side at or below the device tier (DeviceTier, docs/DECISIONS.md D1)
and steps down at runtime; see InferenceGovernor.swift, whose frameSize() this file mirrors.

Source: the official .mlmodel files of release v1.1.0 (fixed 512x512, fp32, neuralnetwork format).
The network is fully convolutional; the only size-dependent fields in the spec are the image
input/output sizes, one attention reshape (H/8 x W/8) and three bilinear resize targets
(H/4, H/2, H). Only those fields are rewritten: weights, layers and preprocessing are untouched.

Check: the official ONNX of the same release (dynamic H/W) is the reference. On macOS every
generated model is run through Core ML on official sample photos and compared with ONNX Runtime
at the same size; the script fails if the CPU result differs by more than MAX_MEAN_ABS_DIFF.
Elsewhere Core ML cannot run, so the comparison is skipped (docs/COREML_RESULTS.md records the
Linux check made with a NumPy executor of the spec).

Run it through scripts/fetch_models.sh, which creates the pinned, isolated environment.
Model binaries are gitignored. Read docs/MODELS.md for the license before using any model.
"""

import argparse
import hashlib
import pathlib
import sys
import urllib.request

REPO = pathlib.Path(__file__).resolve().parent.parent
MODELS_DIR = REPO / "AniReel" / "Resources" / "Models"
CACHE_DIR = REPO / ".model-cache"

LADDER = (512, 384, 256)
SOURCE_SIDE = 512
MAX_MEAN_ABS_DIFF = 1.0  # 0-255 pixel units, Core ML CPU vs ONNX Runtime

RELEASE = "https://github.com/TachibanaYoshino/AnimeGANv3/releases/download/v1.1.0/"
SAMPLES = "https://raw.githubusercontent.com/TachibanaYoshino/AnimeGANv3/master/inputs/imgs/"

# slot -> (official .mlmodel, sha256, official .onnx, sha256); hashes checked 2026-10-29.
SOURCES = {
    "animegan_hayao": (
        "AnimeGANv3_Hayao_36.mlmodel", "8012cd99b42cc261fd49f491c6c260a1ebdd9502c4694b19a608bc3401cc77b5",
        "AnimeGANv3_Hayao_36.onnx", "95ba7b219073fd5b12f569bc38056ffd3019cf4caf15b1feb9f73d1286c9f69d",
    ),
    "animegan_shinkai": (
        "AnimeGANv3_Shinkai_37.mlmodel", "7ce2c3aed36c045e5eb6f04336900106edce490355301b15666aa99d54b30d8d",
        "AnimeGANv3_Shinkai_37.onnx", "8dc4d789c44db472447806583c56809e155280225b991bd79f9e2cb20793dcb9",
    ),
}
SAMPLE_PHOTOS = {
    "v3_20.jpg": "ab78c175874747322b0f8fc92ab352f7b42d739264b91efe21d056fa6e61191c",
    "v3_7.jpg": "6edb2d527f8f0b21dc04f265405ab231713a5e0f60b74ed66c8bc876833a0647",
}
# Every layer kind in the official specs. Anything else could carry a size and must be reviewed.
KNOWN_LAYERS = {
    "add", "transpose", "pooling", "unary", "activation", "convolution", "padding", "divideBroadcastable",
    "multiply", "squeeze", "resizeBilinear", "reshapeStatic", "expandDims", "softmaxND", "reduceSum", "permute",
}


def frame_size(side):
    def round_to_8(value):
        return int(round(value / 8)) * 8
    return round_to_8(side * 0.75), round_to_8(side * 4 / 3)


def fetch(url, filename, sha256):
    path = CACHE_DIR / filename
    if not path.exists():
        CACHE_DIR.mkdir(exist_ok=True)
        print(f"downloading {url}")
        urllib.request.urlretrieve(url, path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != sha256:
        path.unlink()
        sys.exit(f"{filename}: sha256 {digest} does not match pinned {sha256}")
    return path


def reshape(spec, width, height):
    """Rewrites the size-dependent fields of a 512x512 official spec for width x height."""
    for feature in (spec.description.input[0], spec.description.output[0]):
        feature.type.imageType.width = width
        feature.type.imageType.height = height
    reshapes = resizes = 0
    for layer in spec.neuralNetwork.layers:
        kind = layer.WhichOneof("layer")
        if kind not in KNOWN_LAYERS:
            sys.exit(f"unexpected layer {layer.name} ({kind}); review it for fixed sizes")
        if kind == "resizeBilinear":
            target = layer.resizeBilinear.targetSize
            scale = target[0] / SOURCE_SIDE
            if target[0] != target[1] or scale not in (0.25, 0.5, 1.0):
                sys.exit(f"unexpected resize target {list(target)} in {layer.name}")
            target[:] = [int(height * scale), int(width * scale)]
            resizes += 1
        elif kind == "reshapeStatic" and list(layer.reshapeStatic.targetShape)[1:3] == [SOURCE_SIDE // 8] * 2:
            layer.reshapeStatic.targetShape[1:3] = [height // 8, width // 8]
            reshapes += 1
    if (reshapes, resizes) != (1, 3):
        sys.exit(f"expected 1 attention reshape and 3 resizes, found {reshapes} and {resizes}")


def build(slot, side):
    import coremltools as ct

    mlmodel_name, mlmodel_sha, _, _ = SOURCES[slot]
    source = fetch(RELEASE + mlmodel_name, mlmodel_name, mlmodel_sha)
    width, height = frame_size(side)
    spec = ct.utils.load_spec(str(source))
    reshape(spec, width, height)
    metadata = spec.description.metadata
    metadata.shortDescription = f"{mlmodel_name} (AnimeGANv3 v1.1.0), input and output resized to {width}x{height}"
    metadata.license = ("AnimeGANv3 license: free for non-commercial purposes; commercial use needs "
                        "the author's authorization letter. github.com/TachibanaYoshino/AnimeGANv3")
    out_path = MODELS_DIR / f"{slot}_{side}.mlmodel"
    ct.utils.save_spec(spec, str(out_path))
    print(f"wrote {out_path.relative_to(REPO)} ({width}x{height})")
    return out_path


def compare(slot, side, path):
    """Core ML (CPU, then all units) vs ONNX Runtime on official sample photos at the model size."""
    import coremltools as ct
    import numpy as np
    import onnxruntime as ort
    from PIL import Image

    _, _, onnx_name, onnx_sha = SOURCES[slot]
    session = ort.InferenceSession(str(fetch(RELEASE + onnx_name, onnx_name, onnx_sha)))
    width, height = frame_size(side)
    models = {units: ct.models.MLModel(str(path), compute_units=getattr(ct.ComputeUnit, units))
              for units in ("CPU_ONLY", "ALL")}
    for photo, sha in SAMPLE_PHOTOS.items():
        image = Image.open(fetch(SAMPLES + photo, photo, sha)).convert("RGB").resize((width, height), Image.BICUBIC)
        pixels = np.asarray(image, dtype=np.float32)
        reference = session.run(None, {"AnimeGANv3_input:0": (pixels / 127.5 - 1)[None]})[0][0] * 127.5 + 127.5
        reference = np.clip(reference, 0, 255)
        for units, model in models.items():
            output = model.predict({"AnimeGANv3_input": image})["image"]
            diff = np.abs(np.asarray(output.convert("RGB"), dtype=np.float32) - reference)
            print(f"  {path.name} {photo} {units}: mean abs diff {diff.mean():.3f}, max {diff.max():.0f} (0-255)")
            if units == "CPU_ONLY" and diff.mean() > MAX_MEAN_ABS_DIFF:
                sys.exit(f"{path.name}: Core ML output differs from the official ONNX model; do not ship it")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("slots", nargs="*", default=list(SOURCES), help=f"slots to build, default: {' '.join(SOURCES)}")
    args = parser.parse_args()

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    for slot in args.slots:
        if slot not in SOURCES:
            sys.exit(f"no official source for {slot} (see docs/MODELS.md)")
        for side in LADDER:
            path = build(slot, side)
            if sys.platform == "darwin":
                compare(slot, side, path)
    if sys.platform != "darwin":
        print("not macOS: Core ML cannot run here, the Core ML vs ONNX comparison was skipped")


if __name__ == "__main__":
    main()
