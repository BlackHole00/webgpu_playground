package renderer

import "base:runtime"
import "core:sync"
import "core:log"
import "core:thread"
import "vendor:wgpu"

Wgpu_Ticker_Thread :: struct {
	allocator: runtime.Allocator,
	ticker_thread: ^thread.Thread,
	device: wgpu.Device,
	should_close: bool, // atomic
	current_frame_ended: bool, // atomic
	ticker_sync: ^sync.Futex,
}

wgputickerthread_create_and_start :: proc(
	ticker: ^Wgpu_Ticker_Thread,
	device: wgpu.Device,
	allocator := context.allocator,
) -> bool {
	ticker.allocator = allocator
	ticker.device = device

	ticker.ticker_sync = new(sync.Futex, allocator)

	ticker.ticker_thread = thread.create_and_start_with_poly_data(ticker, wgputickerthread_threadproc, context)
	if ticker.ticker_thread == nil {
		log.errorf("Could not create a Wgpu Ticker Thread: Could not create and start a thread")
		return false
	}

	return true
}

wgputickerthread_stop_and_destroy :: proc(ticker: ^Wgpu_Ticker_Thread) {
	sync.atomic_store(&ticker.should_close, true)
	thread.join(ticker.ticker_thread)

	free(ticker.ticker_thread, ticker.allocator)
}

wgputickerthread_begin_frame :: proc(ticker: ^Wgpu_Ticker_Thread) {
	sync.atomic_store(ticker.ticker_sync, 1)
	sync.atomic_store(&ticker.current_frame_ended, false)
}

wgputickerthread_end_frame :: proc(ticker: ^Wgpu_Ticker_Thread) {
	sync.atomic_store(&ticker.current_frame_ended, true)
}

// Waits for the queue to process all the commands
wgputickerthread_sync :: proc(ticker: ^Wgpu_Ticker_Thread) {
	sync.futex_wait(ticker.ticker_sync, 1)
}

@(private="file")
wgputickerthread_threadproc :: proc(ticker: ^Wgpu_Ticker_Thread) {
	for !sync.atomic_load(&ticker.should_close) {
		if wgpu.DevicePoll(ticker.device, false) {
			if _, ok := sync.atomic_compare_exchange_strong(&ticker.current_frame_ended, true, false); ok {
				sync.atomic_store(ticker.ticker_sync, 0)
				sync.futex_broadcast(ticker.ticker_sync)
			}

			thread.yield()
		}
	}
}
