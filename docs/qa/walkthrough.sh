#!/bin/zsh
# Runs one QAWalkthroughTests method while recording the simulator screen, then exports the
# checkpoint screenshots and lines up `QA-MARK` timestamps with the video.
#
#   docs/qa/walkthrough.sh <test-method> [out-dir]
#   QA_DEVICE=<udid> TEST_RUNNER_QA_ARGS="-hasSeenOnboarding YES" docs/qa/walkthrough.sh test05SortedLibrary
#   TEST_RUNNER_QA_ONBOARDING=1 docs/qa/walkthrough.sh test01LaunchOnboardingAccess
#
# Output: <out>/video.mov, <out>/att/*.png (named checkpoints), <out>/marks.txt (seconds into the video).
# Frame timing: `ffprobe -select_streams v -show_entries frame=pts_time -of csv=p=0 <out>/video.mov`.
# The recorder only writes frames when the screen changes, so a gap while something is moving is a hitch.
# Variants: `xcrun simctl ui <udid> appearance dark`, `xcrun simctl ui <udid> content_size
# accessibility-extra-extra-extra-large`, and Reduce Motion via
# `xcrun simctl spawn <udid> defaults write com.apple.Accessibility ReduceMotionEnabled -bool true`.
set -u
method=$1
root=${0:A:h:h:h}
out=${2:-$root/build/qa/$method}
device=${QA_DEVICE:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)}
derived=${QA_DERIVED_DATA:-$root/build/qa/DerivedData}
rm -rf $out $out.xcresult; mkdir -p $out
cd $root
xcodebuild build-for-testing -project ScreenshotSorter.xcodeproj -scheme ScreenshotSorter \
  -destination "id=$device" -derivedDataPath $derived -quiet > $out/build.log 2>&1 || { tail -30 $out/build.log; exit 1; }
python3 -c "import time; print(time.time())" > $out/t0
xcrun simctl io $device recordVideo --codec=h264 --force $out/video.mov > /dev/null 2>&1 & recorder=$!
sleep 1
xcodebuild test-without-building -project ScreenshotSorter.xcodeproj -scheme ScreenshotSorter \
  -destination "id=$device" -derivedDataPath $derived \
  -only-testing:ScreenshotSorterUITests/QAWalkthroughTests/$method -resultBundlePath $out.xcresult > $out/test.log 2>&1
result=$?
kill -INT $recorder; wait $recorder 2>/dev/null
t0=$(cat $out/t0)
grep -o "QA-MARK .*" $out/test.log | awk -v t0=$t0 '{printf "%-24s %.2f\n", $2, $3-t0}' > $out/marks.txt
xcrun xcresulttool export attachments --path $out.xcresult --output-path $out/att > /dev/null 2>&1
python3 - $out/att <<'PY'
import json, os, sys
d = sys.argv[1]
for test in json.load(open(os.path.join(d, 'manifest.json'))):
    for a in test['attachments']:
        name = a['suggestedHumanReadableName'].split('_0_')[0].replace(' ', '_')
        os.rename(os.path.join(d, a['exportedFileName']), os.path.join(d, name + '.png'))
PY
grep -E "error:|Test Case .*(passed|failed)" $out/test.log | tail -5
echo "results: $out (exit $result)"
exit $result
