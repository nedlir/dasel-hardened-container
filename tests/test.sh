#!/bin/bash
set -e

IMAGE="dasel:latest-amd64"
HARDENED="--read-only --cap-drop=ALL --security-opt=no-new-privileges"

echo "Loading OCI image..."
docker load < dasel.tar
docker images | grep -q "dasel"

echo "Testing entrypoint and version..."
docker run --rm $HARDENED "$IMAGE" version | grep -q "v3.3.1"

echo "Testing JSON key extraction..."
result=$(echo '{"test": "value"}' | docker run --rm $HARDENED -i "$IMAGE" -i json 'test')
[ "$result" = '"value"' ]

echo "Testing JSON to YAML conversion..."
echo '{"key": "value"}' | docker run --rm $HARDENED -i "$IMAGE" -i json -o yaml --root | grep -q "key: value"

echo "Testing CVE-2026-33320 patch (bounded alias expansion)..."
malicious_yaml='a: &a ["lol","lol","lol","lol","lol","lol","lol","lol","lol"]
b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a]
c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b]
d: &d [*c,*c,*c,*c,*c,*c,*c,*c,*c]
e: &e [*d,*d,*d,*d,*d,*d,*d,*d,*d]
f: &f [*e,*e,*e,*e,*e,*e,*e,*e,*e]
g: &g [*f,*f,*f,*f,*f,*f,*f,*f,*f]
h: &h [*g,*g,*g,*g,*g,*g,*g,*g,*g]
i: &i [*h,*h,*h,*h,*h,*h,*h,*h,*h]'
if echo "$malicious_yaml" | timeout 10 docker run --rm $HARDENED -i "$IMAGE" -i yaml --root 2>&1 | grep -q "expansion budget exceeded"; then
  echo "  CVE patch working: expansion budget limit triggered"
else
  echo "  Warning: CVE patch verification inconclusive"
  exit 1
fi

echo "All tests passed"
