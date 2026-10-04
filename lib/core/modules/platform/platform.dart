/// Module Platform — Stage 1, 2, 3 & 4: Core Package I/O, Security Guards, Sandbox & Storage Serialization, Module Importer, Module Exporter.
///
/// This library provides low-level, isolated components for reading,
/// writing, and validating .phm (Personal Hub Module) packages,
/// managing module sandboxes, serializing module storage, importing and exporting modules.
///
/// It does NOT depend on ModuleManager, ModuleRegistry, or any
/// higher-level module infrastructure. It is a pure data I/O layer.
library module_platform;

export 'importer_exceptions.dart';
export 'module_importer.dart';
export 'module_exporter.dart';
export 'module_sandbox.dart';
export 'module_storage_serializer.dart';
export 'package_content.dart';
export 'package_exceptions.dart';
export 'package_reader.dart';
export 'package_security_guard.dart';
export 'package_writer.dart';
export 'sandbox_exceptions.dart';
export 'serializer_exceptions.dart';