#!/bin/bash
set -e
case "$1" in
  lint) exit 0 ;;
  pack)
    shift
    for arg in "$@"; do
      [[ "$arg" == --check-skeleton ]] && exit 0
    done
    filename=""; compression="xz"; prime_dir=""; output_dir="."
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --filename)    filename="$2";    shift 2 ;;
        --compression) compression="$2"; shift 2 ;;
        --*)           shift ;;
        *)
          if [[ -z "$prime_dir" ]]; then prime_dir="$1"
          else output_dir="$1"; fi
          shift ;;
      esac
    done
    mksquashfs "$prime_dir" "${output_dir}/${filename}" \
      -noappend -comp "$compression" -no-xattrs -all-root
    ;;
  *) exit 0 ;;
esac
