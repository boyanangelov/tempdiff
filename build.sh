#!/bin/sh
set -e
cd "$(dirname "$0")"
rm -rf WeatherDiff.app
mkdir -p WeatherDiff.app/Contents/MacOS
cp Info.plist WeatherDiff.app/Contents/
swiftc -O -swift-version 5 -o WeatherDiff.app/Contents/MacOS/WeatherDiff main.swift
codesign -s - --force WeatherDiff.app
