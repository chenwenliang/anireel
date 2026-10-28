#!/usr/bin/env python3
"""Convert AnimeGANv3 generators into the fixed-size Core ML models AniReel loads.

For each ladder side S (512, 384, 256) this writes
AniReel/Resources/Models/<name>_<S>.mlmodel: a portrait W x H model (same pixel count as S x S,
multiples of 8) with an RGB image input and an RGB image output named "stylized".
The app picks the largest bundled side at or below the device tier (DeviceTier, docs/DECISIONS.md D1)
and steps down at runtime; see InferenceGovernor.swift, whose frameSize() this file mirrors.

Source format: the TF frozen graph (.pb) from the official release, converted the way upstream's
deploy/pb_to_coreml.py does. The ONNX export is not used: coremltools has no ONNX frontend since 6.0,
and the ONNX graph relies on opset-9 Upsample with runtime-computed sizes.

Setup (Python 3.10, macOS or Linux; the smoke test runs only on macOS):
    python3.10 -m venv .venv && . .venv/bin/activate
    pip install "coremltools==7.2" "tensorflow==2.12.*" "numpy<2" pillow   # Apple silicon: tensorflow-macos==2.12.*

Usage:
    python scripts/convert_animegan.py                         # download + convert animegan_hayao
    python scripts/convert_animegan.py --pb my.pb --name animegan_chibi

Model binaries are gitignored. Read docs/MODELS.md for the license before shipping any model.
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
INPUT_TENSOR = "AnimeGANv3_input"
OUTPUT_IMAGE = "stylized"

RELEASE = "https://github.com/TachibanaYoshino/AnimeGANv3/releases/download/v1.1.0/"
KNOWN_SOURCES = {
    "animegan_hayao": ("AnimeGANv3_Hayao_36.pb", "58bc25bfeec1375047fb8f1d672a1ba6a7a93c266a3769a86c248374f986cf13"),
}


def frame_size(side):
    def round_to_8(value):
        return int(round(value / 8)) * 8
    return round_to_8(side * 0.75), round_to_8(side * 4 / 3)


def fetch(name):
    filename, sha256 = KNOWN_SOURCES[name]
    path = CACHE_DIR / filename
    if not path.exists():
        CACHE_DIR.mkdir(exist_ok=True)
        print(f"downloading {RELEASE + filename}")
        urllib.request.urlretrieve(RELEASE + filename, path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != sha256:
        sys.exit(f"{path}: sha256 {digest} does not match pinned {sha256}")
    return path


def convert(pb, side, out_path):
    import coremltools as ct
    from coremltools.models.neural_network import NeuralNetworkBuilder, quantization_utils
    from coremltools.proto import FeatureTypes_pb2 as ft

    width, height = frame_size(side)
    converted = ct.convert(
        str(pb),
        source="tensorflow",
        convert_to="neuralnetwork",
        inputs=[ct.ImageType(name=INPUT_TENSOR, shape=(1, height, width, 3), channel_first=False,
                             scale=2.0 / 255.0, bias=[-1.0, -1.0, -1.0])],
    )
    spec = converted.get_spec()
    raw_output = spec.description.output[0].name

    # Generator emits NHWC in [-1, 1]; Core ML image outputs need CHW in [0, 255].
    builder = NeuralNetworkBuilder(spec=spec)
    builder.add_permute(name="to_chw", dim=[0, 3, 1, 2], input_name=raw_output, output_name="chw")
    builder.add_squeeze(name="drop_batch", input_name="chw", output_name="chw_image", squeeze_all=True)
    builder.add_activation(name="to_pixels", non_linearity="LINEAR", input_name="chw_image",
                           output_name=OUTPUT_IMAGE, params=[127.5, 127.5])
    del spec.description.output[:]
    output = spec.description.output.add()
    output.name = OUTPUT_IMAGE
    output.type.imageType.colorSpace = ft.ImageFeatureType.ColorSpace.Value("RGB")
    output.type.imageType.width = width
    output.type.imageType.height = height

    spec.description.metadata.author = "AnimeGANv3, Xin Chen (github.com/TachibanaYoshino/AnimeGANv3)"
    spec.description.metadata.license = "Non-commercial use only unless authorized by the AnimeGANv3 author"
    spec.description.metadata.shortDescription = f"AniReel style model, {width}x{height}"

    half = quantization_utils.quantize_weights(ct.models.MLModel(spec, skip_model_load=True), nbits=16)
    if isinstance(half, ct.models.MLModel):
        half.save(str(out_path))
    else:
        ct.utils.save_spec(half, str(out_path))
    print(f"wrote {out_path.relative_to(REPO)} ({width}x{height})")


def smoke_test(path, side):
    import coremltools as ct
    from PIL import Image

    width, height = frame_size(side)
    result = ct.models.MLModel(str(path)).predict({INPUT_TENSOR: Image.new("RGB", (width, height), (120, 160, 90))})
    image = result[OUTPUT_IMAGE]
    if image.size != (width, height):
        sys.exit(f"{path}: output {image.size}, expected {(width, height)}")
    print(f"smoke test ok: {path.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--name", default="animegan_hayao", help="model slot name, e.g. animegan_hayao or animegan_chibi")
    parser.add_argument("--pb", type=pathlib.Path, help="local AnimeGANv3 frozen graph; required for slots without a known source")
    args = parser.parse_args()

    if args.pb is None and args.name not in KNOWN_SOURCES:
        sys.exit(f"no public source for {args.name}; pass --pb (see docs/MODELS.md)")
    pb = args.pb or fetch(args.name)

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    for side in LADDER:
        out_path = MODELS_DIR / f"{args.name}_{side}.mlmodel"
        convert(pb, side, out_path)
        if sys.platform == "darwin":
            smoke_test(out_path, side)


if __name__ == "__main__":
    main()
