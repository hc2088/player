#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT_DIR=""
OUTPUT_DIR="$PROJECT_ROOT/assets/local_media"
ENCRYPTED_EXT="cpp"
CLEAN_OUTPUT=0

usage() {
  cat <<'USAGE'
Encrypt local media files for the Flutter app.

Usage:
  scripts/encrypt_local_media.sh -i <plain-media-dir> [options]

Options:
  -i, --input <dir>       Plain media directory to encrypt.
  -o, --output <dir>      Output directory. Default: assets/local_media
  -e, --ext <cpp|dat>     Encrypted file suffix. Default: cpp
      --clean             Remove existing encrypted files in output dir first.
  -h, --help              Show this help.

Supported input extensions:
  jpg jpeg png webp mp4 mp3 m4a aac wav ogg flac

Password:
  The script asks for the original password. The app stores only its MD5 in
  LocalMediaService.unlockPasswordMd5, but decrypting media still requires
  the original password.

Example:
  scripts/encrypt_local_media.sh -i ~/Desktop/plain_media

Non-interactive example:
  LOCAL_MEDIA_PASSWORD='1234' scripts/encrypt_local_media.sh -i ./plain_media
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

normalize_path() {
  local path="$1"
  mkdir -p "$path"
  (cd "$path" && pwd)
}

password_md5() {
  local password="$1"
  if command -v md5 >/dev/null 2>&1; then
    md5 -s "$password" | sed 's/.*= *//' | tr -d ' '
  elif command -v md5sum >/dev/null 2>&1; then
    printf '%s' "$password" | md5sum | awk '{print $1}'
  else
    die "md5 or md5sum is required"
  fi
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

is_supported_media() {
  local file="$1"
  local ext="${file##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
    jpg|jpeg|png|webp|mp4|mp3|m4a|aac|wav|ogg|flac)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

asset_path_for_output() {
  local output_file="$1"
  local base_name
  base_name="$(basename "$output_file")"
  printf 'assets/local_media/%s' "$base_name"
}

write_index_json() {
  local index_file="$OUTPUT_DIR/index.json"
  local first=1

  {
    printf '[\n'
    while IFS= read -r -d '' file; do
      local asset_path
      asset_path="$(asset_path_for_output "$file")"
      if [[ $first -eq 0 ]]; then
        printf ',\n'
      fi
      first=0
      printf '  "%s"' "$(json_escape "$asset_path")"
    done < <(find "$OUTPUT_DIR" -type f \( -name "*.cpp" -o -name "*.dat" \) -print0)
    printf '\n]\n'
  } > "$index_file"
}

encrypt_file() {
  local input_file="$1"
  local password="$2"
  local output_file="$3"

  openssl enc -aes-256-cbc \
    -a \
    -salt \
    -md sha256 \
    -pass "pass:$password" \
    -in "$input_file" \
    -out "$output_file"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--input)
        INPUT_DIR="${2:-}"
        shift 2
        ;;
      -o|--output)
        OUTPUT_DIR="${2:-}"
        shift 2
        ;;
      -e|--ext)
        ENCRYPTED_EXT="${2:-}"
        shift 2
        ;;
      --clean)
        CLEAN_OUTPUT=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  [[ -n "$INPUT_DIR" ]] || die "missing input directory. Use -i <dir>."
  [[ -d "$INPUT_DIR" ]] || die "input directory does not exist: $INPUT_DIR"
  [[ "$ENCRYPTED_EXT" == "cpp" || "$ENCRYPTED_EXT" == "dat" ]] || die "--ext must be cpp or dat"
  command -v openssl >/dev/null 2>&1 || die "openssl is required"

  INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"
  OUTPUT_DIR="$(normalize_path "$OUTPUT_DIR")"

  local password="${LOCAL_MEDIA_PASSWORD:-}"
  if [[ -z "$password" ]]; then
    read -r -s -p "Enter original password: " password
    printf '\n'
  fi
  password="$(printf '%s' "$password" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$password" ]] || die "password is empty"

  local md5_value
  md5_value="$(password_md5 "$password")"
  echo "Password MD5 for LocalMediaService.unlockPasswordMd5:"
  echo "$md5_value"

  if [[ $CLEAN_OUTPUT -eq 1 ]]; then
    find "$OUTPUT_DIR" -type f \( -name "*.cpp" -o -name "*.dat" -o -name "index.json" \) -delete
  fi

  local count=0
  while IFS= read -r -d '' input_file; do
    if ! is_supported_media "$input_file"; then
      continue
    fi

    local base_name
    base_name="$(basename "$input_file")"
    local output_file="$OUTPUT_DIR/$base_name.$ENCRYPTED_EXT"

    if [[ -e "$output_file" ]]; then
      die "output already exists: $output_file. Use --clean or rename the source file."
    fi

    encrypt_file "$input_file" "$password" "$output_file"
    count=$((count + 1))
    echo "Encrypted: $input_file -> $output_file"
  done < <(find "$INPUT_DIR" -type f -print0)

  [[ $count -gt 0 ]] || die "no supported media files found in: $INPUT_DIR"

  write_index_json

  echo "Done. Encrypted $count file(s)."
  echo "Output: $OUTPUT_DIR"
  echo "Index: $OUTPUT_DIR/index.json"
  echo "Run flutter pub get or rebuild the app so Flutter bundles the updated assets."
}

main "$@"
