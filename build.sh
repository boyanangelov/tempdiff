#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=TempDiff.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/"
swiftc -O -swift-version 5 -target arm64-apple-macos13 -o "$APP/Contents/MacOS/TempDiff" main.swift
codesign -s - --force "$APP"
echo "Built $APP: run with open $APP"
