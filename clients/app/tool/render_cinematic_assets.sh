#!/usr/bin/env bash

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_DIR="$APP_DIR/assets/cinematic"
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
FPS=24

MASTER="$ASSET_DIR/breathing_corridor_master.png"
ALIGNED="$ASSET_DIR/breathing_corridor_aligned.png"
OPEN="$ASSET_DIR/breathing_corridor_open.png"

for frame in "$MASTER" "$ALIGNED" "$OPEN"; do
  if [[ ! -f "$frame" ]]; then
    echo "缺少电影场景定帧：$frame" >&2
    exit 1
  fi
done

# 建立通道时同样只替换门洞内部像素，建筑本体保持母版不变。
"$FFMPEG" -y -hide_banner -loglevel warning \
  -loop 1 -framerate "$FPS" -t 0.38 -i "$MASTER" \
  -loop 1 -framerate "$FPS" -t 0.38 -i "$ALIGNED" \
  -filter_complex "
    [0:v]scale=1600:1000,format=yuv444p,split=3[base][mn][mf];
    [1:v]scale=1600:1000,format=yuv444p,split=2[an][af];
    [mn]crop=270:560:385:70[mnc];
    [an]crop=270:560:385:70[anc];
    [mnc][anc]xfade=transition=fade:duration=0.34:offset=0[n1];
    color=black:s=270x560:r=$FPS:d=0.38,format=gray,
      geq=lum='255*min(1,between(X,42,228)*gte(Y,120)*lte(Y,535)+gte(Y,28)*lt(Y,120)*lte(pow((X-135)/93,2)+pow((Y-120)/92,2),1))',gblur=sigma=2.2[nm];
    [n1][nm]alphamerge[n2];
    [mf]crop=150:320:1220:300[mfc];
    [af]crop=150:320:1220:300[afc];
    [mfc][afc]xfade=transition=fade:duration=0.34:offset=0[f1];
    color=black:s=150x320:r=$FPS:d=0.38,format=gray,
      geq=lum='255*min(1,between(X,48,118)*gte(Y,72)*lte(Y,310)+gte(Y,36)*lt(Y,72)*lte(pow((X-83)/35,2)+pow((Y-72)/36,2),1))',gblur=sigma=1.4[fm];
    [f1][fm]alphamerge[f2];
    [base][n2]overlay=385:70[tmp];
    [tmp][f2]overlay=1220:300,format=yuv420p[out]
  " \
  -map "[out]" -t 0.36 -an -c:v libx264 -preset slow -crf 20 \
  -movflags +faststart "$ASSET_DIR/corridor_connecting.mp4"

# 通道开启也被限制在门洞内，随后由 Flutter 做无方向性的光学溶解。
"$FFMPEG" -y -hide_banner -loglevel warning \
  -loop 1 -framerate "$FPS" -t 0.20 -i "$ALIGNED" \
  -loop 1 -framerate "$FPS" -t 0.20 -i "$OPEN" \
  -filter_complex "
    [0:v]scale=1600:1000,format=yuv444p,split=3[base][an][af];
    [1:v]scale=1600:1000,format=yuv444p,split=2[on][of];
    [an]crop=270:560:385:70[anc];
    [on]crop=270:560:385:70[onc];
    [anc][onc]xfade=transition=fade:duration=0.28:offset=0[n1];
    color=black:s=270x560:r=$FPS:d=0.20,format=gray,
      geq=lum='255*min(1,between(X,42,228)*gte(Y,120)*lte(Y,535)+gte(Y,28)*lt(Y,120)*lte(pow((X-135)/93,2)+pow((Y-120)/92,2),1))',gblur=sigma=2.2[nm];
    [n1][nm]alphamerge[n2];
    [af]crop=150:320:1220:300[afc];
    [of]crop=150:320:1220:300[ofc];
    [afc][ofc]xfade=transition=fade:duration=0.28:offset=0[f1];
    color=black:s=150x320:r=$FPS:d=0.20,format=gray,
      geq=lum='255*min(1,between(X,48,118)*gte(Y,72)*lte(Y,310)+gte(Y,36)*lt(Y,72)*lte(pow((X-83)/35,2)+pow((Y-72)/36,2),1))',gblur=sigma=1.4[fm];
    [f1][fm]alphamerge[f2];
    [base][n2]overlay=385:70[tmp];
    [tmp][f2]overlay=1220:300,format=yuv420p[out]
  " \
  -map "[out]" -t 0.18 -an -c:v libx264 -preset slow -crf 20 \
  -movflags +faststart "$ASSET_DIR/corridor_enter.mp4"

echo "电影动画资源已生成："
du -h "$ASSET_DIR"/*.mp4
