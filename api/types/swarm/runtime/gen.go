//go:generate protoc -I . --gogofast_out=import_path=github.com/docker/docker/v24/api/types/swarm/runtime:. plugin.proto

package runtime
