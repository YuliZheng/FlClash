//go:build android && !with_low_memory

package main

import "runtime/debug"

const androidMemoryLimit = 64 * 1024 * 1024

func init() {
	debug.SetMemoryLimit(androidMemoryLimit)
}
