#!/bin/zsh
# Measures grid scroll smoothness without UI-test input: launches a Debug build with
# -QAOpenGallery / -QAAutoScroll (scripted scrolling inside the app), records the screen and
# reports frame gaps while the picture is moving.
#
#   docs/qa/autoscroll.sh <simulator-udid> [launch args…]
#   docs/qa/autoscroll.sh <udid> -QAAutoScrollSpeed 2          # ~2× faster jumps
#   docs/qa/autoscroll.sh <udid> -QAPauseAnalysis NO           # measure while sorting
#
# XCUITest swipes are not a fair input for this: the runner's own work between gestures shows up
# as dropped frames (7–10% "hitches" vs ~0.1% with this script on the same 2,000-item library).
set -u
device=$1; shift
root=${0:A:h:h:h}
out=${QA_OUT:-$root/build/qa/autoscroll}
derived=${QA_DERIVED_DATA:-$root/build/qa/DerivedData}
rm -rf $out; mkdir -p $out
cd $root
xcodebuild build -project ScreenshotSorter.xcodeproj -scheme ScreenshotSorter -destination "id=$device" \
  -derivedDataPath $derived -quiet > $out/build.log 2>&1 || { tail -20 $out/build.log; exit 1; }
xcrun simctl install $device $derived/Build/Products/Debug-iphonesimulator/ScreenshotSorter.app
xcrun simctl terminate $device sabtain.ScreenshotSorter 2>/dev/null
python3 -c "import time; print(time.time())" > $out/t0
xcrun simctl io $device recordVideo --codec=h264 --force $out/video.mov > /dev/null 2>&1 & recorder=$!
sleep 1
xcrun simctl launch --console $device sabtain.ScreenshotSorter -hasSeenOnboarding YES -QAPauseAnalysis YES \
  -QAOpenGallery YES -QAAutoScroll YES "$@" > $out/console.txt 2>&1 & app=$!
for _ in $(seq 1 120); do grep -q "QA-AUTOSCROLL end" $out/console.txt && break; sleep 1; done
kill -INT $recorder; wait $recorder 2>/dev/null; kill $app 2>/dev/null
t0=$(cat $out/t0)
start=$(grep -o "QA-AUTOSCROLL start [0-9.]*" $out/console.txt | awk -v t=$t0 '{print $3 - t}')
end=$(grep -o "QA-AUTOSCROLL end [0-9.]*" $out/console.txt | awk -v t=$t0 '{print $3 - t}')
[[ -z $start || -z $end ]] && { echo "autoscroll did not run (needs > 120 screenshots and photo access)"; exit 1; }
python3 - $out/video.mov $start $end <<'PY'
import subprocess, sys
video, start, end = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
pts = [float(p.strip(',')) for p in subprocess.run(
    ['ffprobe', '-v', 'error', '-select_streams', 'v', '-show_entries', 'frame=pts_time', '-of', 'csv=p=0', video],
    capture_output=True, text=True).stdout.split() if p.strip(',')]
window = [p for p in pts if start <= p <= end]
raw = subprocess.run(['ffmpeg', '-v', 'error', '-ss', str(start), '-i', video, '-t', str(end - start),
                      '-fps_mode', 'passthrough', '-vf', 'scale=40:-1,format=gray', '-f', 'rawvideo', '-'],
                     capture_output=True).stdout
size = len(raw) // max(1, len(window))
moving, hitches = 0, []
for k in range(1, len(window)):
    a, b = raw[(k - 1) * size:k * size], raw[k * size:(k + 1) * size]
    if sum(abs(x - y) for x, y in zip(a, b)) / max(1, size) > 2:
        moving += 1
        gap = window[k] - window[k - 1]
        if gap >= 0.034:
            hitches.append(round(gap * 1000))
print(f"moving frames {moving}, hitches ≥34 ms {len(hitches)} ({100 * len(hitches) / max(1, moving):.2f}%), worst {sorted(hitches, reverse=True)[:5]} ms")
PY
