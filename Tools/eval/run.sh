#!/bin/zsh
# Builds the macOS eval harness from the app's own analysis sources and runs it.
#   Tools/eval/run.sh --corpus build/corpus [--pass fast|deep|both] [--export out.json] [--filter receipts]
#   Tools/eval/run.sh --db snap.sqlite [--out rescore.jsonl]   # re-score a real library's stored features
set -euo pipefail
root=${0:A:h:h:h}
app=$root/ScreenshotSorter
out=$root/build/eval
mkdir -p $out
sources=(
  $app/Models/ScreenshotCategory.swift
  $app/Models/AnalysisRecord.swift
  $app/Analysis/ExtractedFeatures.swift
  $app/Analysis/VisionExtractor.swift
  $app/Analysis/EntityExtractor.swift
  $app/Analysis/ScreenshotClassifier.swift
  $app/Analysis/Text/TextNormalizer.swift
  $app/Analysis/Fusion/SignalFusion.swift
  $app/Analysis/Rules/*.swift
  $root/Tools/eval/main.swift
  $root/Tools/eval/rescore.swift
)
newest=$(ls -t $sources | head -1)
if [[ ! -x $out/screenshot-eval || $newest -nt $out/screenshot-eval ]]; then
  xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 $sources -o $out/screenshot-eval
fi
cd $root
exec $out/screenshot-eval "$@"
