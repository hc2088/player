#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT_DIR="$PROJECT_ROOT/assets/local_media"
OUTPUT_DIR="$PROJECT_ROOT/decrypted_local_media"
CLEAN_OUTPUT=0
DIGEST_MODE="auto"

usage() {
  cat <<'USAGE'
Decrypt local media files on your computer.

Usage:
  scripts/decrypt_local_media.sh [options]

Options:
  -i, --input <dir>       Encrypted media directory. Default: assets/local_media
  -o, --output <dir>      Decrypted output directory. Default: decrypted_local_media
  -m, --md <auto|sha256|md5>
                          OpenSSL digest used by encryption. Default: auto
      --clean             Remove existing output files first.
  -h, --help              Show this help.

Password:
  Enter the original password, not its MD5. The MD5 is only used by the app to
  verify the password before decrypting.

Example:
  scripts/decrypt_local_media.sh
  scripts/decrypt_local_media.sh -i assets/local_media -o ~/Desktop/decrypted_media

Non-interactive example:
  LOCAL_MEDIA_PASSWORD='1234' scripts/decrypt_local_media.sh -o ./decrypted_media
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

strip_encrypted_extension() {
  local file_name="$1"
  case "$file_name" in
    *.cpp)
      printf '%s' "${file_name%.cpp}"
      ;;
    *.dat)
      printf '%s' "${file_name%.dat}"
      ;;
    *)
      printf '%s' "$file_name"
      ;;
  esac
}

decrypt_with_digest() {
  local input_file="$1"
  local output_file="$2"
  local password="$3"
  local digest="$4"

  openssl enc -aes-256-cbc \
    -d \
    -a \
    -salt \
    -md "$digest" \
    -pass "pass:$password" \
    -in "$input_file" \
    -out "$output_file" >/dev/null 2>&1
}

decrypt_file() {
  local input_file="$1"
  local output_file="$2"
  local password="$3"
  local temp_file="$output_file.tmp.$$"

  rm -f "$temp_file"

  if [[ "$DIGEST_MODE" == "auto" || "$DIGEST_MODE" == "sha256" ]]; then
    if decrypt_with_digest "$input_file" "$temp_file" "$password" "sha256"; then
      mv "$temp_file" "$output_file"
      return 0
    fi
    rm -f "$temp_file"
  fi

  if [[ "$DIGEST_MODE" == "auto" || "$DIGEST_MODE" == "md5" ]]; then
    if decrypt_with_digest "$input_file" "$temp_file" "$password" "md5"; then
      mv "$temp_file" "$output_file"
      return 0
    fi
    rm -f "$temp_file"
  fi

  return 1
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
      -m|--md)
        DIGEST_MODE="${2:-}"
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

  [[ -d "$INPUT_DIR" ]] || die "input directory does not exist: $INPUT_DIR"
  case "$DIGEST_MODE" in
    auto|sha256|md5)
      ;;
    *)
      die "--md must be auto, sha256, or md5"
      ;;
  esac
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

  echo "Password MD5:"
  password_md5 "$password"

  if [[ $CLEAN_OUTPUT -eq 1 ]]; then
    find "$OUTPUT_DIR" -type f -delete
  fi

  local count=0
  local failed=0
  while IFS= read -r -d '' input_file; do
    local base_name
    base_name="$(basename "$input_file")"

    local output_name
    output_name="$(strip_encrypted_extension "$base_name")"
    local output_file="$OUTPUT_DIR/$output_name"

    if [[ -e "$output_file" ]]; then
      echo "Skip existing output: $output_file"
      continue
    fi

    if decrypt_file "$input_file" "$output_file" "$password"; then
      count=$((count + 1))
      echo "Decrypted: $input_file -> $output_file"
    else
      failed=$((failed + 1))
      echo "Failed: $input_file" >&2
    fi
  done < <(find "$INPUT_DIR" -type f \( -name "*.cpp" -o -name "*.dat" \) -print0)

  [[ $count -gt 0 || $failed -gt 0 ]] || die "no encrypted .cpp/.dat files found in: $INPUT_DIR"

  echo "Done. Decrypted $count file(s). Failed $failed file(s)."
  echo "Output: $OUTPUT_DIR"

  if [[ $failed -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
