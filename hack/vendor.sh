#!/usr/bin/env bash
#
# This file is just a wrapper around the 'go mod vendor' tool.
# For updating dependencies you should change `vendor.mod` file in root of the
# project.

set -e

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tidy() (
		set -x
		"${SCRIPTDIR}"/with-go-mod.sh go mod tidy -modfile vendor.mod -compat 1.18
)

vendor() (
		set -x
		"${SCRIPTDIR}"/with-go-mod.sh go mod vendor -modfile vendor.mod
)

validate() (
		diff=$(git status --porcelain -- vendor.mod vendor.sum vendor)
		if [ -n "$diff" ]; then
			echo >&2 'ERROR: Vendor result differs. Please revendor with hack/vendor.sh'
			echo "$diff"
			exit 1
		fi
)

help() {
	printf "%s:\n" "$(basename "$0")"
	echo "  - tidy: run go mod tidy"
	echo "  - vendor: run go mod vendor"
	echo "  - validate: validate vendor"
	echo "  - all: run tidy && vendor"
	echo "  - help: show this help"
}

case "$1" in
	tidy) tidy ;;
	vendor) vendor ;;
	validate) validate ;;
	""|all) tidy && vendor ;;
	*) help ;;
esac
