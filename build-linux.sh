#!/bin/sh
# Builds the Linux version of the Serious Sam TEX Converter and packs it for a GitHub Release.
#
# Usage (in the folder with TexConverter.pb):
#   sh build-linux.sh
#
# Needs PureBasic for Linux. Set PUREBASIC_HOME to the PureBasic folder (for example ~/purebasic),
# or make sure "pbcompiler" can be found in your PATH.

VERSION="1.00"
NAME="SS-TexConverter-$VERSION-Linux"

if [ -n "$PUREBASIC_HOME" ] && [ -x "$PUREBASIC_HOME/compilers/pbcompiler" ]; then
  PBC="$PUREBASIC_HOME/compilers/pbcompiler"
elif command -v pbcompiler >/dev/null 2>&1; then
  PBC="pbcompiler"
else
  echo "pbcompiler not found. Set PUREBASIC_HOME, for example:"
  echo "  export PUREBASIC_HOME=~/purebasic"
  exit 1
fi

rm -rf "Release/$NAME"
mkdir -p "Release/$NAME"

echo "Compiling with $PBC ..."
"$PBC" -e "Release/$NAME/SS1TexConverter2" TexConverter.pb || { echo "Compiling failed."; exit 1; }

cp -r Help "Release/$NAME/"
cp README.md LICENSE "Release/$NAME/"
chmod +x "Release/$NAME/SS1TexConverter2"

# tar.gz keeps the "executable" permission, a zip file does not
cd Release && tar -czf "$NAME.tar.gz" "$NAME" && cd ..
echo "Done: Release/$NAME.tar.gz"
