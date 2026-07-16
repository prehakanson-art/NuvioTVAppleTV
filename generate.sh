#!/bin/bash
# Regenerate the Xcode project.
#
# USE THIS INSTEAD OF a bare `xcodegen generate`.
#
# Why: KSPlayer is a vendored LOCAL Swift package (Vendor/KSPlayer, see
# project.yml). XcodeGen 2.45.4 has a bug where it does NOT emit the
# `package = <ref>` link on the XCSwiftPackageProductDependency for a local
# package. `xcodebuild` tolerates that, but the Xcode GUI shows
# "Missing package product 'KSPlayer'" and refuses to build (e.g. to a real
# Apple TV). This wrapper regenerates, then patches that link back in.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate

python3 - <<'PY'
import re, sys
path = "NuvioTV.xcodeproj/project.pbxproj"
src = open(path).read()

m = re.search(r'([0-9A-F]{24}) /\* XCLocalSwiftPackageReference "Vendor/KSPlayer" \*/', src)
if not m:
    sys.exit("generate.sh: could not find the local KSPlayer package reference")
uuid = m.group(1)

# The KSPlayer product dependency block; add the package link if it's missing.
def patch(match):
    block = match.group(0)
    if "package =" in block:
        return block
    return block.replace(
        "isa = XCSwiftPackageProductDependency;",
        'isa = XCSwiftPackageProductDependency;\n\t\t\tpackage = %s /* XCLocalSwiftPackageReference "Vendor/KSPlayer" */;' % uuid,
        1,
    )

patched = re.sub(r'\{[^{}]*?productName = KSPlayer;[^{}]*?\}', patch, src)
if patched != src:
    open(path, "w").write(patched)
    print("generate.sh: linked KSPlayer product to the local package")
else:
    print("generate.sh: KSPlayer product link already present")
PY
