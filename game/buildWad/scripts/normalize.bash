set -euo pipefail
TARGET_PATH=$1
TARGET_LEVEL=$2
TARGET_NT_TYPE=$3
PROBE_RESULT=$(ffprobe "$TARGET_PATH" 2>&1)
PROBE_HZ=$(echo "$PROBE_RESULT" | rg '([0-9]+) Hz' -or '$1')
EXTRA_ARGS=""
# ffmpeg-normalize mistakenly forces pcm_s8 codec, which is not supported in ffmpeg.
# This works around this bug.
if echo "$PROBE_RESULT" | grep 'pcm_u8' &>/dev/null; then
    EXTRA_ARGS="$EXTRA_ARGS -c:a pcm_u8"
fi
# ffmpeg-normalize requires to explicitly set audio codec for mp3
if echo "$PROBE_RESULT" | grep 'Audio: mp3' &>/dev/null; then
    EXTRA_ARGS="$EXTRA_ARGS -c:a libmp3lame"
fi
NAME="${TARGET_PATH##**/}"
BASENAME="${NAME%.*}"
EXT="${NAME##*.}"
DIRNAME=$(dirname $TARGET_PATH)
#echo $NAME $BASENAME $EXT $DIRNAME
ffmpeg-normalize $TARGET_PATH -o $TARGET_PATH -f -nt $TARGET_NT_TYPE -t $TARGET_LEVEL -ar $PROBE_HZ -v -ext $EXT $EXTRA_ARGS

