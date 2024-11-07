package main

import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"
import "core:flags"
import "vendor:wgpu"
import "project:renderer/shader_preprocessor"

Command_Line_Options :: struct {
	files: [dynamic]string `args:"pos=0,required=1" usage:"Shader input file(s)"`,
	include_path: [dynamic]string `usage:"Specifies the include path(s)"`,
	allow_namespaces: bool `usage:"Allows namespace usage when preprocessing"`,
	verbose: bool `usage:"Print more messages"`,
}

g_command_line_options: Command_Line_Options
g_logger: log.Logger
g_instance: wgpu.Instance
g_adapter: wgpu.Adapter
g_device: wgpu.Device
g_shaderpreprocessor: shader_preprocessor.Shader_Preprocessor

main :: proc() {
	flags.parse_or_exit(&g_command_line_options, os.args, .Odin, context.temp_allocator)

	g_logger = log.create_console_logger(log.Level.Debug if g_command_line_options.verbose else log.Level.Info)
	defer log.destroy_file_logger(g_logger)
	context.logger = g_logger

	instance_init()
	defer wgpu.InstanceRelease(g_instance)

	adapter_init()
	defer wgpu.AdapterRelease(g_adapter)

	device_init()
	defer wgpu.DeviceRelease(g_device)

	err := shader_preprocessor.create(&g_shaderpreprocessor)
	log.assertf(err == nil, "Could not create a shader preprocessor")
	defer shader_preprocessor.destroy(&g_shaderpreprocessor)

	for include in g_command_line_options.include_path {
		log.assertf(
			shader_preprocessor.add_include_path(&g_shaderpreprocessor, include) == nil,
			"Could not add the required include files to the path",
		)
	}

	for file in g_command_line_options.files {
		log.infof("Checking file %s", file)

		source, preprocess_error := shader_preprocessor.preprocess(
			&g_shaderpreprocessor,
			file,
			shader_preprocessor.Preprocess_Options {
				allow_namespaces = g_command_line_options.allow_namespaces,
			},
		)
		if preprocess_error != nil {
			log.panicf("Got error in shader file %s: Preprocess failed", file)
		}

		log.debugf("Preprocess output: %s", source)

		shader_module := wgpu.DeviceCreateShaderModule(
			g_device,
			&wgpu.ShaderModuleDescriptor {
				label = strings.clone_to_cstring(file, context.temp_allocator),
				nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
					sType = .ShaderModuleWGSLDescriptor,
					code = strings.clone_to_cstring(source, context.temp_allocator),
				},
			},
		)
		if shader_module == nil {
			log.panicf("Got error in shader file %s: Could not compile shader", file)
		}
		defer wgpu.ShaderModuleRelease(shader_module)
	}
}

instance_init :: proc() {
	when ODIN_OS == .Windows {
		BACKENDS :: wgpu.InstanceBackendFlags { .Vulkan, .DX12, .DX11, .GL }
	} else when ODIN_OS == .Darwin {
		BACKENDS :: wgpu.InstanceBackendFlags { .Metal, .Vulkan, .GL }
	} else {
		BACKENDS :: wgpu.InstanceBackendFlags { .Vulkan, .GL }
	}

	FLAGS :: wgpu.InstanceFlags { .Debug, .Validation } when ODIN_DEBUG else wgpu.InstanceFlags_Default
	LOG_LEVEL :: wgpu.LogLevel.Info when #config(WGPU_VERBOSE_LOGS, false) else wgpu.LogLevel.Warn
	
	wgpu.SetLogCallback(wgpu_log_callback, nil)
	wgpu.SetLogLevel(LOG_LEVEL)
	
	instance_descriptor := wgpu.InstanceDescriptor {
		nextInChain = &wgpu.InstanceExtras {
			sType = .InstanceExtras,
			backends = BACKENDS,
			flags = FLAGS,
		},
	}
	log.debugf("Creating an instance using the following descriptor: %#v", instance_descriptor)
	log.debugf("Note: Using in chain: %#v", (^wgpu.InstanceExtras)(instance_descriptor.nextInChain)^)

	g_instance = wgpu.CreateInstance(&instance_descriptor)
	log.assertf(g_instance != nil, "Could not create a wgpu instance")
}

adapter_init :: proc() {
	adapter_options := wgpu.RequestAdapterOptions {
		powerPreference = .HighPerformance,
	}
	log.debugf("Creating an adapter with the following options: %#v", adapter_options)
	
	wgpu.InstanceRequestAdapter(
		g_instance,
		&adapter_options,
		wgpu_request_adapter_callback,
		nil,
	)
	log.assertf(g_adapter != nil, "Could not create an adapter: For some reason InstanceRequestAdapter is async?")
}

device_init :: proc() {
	device_descriptor := wgpu.DeviceDescriptor {
		deviceLostCallback = wgpu_device_lost_callback,
	}
	log.debugf("Creating a device with the following descriptor: %#v", device_descriptor)
	
	wgpu.AdapterRequestDevice(
		g_adapter,
		&device_descriptor,
		wgpu_request_device_callback,
		nil,
	)
	log.assertf(g_device != nil, "Could not create a device: For some reason InstanceRequestDevice is async?")
}

@(private="file")
wgpu_log_callback :: proc "c" (level: wgpu.LogLevel, message: cstring, userdata: rawptr) {
	context = runtime.default_context()
	context.logger = g_logger

	switch level {
	case .Off:
	case .Trace:
	case .Debug:
		log.debugf("[WGPU] %s", message)
	case .Info:
		log.infof("[WGPU] %s", message)
	case .Warn:
		log.warnf("[WGPU] %s", message)
	case .Error:
		log.errorf("[WGPU] %s", message)
	}
}

@(private="file")
wgpu_request_adapter_callback :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	result: wgpu.Adapter,
	message: cstring,
	user_data: rawptr,
) {
	context = runtime.default_context()
	context.logger = g_logger
	
	switch status {
	case .Unavailable:
	case .Unknown:
	case .Error:
		log.panicf("Could not request an adapter. Got the following message: %s", message)
	case .Success:
		if message != nil && message != "" {
			log.debugf("Obtained an adapter with the following message: %s", message)
		}
	}
	
	g_adapter = result
}

@(private="file")
wgpu_request_device_callback :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	result: wgpu.Device,
	message: cstring,
	user_data: rawptr,
) {
	context = runtime.default_context()
	context.logger = g_logger
	
	switch status {
	case .Unknown:
	case .Error:
		log.panicf("Could not request a device. Got the following message: %s", message)
	case .Success:
		if message != nil && message != "" {
			log.debugf("Obtained a device with the following message: %s", message)
		}
	}
	
	g_device = result
}

@(private="file")
wgpu_device_lost_callback :: proc "c" (reason: wgpu.DeviceLostReason, message: cstring, userdata: rawptr) {
	context = runtime.default_context()
	context.logger = g_logger

	log.panicf("Lost device: %s\n", message)
}

