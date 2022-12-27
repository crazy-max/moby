//go:build !static_build
// +build !static_build

package linkmode

func IsStatic() bool {
	return false
}
