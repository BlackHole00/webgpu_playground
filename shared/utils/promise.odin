package utils

import "core:sync"
import "base:runtime"

Promise_Status :: enum sync.Futex {
	Waiting,
	Ready,
}

Promise :: struct($T: typeid) {
	allocator: runtime.Allocator,
	status: sync.Futex, // atomic, with value Promise_Status
	data: Maybe(T),
}

promise_new :: proc($T: typeid, allocator := context.allocator) -> ^Promise(T) {
	promise := new(Promise(T), allocator)
	promise.allocator = allocator

	return promise
}

promise_resolve :: proc(promise: ^Promise($T), data: T) {
	promise.data = data
	sync.atomic_store(&promise.status, (sync.Futex)(Promise_Status.Ready))
	sync.futex_broadcast(&promise.status)
}

promise_wait :: proc(promise: ^Promise($T)) {
	sync.futex_wait(&promise.status, Promise_Status.Waiting)
}

promise_get :: proc(promise: ^Promise($T)) -> (T, bool) {
	switch sync.atomic_load(&promise.status) {
	case .Waiting:
		return {}, false
	case .Ready:
		defer promise_force_free(promise)
		return promise.data.?, true
	}
}

promise_force_free :: proc(promise: ^Promise($T)) {
	free(promise, promise.allocator)
}

_ :: runtime
