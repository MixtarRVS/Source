# AILang Code Map

Auto-generated index of 284 Python files. 
Run `python tools/codemap.py` to regenerate.

Lists top-level classes (with their methods) and free functions, 
each with a line number. Use this to jump to any symbol without 
grepping the larger files.

## Packages

- **`(launcher)`** - 1 file(s), 26 lines
- **`(source root)`** - 7 file(s), 372 lines
- **`cli`** - 14 file(s), 4,599 lines
- **`codegen`** - 40 file(s), 11,875 lines
- **`compiler`** - 3 file(s), 569 lines
- **`diagnostics`** - 18 file(s), 5,084 lines
- **`lexer`** - 3 file(s), 771 lines
- **`parser`** - 25 file(s), 8,049 lines
- **`pgo`** - 5 file(s), 460 lines
- **`runtime`** - 7 file(s), 1,853 lines
- **`tools`** - 6 file(s), 2,100 lines
- **`transpiler`** - 148 file(s), 46,302 lines
- **`ui_dsl`** - 7 file(s), 1,789 lines

## (launcher)

### ailang.py  (26 lines)

- `def main` - line 10

## (source root)

### source/abi_symbols.py  (92 lines)

- `def _decorator_texts` - line 12
- `def is_export_decorator` - line 18
- `def has_export_decorator` - line 23
- `def explicit_export_symbol` - line 27
- `def c_symbol_for_function` - line 47
- `def explicit_c_abi_parts` - line 55

### source/ast_access.py  (31 lines)

- `def arg_at` - line 8
- `def body_at` - line 13
- `def param_at` - line 18
- `def target_at` - line 23
- `def value_at` - line 28

### source/callback_types.py  (42 lines)

- `def is_callback_type` - line 10
- `def callback_parts` - line 18
- `def resolve_callback_alias` - line 28

### source/calling_conventions.py  (29 lines)

- `def normalized_decorators` - line 6
- `def c_callconv_macro` - line 13
- `def llvm_calling_convention` - line 22

### source/target_info.py  (80 lines)

- `def normalize_os_name` - line 8
- `def target_matches` - line 34
- `def os_from_platform` - line 50
- `def os_from_triple` - line 64

### source/token_access.py  (32 lines)

- `def token_type_at` - line 10
- `def token_text_at` - line 16
- `def token_line_at` - line 22
- `def token_col_at` - line 28

### source/version.py  (66 lines)

- `def get_version_string` - line 57
- `def get_feature_status` - line 62

## cli

### source/cli/builtins.py  (481 lines)

- `def _print_builtins` - line 6

### source/cli/cinclude_diagnostics.py  (357 lines)

- `class CIncludeDirective` - line 15
- `class CIncludeDiagnostic` - line 31
  - `to_diagnostic` - line 40
  - `to_dict` - line 50
- `def format_cinclude` - line 68
- `def cinclude_backend_support_payload` - line 83
- `def _resolve_local_header` - line 105
- `def cinclude_directive_from_node` - line 122
- `def cinclude_directive_payload` - line 153
- `def collect_cinclude_directives` - line 178
- `def diagnose_cinclude_directives` - line 228
- `def collect_cinclude_diagnostics` - line 274
- `def collect_cinclude_include_dirs` - line 295
- `def cinclude_backend_warning` - line 326
- `def emit_cinclude_backend_warning` - line 343

### source/cli/compilation.py  (735 lines)

- `def _normalize_mingw_vararg_symbols` - line 43
- `def _split_ailang_link_flags` - line 52
- `def _split_targeted_link_payload` - line 67
- `def _extract_ailang_link_flags` - line 81
- `def _merge_link_flags` - line 110
- `def _normalize_native_toolchain` - line 123
- `def _resolve_tool` - line 138
- `def _default_clang_target` - line 155
- `def _sanitize_stem` - line 165
- `def _source_identity_tag` - line 170
- `def _intermediate_artifact_path` - line 175
- `def default_pgo_output_dir` - line 184
- `def _summarize_compiler_failure` - line 189
- `def _pgo_compile_flags` - line 198
- `def default_emit_llvm_output_path` - line 210
- `def default_emit_c_output_path` - line 215
- `def compile_via_c` - line 220
- `def compile_to_native` - line 393

### source/cli/diagnostics.py  (390 lines)

- `def _parse_program_ast` - line 21
- `def run_prepass` - line 36
- `def _collect_effect_policy_diagnostics` - line 111
- `def _collect_cinclude_diagnostics` - line 127
- `def run_effect_policy_gate` - line 135
- `def _run_ast_analysis` - line 149
- `def run_diagnostics` - line 166
- `def run_diagnostics_on_error` - line 222
- `def run_diagnostics_json` - line 240
- `def run_static_analysis` - line 346

### source/cli/emit_c_output.py  (33 lines)

- `def _output_arg` - line 8
- `def maybe_emit_c_source` - line 15

### source/cli/header_generation.py  (508 lines)

- `def default_header_output_path` - line 23
- `def _decorator_names` - line 30
- `def _header_guard` - line 35
- `def _parse_source` - line 45
- `def _configured_transpiler` - line 58
- `def _emit_includes` - line 82
- `def _emit_record` - line 108
- `def _emit_union` - line 119
- `def _emit_callback_alias` - line 130
- `def _emit_extern_record` - line 148
- `def _type_to_text` - line 160
- `def _emit_exported_function` - line 166
- `def generate_c_header` - line 178
- `def _cabi_guard` - line 307
- `def _cabi_type_to_c` - line 318
- `def _cabi_value_to_c` - line 324
- `def _cabi_params_to_c` - line 335
- `def _emit_cabi_macro` - line 345
- `def _emit_cabi_inline` - line 356
- `def _emit_cabi_entries` - line 378
- `def _emit_cabi_header_block` - line 441
- `def generate_cabi_headers` - line 465
- `def write_cabi_headers` - line 477
- `def write_c_header` - line 496

### source/cli/layout_probe.py  (165 lines)

- `def _available_c_compiler` - line 17
- `def _quote_c_string` - line 22
- `def _probe_source` - line 27
- `def _empty_payload` - line 60
- `def _parse_probe_output` - line 70
- `def probe_ffi_layout` - line 99

### source/cli/llvm_diagnostics.py  (199 lines)

- `def _detect_llvm_link_flags` - line 20
- `def _first_nonempty_line` - line 49
- `def _normalize_link_symbol` - line 76
- `def _extract_undefined_symbols` - line 86
- `def _derive_missing_link_hints` - line 104
- `def _format_llvm_failure_diagnostics` - line 172

### source/cli/main.py  (751 lines)

- `def _read_project_version` - line 88
- `def main` - line 112

### source/cli/optimizer_report.py  (108 lines)

- `def report_optimizer` - line 9
- `def _print_backend_report` - line 75

### source/cli/pgo_options.py  (93 lines)

- `class PgoCliOptions` - line 13
- `def wants_llvm_pgo_probe` - line 22
- `def run_llvm_pgo_probe_cli` - line 27
- `def parse_pgo_cli_options` - line 48
- `def validate_pgo_cli_options` - line 84

### source/cli/reports.py  (724 lines)

- `def report_runtime_needs` - line 25
- `def _decorator_names` - line 98
- `def _c_symbol_mangler` - line 103
- `def report_ffi` - line 124
- `def report_checks` - line 516
- `def report_format` - line 580
- `def report_effect_policy` - line 645

## codegen

### source/codegen/bigint_runtime.py  (141 lines)

- `class BigIntRuntime` - line 16
  - `__init__` - line 19
  - `__getattr__` - line 22
  - `_get_bigint_type` - line 25
  - `_get_bigint_new` - line 38
  - `_get_bigint_from_int` - line 47
  - `_get_bigint_add` - line 56
  - `_get_bigint_sub` - line 65
  - `_get_bigint_mul` - line 74
  - `_get_bigint_div` - line 83
  - `_get_bigint_pow` - line 92
  - `_get_bigint_cmp` - line 101
  - `_get_bigint_print` - line 110
  - `_get_bigint_digits` - line 119
  - `_get_bigint_free` - line 128
  - `is_bigint_type` - line 137

### source/codegen/builtin_arrays.py  (741 lines)

- `class BuiltinArrayEmitter` - line 12
  - `__init__` - line 15
  - `__getattr__` - line 18
  - `_array_header_ptr` - line 27
  - `_stack_array_scalar_values` - line 33
  - `builtin_array_len` - line 47
  - `builtin_array_cap` - line 62
  - `builtin_array_new` - line 74
  - `builtin_array_push` - line 113
  - `builtin_array_pop` - line 206
  - `builtin_array_get` - line 248
  - `builtin_array_set` - line 267
  - `_str_array_header_ptr` - line 286
  - `builtin_str_array_new` - line 292
  - `builtin_str_array_len` - line 330
  - `builtin_str_array_push` - line 340
  - `builtin_str_array_get` - line 427
  - `builtin_str_array_join` - line 465
  - `builtin_dealloc_str_array` - line 629
  - `builtin_str_array_set` - line 677
  - `builtin_str_array_pop` - line 696

### source/codegen/builtin_misc.py  (358 lines)

- `class BuiltinMiscEmitter` - line 24
  - `__init__` - line 27
  - `__getattr__` - line 30
  - `builtin_fn_ptr` - line 33
  - `builtin_fn_call` - line 73
  - `builtin_fn_call_str` - line 129
  - `builtin_putc` - line 152
  - `builtin_print` - line 182
  - `_print_arg_value` - line 208
  - `_try_constant_print_line` - line 217
  - `_constant_print_text` - line 227
  - `_format_print_value` - line 245
  - `_format_int_for_print` - line 265
  - `_is_string_pointer` - line 297
  - `builtin_len` - line 305
  - `builtin_as_class` - line 332

### source/codegen/builtin_string.py  (749 lines)

- `class BuiltinStringEmitter` - line 26
  - `__init__` - line 29
  - `__getattr__` - line 32
  - `_emit_unchecked_char_load` - line 35
  - `builtin_char_at` - line 42
  - `builtin_unsafe_char_at` - line 117
  - `builtin_index_of` - line 128
  - `builtin_index_of_from` - line 157
  - `_index_result_from_ptr` - line 216
  - `builtin_substr` - line 230
  - `builtin_concat` - line 294
  - `builtin_ord` - line 328
  - `builtin_chr` - line 367
  - `builtin_strlen` - line 408
  - `_try_emit_cached_strlen` - line 425
  - `_try_emit_virtual_strlen` - line 467
  - `_str_arg_is_known_integer` - line 503
  - `_is_integer_type_name` - line 538
  - `builtin_str` - line 566
  - `builtin_startswith` - line 593
  - `builtin_endswith` - line 613
  - `builtin_str_replace` - line 662

### source/codegen/codegen.py  (549 lines)

- `class CodeGen : _CodeGenSupportMixin, _CodeGenModuleMixin, _CodeGenFunctionMixin, _CodeGenClassRecordMixin, _CodeGenBigIntFormatMixin, _CodeGenFunctionAnalysisMixin, _CodeGenOptimizerReportMixin` - line 32
  - `__init__` - line 61
  - `__getattr__` - line 410

### source/codegen/codegen_bigint_format_mixin.py  (162 lines)

- `class _CodeGenBigIntFormatMixin` - line 10
  - `bigint_to_hex_string` - line 11
  - `bigint_to_bin_string` - line 66
  - `bigint_to_oct_string` - line 113

### source/codegen/codegen_class_record_mixin.py  (202 lines)

- `def _is_string_type` - line 12
- `def _string_len_name` - line 16
- `class _CodeGenClassRecordMixin` - line 20
  - `__init__` - line 23
  - `generate_record` - line 39
  - `generate_class` - line 50
  - `_register_class_method_recursion` - line 77
  - `_generate_method` - line 116

### source/codegen/codegen_errors.py  (6 lines)

- `class CodeGenError : Exception` - line 4

### source/codegen/codegen_function_analysis_mixin.py  (335 lines)

- `class _CodeGenFunctionAnalysisMixin` - line 10
  - `_walk_ast_nodes` - line 11
  - `_find_recursive_functions` - line 28
  - `_find_recursion_guard_elisions` - line 58
  - `_can_elide_recursion_guard` - line 80
  - `_single_integer_param_name` - line 109
  - `_leading_base_case_upper` - line 138
  - `_base_case_upper_from_condition` - line 152
  - `_recursive_calls_decrease` - line 176
  - `_positive_param_decrement` - line 194
  - `_known_nonself_entry_upper` - line 210
  - `_int_literal` - line 240
  - `_node_calls_function` - line 247
  - `_analyze_param_mutations` - line 255
  - `_get_child_statements` - line 287
  - `_get_match_children` - line 315
  - `_get_try_except_children` - line 324

### source/codegen/codegen_function_mixin.py  (523 lines)

- `class _CodeGenFunctionMixin` - line 14
  - `__init__` - line 18
  - `_resolved_function_name` - line 45
  - `_record_source_location` - line 51
  - `_prepare_pending_di` - line 58
  - `_save_function_generation_state` - line 68
  - `_apply_function_decorators` - line 104
  - `_apply_auto_inline_heuristics` - line 127
  - `_initialize_function_context` - line 141
  - `_node_children` - line 172
  - `_walk_nodes` - line 184
  - `_expr_uses_var_stack_safely` - line 189
  - `_stmt_uses_var_stack_safely` - line 218
  - `_find_stack_class_locals` - line 244
  - `_create_entry_builder` - line 264
  - `_maybe_create_main_string_arena` - line 283
  - `_maybe_store_main_argv` - line 288
  - `_maybe_emit_function_entry_guards` - line 315
  - `_function_needs_recursion_guard` - line 324
  - `_can_seed_call_hint_ranges` - line 341
  - `_seed_call_hint_param_range` - line 351
  - `_declared_param_range` - line 378
  - `_bind_function_parameters` - line 398
  - `_emit_implicit_return_if_needed` - line 437
  - `_restore_function_generation_state` - line 460
  - `generate_function` - line 485
  - `generate_stmt` - line 516
  - `generate_expr` - line 520

### source/codegen/codegen_module_mixin.py  (763 lines)

- `class _CodeGenModuleMixin` - line 31
  - `__init__` - line 32
  - `_process_module_import` - line 36
  - `_generate_export_type` - line 54
  - `_collect_imported_functions` - line 76
  - `_register_type_aliases_from_nodes` - line 108
  - `_module_needs_string_arena` - line 114
  - `_collect_fn_ptr_references` - line 191
  - `_module_uses_argc_argv` - line 204
  - `generate` - line 211
  - `_collect_link_directives` - line 331
  - `_patch_personality_functions` - line 360
  - `_function_has_exception_handling` - line 374
  - `_strip_template_declares` - line 387
  - `declare_function` - line 418
  - `generate_global_var` - line 500
  - `_generate_global_array` - line 553
  - `generate_global_assign` - line 606
  - `generate_enum` - line 690
  - `_generate_data_enum` - line 706
  - `_type_size` - line 748

### source/codegen/codegen_optimizer_report_mixin.py  (43 lines)

- `class _CodeGenOptimizerReportMixin` - line 9
  - `_record_optimizer_decision` - line 10
  - `get_optimizer_report` - line 38

### source/codegen/codegen_support_mixin.py  (727 lines)

- `class _CodeGenSupportMixin` - line 36
  - `__init__` - line 37
  - `_get_free` - line 41
  - `generate_string_concat` - line 53
  - `create_string_constant` - line 93
  - `create_string_constant_gep` - line 112
  - `get_i64_to_cstr_func` - line 130
  - `get_i64_decimal_len_func` - line 244
  - `_print_bigint_dec` - line 300
  - `_register_std_module` - line 403
  - `_type_str_to_llvm` - line 422
  - `_declare_c_function` - line 444
  - `_process_use_statement` - line 466
  - `_process_ast_node` - line 488
  - `_process_template_block` - line 548
  - `_process_extern_fn` - line 569
  - `_process_extern_var` - line 591
  - `_process_extern_record` - line 599
  - `_process_union_def` - line 620
  - `_type_size_bits` *(static)* - line 643
  - `_compile_ast_template` - line 659
  - `_parse_template_func_sigs` - line 668

### source/codegen/collection_helpers.py  (736 lines)

- `class CollectionHelpers` - line 17
  - `__init__` - line 20
  - `__getattr__` - line 23
  - `get_channel_type` - line 26
  - `get_dict_type` - line 46
  - `_dict_field_ptr` - line 64
  - `_load_dict_fields` - line 78
  - `_emit_dict_key_search` - line 92
  - `_create_dict_key_lookup_func` - line 130
  - `_emit_dict_index_bounds` - line 168
  - `_create_dict_index_func` - line 186
  - `get_dict_create_func` - line 200
  - `get_dict_set_func` - line 274
  - `get_dict_get_type_func` - line 438
  - `get_dict_get_func` - line 494
  - `get_dict_has_key_func` - line 551
  - `get_dict_size_func` - line 581
  - `get_dict_key_at_func` - line 606
  - `get_dict_value_at_func` - line 640
  - `get_dict_remove_func` - line 667

### source/codegen/collection_helpers_types.py  (33 lines)

- `def get_channel_type` - line 8

### source/codegen/context_emitter.py  (102 lines)

- `class ContextEmitter` - line 10
  - `__init__` - line 13
  - `__getattr__` - line 16
  - `current_builder` - line 21
  - `current_function` - line 28
  - `alloca_in_entry_block` - line 34
  - `push_scope` - line 73
  - `pop_scope` - line 77
  - `register_for_cleanup` - line 91
  - `cleanup_all_scopes` - line 98

### source/codegen/control_flow_emitter.py  (158 lines)

- `class ControlFlowEmitter` - line 11
  - `__init__` - line 14
  - `__getattr__` - line 17
  - `_get_recursion_depth_global` - line 21
  - `_emit_recursion_check` - line 34
  - `_emit_recursion_decrement` - line 65
  - `_emit_synchronized_lock` - line 74

### source/codegen/debug_info.py  (194 lines)

- `class DebugInfoEmitter` - line 28
  - `__init__` - line 32
  - `__getattr__` - line 35
  - `_ensure_dwarf_module_flags` - line 40
  - `_get_di_file` - line 51
  - `_get_di_compile_unit` - line 75
  - `_get_di_subroutine_type` - line 100
  - `emit_dwarf_subprogram` - line 111
  - `_make_di_location` - line 152
  - `di_location_for_line` - line 171

### source/codegen/exception_emitter.py  (304 lines)

- `class ExceptionEmitter` - line 18
  - `__init__` - line 21
  - `__getattr__` - line 24
  - `_emit_safety_trap` - line 28
  - `_ensure_exc_globals` - line 66
  - `ensure_personality_function` - line 88
  - `call_or_invoke` - line 103
  - `generate_try_except` - line 126
  - `generate_throw` - line 262
  - `_error_type_hash` *(static)* - line 298

### source/codegen/fast_jit.py  (676 lines)

- `def _normalize_jit_opt` - line 34
- `def _write_ir_dump` - line 44
- `def create_execution_engine` - line 56
- `def _flush_c_stdout` - line 76
- `def _extract_result_int` - line 97
- `def _run_jit_once` - line 104
- `def _build_jit_callable` - line 160
- `def fast_jit_compile` - line 293
- `def _load_crt_library` - line 351
- `def _try_load_lib` - line 366
- `def _load_sqlite_library` - line 375
- `def fast_jit_repeat_file` - line 397
- `def _fast_jit_repeat_file_inprocess` - line 438
- `def jit_worker_cli` - line 576
- `def fast_jit_file` - line 610
- `def compile_to_ir_fast` - line 658

### source/codegen/fast_jit_runtime.py  (147 lines)

- `def install_profile_crash_atexit` - line 23
- `def print_jit_crash_banner` - line 51
- `def run_jit_main` - line 71

### source/codegen/fast_jit_unsafe_scan.py  (122 lines)

- `def scan_for_unsafe` - line 10
- `def _scan_node_for_unsafe` - line 16

### source/codegen/fast_jit_worker.py  (220 lines)

- `def _clamp_jit_opt` - line 16
- `def _is_packaged_runtime` - line 20
- `def _frozen_worker_entrypoint` - line 31
- `def _jit_worker_cmd` - line 53
- `def _checksum_from_worker_stdout` - line 98
- `def run_jit_worker_subprocess` - line 131

### source/codegen/memory_emitter.py  (106 lines)

- `class MemoryEmitter` - line 16
  - `__init__` - line 19
  - `__getattr__` - line 22
  - `checked_malloc` - line 25
  - `_checked_malloc_with_builder` - line 34
  - `string_alloc` - line 61

### source/codegen/monomorphize.py  (394 lines)

- `class MonomorphizationError : Exception` - line 26
- `def substitute_type` - line 30
- `def substitute_in_expr` - line 38
- `def substitute_in_stmt` - line 97
- `def monomorphize_record` - line 164
- `def monomorphize_class` - line 206
- `def monomorphize_function_body` - line 245
- `def monomorphize_generic_function` - line 284
- `class Monomorphizer` - line 342
  - `__init__` - line 345
  - `register_generic` - line 355
  - `instantiate` - line 360
  - `get_specialized_definitions` - line 391

### source/codegen/profiling_emitter.py  (102 lines)

- `class ProfilingEmitter` - line 23
  - `__init__` - line 26
  - `__getattr__` - line 29
  - `_get_prof_enter_func` - line 33
  - `_get_prof_exit_func` - line 43
  - `_get_prof_name_const` - line 53
  - `_is_profile_skipped` - line 75
  - `emit_profile_enter` - line 81
  - `emit_profile_exit` - line 92

### source/codegen/runtime_decls.py  (25 lines)

- `class RuntimeDecls : RuntimeDeclsStringMemMixin, RuntimeDeclsFileIOMixin, RuntimeDeclsThreadSyncMixin, RuntimeDeclsSqliteMathMixin, RuntimeDeclsBase` - line 17

### source/codegen/runtime_decls_base.py  (39 lines)

- `class RuntimeDeclsBase` - line 10
  - `__init__` - line 13
  - `__getattr__` - line 16
  - `_declare_external` - line 24

### source/codegen/runtime_decls_file_io.py  (118 lines)

- `class RuntimeDeclsFileIOMixin` - line 10
  - `get_fopen` - line 13
  - `get_fclose` - line 21
  - `get_fwrite` - line 29
  - `get_setvbuf` - line 40
  - `get_fread` - line 51
  - `get_fseek` - line 62
  - `get_ftell` - line 80
  - `get_fgets` - line 103
  - `get_fgetc` - line 111

### source/codegen/runtime_decls_sqlite_math.py  (312 lines)

- `class RuntimeDeclsSqliteMathMixin` - line 10
  - `get_sqlite3_open` - line 13
  - `get_sqlite3_open_v2` - line 25
  - `get_sqlite3_close` - line 38
  - `get_sqlite3_exec` - line 48
  - `get_sqlite3_errmsg` - line 61
  - `get_sqlite3_prepare_v2` - line 71
  - `get_sqlite3_step` - line 95
  - `get_sqlite3_reset` - line 108
  - `get_sqlite3_bind_int64` - line 121
  - `get_sqlite3_bind_text` - line 135
  - `get_sqlite3_bind_null` - line 150
  - `get_sqlite3_clear_bindings` - line 164
  - `get_sqlite3_column_int64` - line 176
  - `get_sqlite3_column_text` - line 194
  - `get_sqlite3_finalize` - line 212
  - `get_exp` - line 225
  - `get_log` - line 233
  - `get_sqrt` - line 241
  - `get_sin` - line 249
  - `get_cos` - line 257
  - `get_tan` - line 265
  - `get_tanh` - line 273
  - `get_pow` - line 281
  - `get_floor` - line 289
  - `get_ceil` - line 297
  - `get_fabs` - line 305

### source/codegen/runtime_decls_string_mem.py  (182 lines)

- `class RuntimeDeclsStringMemMixin` - line 11
  - `get_printf` - line 15
  - `get_puts` - line 23
  - `get_strlen` - line 31
  - `get_strcmp` - line 39
  - `get_sprintf` - line 47
  - `get_snprintf` - line 57
  - `get_malloc` - line 77
  - `get_strcpy` - line 86
  - `get_strcat` - line 94
  - `get_strdup` - line 102
  - `get_strncpy` - line 135
  - `get_memcpy` - line 146
  - `get_realloc` - line 154
  - `get_strstr` - line 162
  - `get_strncmp` - line 170

### source/codegen/runtime_decls_thread_sync.py  (324 lines)

- `class RuntimeDeclsThreadSyncMixin` - line 10
  - `get_pthread_create` - line 13
  - `get_pthread_join` - line 36
  - `get_create_thread` - line 53
  - `get_wait_for_single_object` - line 75
  - `get_close_handle` - line 88
  - `get_exit_code_thread` - line 98
  - `_get_or_declare_exit` - line 111
  - `get_exit_func` - line 118
  - `get_mutex_func` - line 122
  - `get_cond_func` - line 180
  - `get_rwlock_func` - line 249

### source/codegen/runtime_helpers.py  (240 lines)

- `class RuntimeHelpers` - line 15
  - `__init__` - line 18
  - `__getattr__` - line 21
  - `get_stream_file_global` - line 24
  - `get_stream_path_global` - line 35
  - `get_stream_write_func` - line 48
  - `get_stream_close_func` - line 146
  - `get_stdin` - line 187

### source/codegen/safety_arithmetic.py  (316 lines)

- `class SafetyArithmeticMixin` - line 10
  - `__getattr__` - line 11
  - `safe_add` - line 14
  - `_safe_add_intrinsic` - line 32
  - `_safe_add_manual` - line 75
  - `safe_sub` - line 115
  - `_safe_sub_intrinsic` - line 133
  - `_safe_sub_manual` - line 176
  - `safe_mul` - line 216
  - `_safe_mul_intrinsic` - line 234
  - `_safe_mul_manual` - line 272

### source/codegen/safety_emitter.py  (539 lines)

- `class SafetyEmitter : SafetyArithmeticMixin` - line 23
  - `__init__` - line 26
  - `__getattr__` - line 29
  - `is_unsigned_value` - line 32
  - `set_signedness` - line 46
  - `safe_division` - line 56
  - `safe_modulo` - line 131
  - `_proven_no_overflow_for_node` - line 190
  - `try_proven_int_arithmetic` - line 216
  - `try_proven_modulo` - line 271
  - `_try_single_subtract_modulo` - line 333
  - `_range_pair` - line 364
  - `try_proven_division` - line 369
  - `_emit_range_error` - line 421
  - `_emit_string_bounds_error` - line 437
  - `to_bool` - line 446
  - `cast_value` - line 471
  - `ensure_int64` - line 477
  - `default_value` - line 481
  - `check_bounds` - line 493
  - `check_bounds_dynamic` - line 498

### source/codegen/strlen_fact_cache.py  (85 lines)

- `def invalidate_strlen_facts` - line 16
- `def clear_strlen_facts` - line 25
- `def maybe_register_strlen_fact` - line 31
- `def register_strlen_fact` - line 50
- `def lookup_strlen_fact` - line 58
- `def register_value_strlen_fact` - line 71
- `def consume_value_strlen_fact` - line 79

### source/codegen/strlen_scalarization.py  (426 lines)

- `def _is_str_call` - line 14
- `def _is_baseconv_call` - line 21
- `def _is_read_file_call` - line 29
- `def _is_length_string_expr` - line 33
- `def collect_length_only_str_locals` - line 42
- `def _get_ctlz_i64` - line 208
- `def _emit_baseconv_len` - line 218
- `def _emit_read_file_len` - line 246
- `def try_emit_baseconv_strlen` - line 292
- `def _is_known_integer_expr` - line 301
- `def _literal_strlen` - line 309
- `def _add_lengths` - line 313
- `def _variable_string_type` - line 324
- `def _emit_variable_part_strlen` - line 340
- `def try_emit_known_string_length` - line 364
- `def try_emit_length_only_str_assignment` - line 416

### source/codegen/templates.py  (364 lines)

- `class TemplateError : Exception` - line 14
- `class TemplateBlock` - line 18
  - `__init__` - line 27
- `class TemplateCompiler` - line 37
  - `__init__` - line 42
  - `load_builtin_templates` - line 46
  - `compile_template` - line 154
  - `_strip_runtime_bloat` - line 263
  - `_extract_function_names` - line 328
  - `merge_ir` - line 341

### source/codegen/type_lowering.py  (310 lines)

- `class TypeLowering` - line 15
  - `__init__` - line 18
  - `__getattr__` - line 21
  - `get_type_size` - line 24
  - `_resolve_type_alias_spec` - line 28
  - `_callback_type_to_llvm` - line 47
  - `get_llvm_type` - line 53
  - `get_variable_class_type` - line 267
  - `get_record_name_from_type` - line 293
  - `get_field_info` - line 303

## compiler

### source/compiler/compiler.py  (197 lines)

- `def optimize_ir` - line 19
- `def compile_ail_file` - line 67
- `def compile_to_ir` - line 140
- `def jit_execute` - line 164

### source/compiler/modules.py  (370 lines)

- `class ModuleCache` - line 31
  - `__init__` - line 34
  - `_cache_key` *(static)* - line 40
  - `get` - line 44
  - `put` - line 47
  - `is_stale` - line 55
  - `invalidate` - line 68
  - `clear` - line 74
  - `is_loading` - line 80
  - `start_loading` - line 83
  - `finish_loading` - line 86
- `class Module` - line 90
  - `__init__` - line 93
  - `_extract_exports` - line 104
  - `get_export` - line 142
  - `get_all_exports` - line 146
- `def _has_link_directive` - line 151
- `class ModuleLoader` - line 162
  - `__init__` - line 165
  - `set_current_file` - line 170
  - `resolve_module_path` - line 174
  - `load_module` - line 230
  - `_load_file` - line 258
  - `process_imports` - line 303
- `def get_loader` - line 345
- `def set_search_paths` - line 352
- `def load_module` - line 357
- `def process_imports` - line 362

## diagnostics

### source/diagnostics/diagnostics.py  (303 lines)

- `class DiagnosticEngine` - line 44
  - `__init__` - line 49
  - `analyze` - line 54
- `def apply_fixes` - line 127
- `def fix_file` - line 160
- `def analyze_file` - line 188
- `def main` - line 197

### source/diagnostics/diagnostics_engine_checks.py  (681 lines)

- `def _check_unknown_identifiers` - line 63
- `def _check_patterns` - line 168
- `def _check_token_hints` - line 193
- `def _rhs_is_direct_string_literal` - line 227
- `def _check_dealloc_borrowed_strings` - line 249
- `def _check_division_by_zero` - line 345
- `def _check_unused_variables` - line 367
- `def _check_unused_globals` - line 412
- `def _check_dead_code` - line 482
- `def _check_infinite_loops` - line 569
- `def _check_concurrency_hints` - line 642

### source/diagnostics/diagnostics_engine_ffi_checks.py  (99 lines)

- `def _check_opaque_record_by_value_use` - line 12
- `def _collect_layoutless_c_record_names` - line 74

### source/diagnostics/diagnostics_engine_increment.py  (90 lines)

- `def _starts_statement` - line 18
- `def _ends_statement` - line 29
- `def _emit_increment_context_diagnostic` - line 40
- `def check_increment_decrement_statement_only` - line 60

### source/diagnostics/diagnostics_engine_symbols.py  (486 lines)

- `def _type_alias_symbol` - line 14
- `def _is_ident_type_name` - line 42
- `def _collect_symbols` - line 46
- `def _resolve_imports` - line 258
- `def _collect_cimport_symbols` - line 313
- `def _collect_symbols_from_file` - line 359

### source/diagnostics/diagnostics_engine_token_spans.py  (158 lines)

- `def ignored_declarative_token_indices` - line 19
- `def _looks_like_ui_block` - line 28
- `def _looks_like_ui_include` - line 45
- `def _ui_dsl_token_indices` - line 55
- `def _cabi_header_token_indices` - line 89
- `def _decorator_argument_token_indices` - line 128

### source/diagnostics/diagnostics_models.py  (51 lines)

- `class Fix` - line 8
  - `__init__` - line 11
  - `__str__` - line 16
- `class Diagnostic` - line 20
  - `__init__` - line 23
  - `__str__` - line 39

### source/diagnostics/diagnostics_utils.py  (80 lines)

- `def tokenize` - line 31
- `def levenshtein` - line 41
- `def find_closest` - line 63

### source/diagnostics/effect_policy.py  (307 lines)

- `class EffectViolation` - line 124
- `def parse_effect_decorators` - line 137
- `def collect_effect_policy_violations` - line 156
- `def violations_to_diagnostics` - line 177
- `def _collect_generic_fn_violations` - line 196
- `def _collect_fn_violations` - line 206
- `def _scan_function_body` - line 215
- `def _walk_nodes` - line 287

### source/diagnostics/static_analysis.py  (736 lines)

- `class StaticAnalyzer` - line 38
  - `__init__` - line 74
  - `analyze` - line 95
  - `_check_class_cleanup_contract` - line 125
  - `_extract_class_field_spec` - line 128
  - `_field_type_to_text` - line 131
  - `_looks_owned_resource_type` - line 134
  - `_collect_globals_and_functions` - line 137
  - `_collect_functions` - line 169
  - `_find_spawn_calls` - line 185
  - `_recurse_find_spawn` - line 210
  - `_analyze_node` - line 244
  - `_analyze_function` - line 255
  - `_analyze_statement` - line 282
  - `_analyze_if` - line 376
  - `_refine_from_condition` - line 413
  - `_check_null_access` - line 448
  - `_track_atomic_call` - line 523
  - `_expr_null_state` - line 577
  - `_best_line_for_var` - line 613
  - `_check_shared_variables` - line 627
- `def analyze_ast` - line 732

### source/diagnostics/static_analysis_class_cleanup.py  (254 lines)

- `def _check_class_cleanup_contract` - line 42
- `def _format_class_cleanup_field_preview` - line 128
- `def _destructor_touched_fields` - line 136
- `def _extract_class_field_spec` - line 205
- `def _field_type_to_text` - line 221
- `def _looks_owned_resource_type` - line 231

### source/diagnostics/static_analysis_models.py  (88 lines)

- `class NullState : Enum` - line 9
- `class AccessType : Enum` - line 17
- `class VariableAccess` - line 29
- `class AnalysisWarning` - line 40
  - `__str__` - line 50
- `class FunctionContext` - line 59
  - `set_null_state` - line 77
  - `get_null_state` - line 80
  - `is_concurrent` - line 83
  - `is_local_var` - line 86

### source/diagnostics/static_analysis_perf.py  (129 lines)

- `class _WarnCollector : Protocol` - line 40
- `def _self_concat_other` - line 44
- `def _looks_like_string` - line 53
- `def check_string_concat_loops` - line 65

### source/diagnostics/transpile_validator.py  (710 lines)

- `class TranspileTimeoutError : Exception` - line 41
- `def run_with_timeout` - line 45
- `class PythonAnalyzer` - line 69
  - `analyze` - line 72
  - `_is_method` - line 92
  - `_analyze_function` - line 101
  - `_analyze_class` - line 144
  - `_get_body_source` - line 183
  - `_hash_body` - line 190
- `class AILangAnalyzer` - line 198
  - `analyze` - line 209
  - `_extract_functions` - line 215
  - `_extract_records` - line 254
  - `_find_matching_end` - line 258
  - `_hash_body` - line 281
- `class TranspileValidator` - line 288
  - `__init__` - line 301
  - `log` - line 319
  - `validate_transpilation` - line 334
  - `_compare_functions` - line 422
  - `validate_file` - line 452
  - `validate_directory` - line 544
  - `_print_summary` - line 612
- `def validate_self` - line 630

### source/diagnostics/transpile_validator_models.py  (110 lines)

- `class Colors` - line 9
  - `disable` *(classmethod)* - line 23
- `class FunctionInfo` - line 37
- `class ClassInfo` - line 54
- `class TranspileResult` - line 66
  - `total_functions` - line 84
  - `match_percentage` - line 88
- `class ValidationReport` - line 95
  - `overall_match_rate` - line 106

## lexer

### source/lexer/scan.py  (733 lines)

- `def _first_chars_for_pattern` - line 350
- `def _build_dispatch` - line 390
- `def _match_ui_color_after_arrow` - line 424
- `def tokenize` - line 433
- `def _apply_contextual_keywords` - line 548
- `def unescape_string` - line 659
- `def char_literal_to_int` - line 698

### source/lexer/unicode_security.py  (36 lines)

- `def check_unicode_security` - line 24

## parser

### source/parser/ast_base.py  (77 lines)

- `def parsed_type_to_str` - line 16
- `class ASTNode` - line 52
  - `set_pos` - line 68

### source/parser/ast_decl_nodes.py  (663 lines)

- `class Function : ASTNode` - line 10
  - `__init__` - line 11
- `class Block : ASTNode` - line 33
  - `__init__` - line 36
- `class BlockCall : ASTNode` - line 41
  - `__init__` - line 44
- `class TemplateBlock : ASTNode` - line 57
  - `__init__` - line 60
- `class Match : ASTNode` - line 68
  - `__init__` - line 71
- `class MatchPattern : ASTNode` - line 82
  - `__init__` - line 85
- `class Cast : ASTNode` - line 96
  - `__init__` - line 99
- `class RecordDef : ASTNode` - line 107
  - `__init__` - line 110
- `class ExternRecordDef : ASTNode` - line 116
  - `__init__` - line 124
- `class EnumVariant : ASTNode` - line 150
  - `__init__` - line 156
  - `has_data` - line 168
- `class EnumDef : ASTNode` - line 173
  - `__init__` - line 185
  - `has_data_variants` - line 200
- `class EnumConstruct : ASTNode` - line 205
  - `__init__` - line 208
- `class EnumFieldAccess : ASTNode` - line 214
  - `__init__` - line 217
- `class ClassDef : ASTNode` - line 222
  - `__init__` - line 225
- `class NewExpr : ASTNode` - line 234
  - `__init__` - line 237
- `class FieldAccess : ASTNode` - line 242
  - `__init__` - line 245
- `class SafeFieldAccess : ASTNode` - line 250
  - `__init__` - line 253
- `class FieldAssign : ASTNode` - line 258
  - `__init__` - line 261
- `class MethodCall : ASTNode` - line 267
  - `__init__` - line 270
- `class ThisExpr : ASTNode` - line 278
- `class InlineAsm : ASTNode` - line 287
  - `__init__` - line 294
- `class GenericParam : ASTNode` - line 306
  - `__init__` - line 309
- `class GenericFunction : ASTNode` - line 317
  - `__init__` - line 320
- `class GenericRecord : ASTNode` - line 337
  - `__init__` - line 340
- `class GenericClass : ASTNode` - line 352
  - `__init__` - line 355
- `class GenericInstantiation : ASTNode` - line 369
  - `__init__` - line 372
- `class ComptimeExpr : ASTNode` - line 380
  - `__init__` - line 386
- `class ComptimeBlock : ASTNode` - line 390
  - `__init__` - line 396
- `class ComptimeIf : ASTNode` - line 400
  - `__init__` - line 405
- `class StaticAssert : ASTNode` - line 413
  - `__init__` - line 418
- `class CInclude : ASTNode` - line 423
  - `__init__` - line 430
- `class CImport : ASTNode` - line 447
  - `__init__` - line 456
- `class CAbiDefine : ASTNode` - line 471
  - `__init__` - line 474
- `class CAbiInclude : ASTNode` - line 479
  - `__init__` - line 482
- `class CAbiTypedef : ASTNode` - line 490
  - `__init__` - line 493
- `class CAbiField : ASTNode` - line 498
  - `__init__` - line 501
- `class CAbiStruct : ASTNode` - line 506
  - `__init__` - line 509
- `class CAbiPrototype : ASTNode` - line 514
  - `__init__` - line 517
- `class CAbiInlineFunction : ASTNode` - line 530
  - `__init__` - line 533
- `class CAbiConditional : ASTNode` - line 548
  - `__init__` - line 551
- `class CAbiMacro : ASTNode` - line 564
  - `__init__` - line 567
- `class CAbiHeader : ASTNode` - line 573
  - `__init__` - line 580
- `class ExternFn : ASTNode` - line 591
  - `__init__` - line 597
- `class LinkDirective : ASTNode` - line 611
  - `__init__` - line 618
- `class ExternVar : ASTNode` - line 633
  - `__init__` - line 638
- `class UnionDef : ASTNode` - line 644
  - `__init__` - line 649
- `class ReinterpretCast : ASTNode` - line 655
  - `__init__` - line 660

### source/parser/ast_expr_nodes.py  (251 lines)

- `class Import : ASTNode` - line 10
  - `__init__` - line 13
- `class FromImport : ASTNode` - line 24
  - `__init__` - line 27
- `class Use : ASTNode` - line 32
  - `__init__` - line 35
- `class Library : ASTNode` - line 42
  - `__init__` - line 45
- `class Number : ASTNode` - line 52
  - `__init__` - line 58
- `class Bool : ASTNode` - line 76
  - `__init__` - line 79
- `class Null : ASTNode` - line 83
- `class StringLit : ASTNode` - line 89
  - `__init__` - line 90
- `class InterpolatedString : ASTNode` - line 105
  - `__init__` - line 112
- `class ArrayLit : ASTNode` - line 116
  - `__init__` - line 117
- `class TupleLit : ASTNode` - line 121
  - `__init__` - line 124
- `class TupleAccess : ASTNode` - line 128
  - `__init__` - line 131
- `class ListComprehension : ASTNode` - line 136
  - `__init__` - line 139
- `class Range : ASTNode` - line 152
  - `__init__` - line 155
- `class DictLit : ASTNode` - line 161
  - `__init__` - line 164
- `class DictAccess : ASTNode` - line 168
  - `__init__` - line 171
- `class DictAssign : ASTNode` - line 176
  - `__init__` - line 179
- `class Variable : ASTNode` - line 191
  - `__init__` - line 192
- `class BinaryOp : ASTNode` - line 196
  - `__init__` - line 197
- `class UnaryOp : ASTNode` - line 203
  - `__init__` - line 204
- `class TernaryOp : ASTNode` - line 209
  - `__init__` - line 210
- `class Call : ASTNode` - line 216
  - `__init__` - line 217
- `class ArrayAccess : ASTNode` - line 225
  - `__init__` - line 226
- `class StringSlice : ASTNode` - line 234
  - `__init__` - line 240

### source/parser/ast_stmt_nodes.py  (353 lines)

- `class Return : ASTNode` - line 10
  - `__init__` - line 11
- `class Break : ASTNode` - line 15
- `class Continue : ASTNode` - line 18
- `class Assert : ASTNode` - line 21
  - `__init__` - line 27
- `class VarDecl : ASTNode` - line 32
  - `__init__` - line 33
- `class RangeType : ASTNode` - line 48
  - `__init__` - line 51
- `class TypeAlias : ASTNode` - line 57
  - `__init__` - line 60
- `class RangeVarDecl : ASTNode` - line 65
  - `__init__` - line 68
- `class Assign : ASTNode` - line 79
  - `__init__` - line 80
- `class TupleAssign : ASTNode` - line 85
  - `__init__` - line 88
- `class If : ASTNode` - line 96
  - `__init__` - line 97
- `class While : ASTNode` - line 105
  - `__init__` - line 106
- `class DoWhile : ASTNode` - line 117
  - `__init__` - line 124
- `class For : ASTNode` - line 135
  - `__init__` - line 136
- `class Loop : ASTNode` - line 151
  - `__init__` - line 152
- `class Foreach : ASTNode` - line 159
  - `__init__` - line 160
- `class Repeat : ASTNode` - line 173
  - `__init__` - line 174
- `class Spawn : ASTNode` - line 182
  - `__init__` - line 191
- `class Join : ASTNode` - line 197
  - `__init__` - line 203
- `class Await : ASTNode` - line 207
  - `__init__` - line 216
- `class AtomicOp : ASTNode` - line 220
  - `__init__` - line 231
- `class ChannelCreate : ASTNode` - line 244
  - `__init__` - line 252
- `class ChannelSend : ASTNode` - line 257
  - `__init__` - line 263
- `class ChannelRecv : ASTNode` - line 268
  - `__init__` - line 274
- `class ChannelTrySend : ASTNode` - line 278
  - `__init__` - line 281
- `class ChannelTryRecv : ASTNode` - line 286
  - `__init__` - line 289
- `class ChannelClose : ASTNode` - line 293
  - `__init__` - line 296
- `class TryExcept : ASTNode` - line 300
  - `__init__` - line 317
- `class Throw : ASTNode` - line 338
  - `__init__` - line 341

### source/parser/expression_parser.py  (80 lines)

- `class ExpressionParser` - line 45
  - `__init__` - line 48

### source/parser/naming.py  (31 lines)

- `def mangle_generic_name` - line 13

### source/parser/parser.py  (695 lines)

- `class Parser` - line 246
  - `__init__` - line 258
  - `_check_depth` - line 263
  - `_not_block_end` - line 274
  - `peek` - line 285
  - `peek_type` - line 291
  - `peek_text` - line 299
  - `peek_line` - line 307
  - `peek_col` - line 315
  - `_get_token_line` - line 323
  - `_get_token_col` - line 330
  - `consume` - line 337
  - `_consume_field_name` - line 466
  - `expect` - line 476
  - `error` - line 480
  - `skip_newlines` - line 488
  - `_is_type_ident` - line 494

### source/parser/parser_cabi_header_impl.py  (333 lines)

- `def parse_cabi_header` - line 22
- `def _parse_cabi_entries` - line 48
- `def _peek_cabi_keyword` - line 93
- `def _consume_abi_header_start` - line 99
- `def _consume_cabi_keyword` - line 105
- `def _consume_cabi_identifier` - line 114
- `def _token_text_until_line_end` - line 122
- `def _parse_cabi_define` - line 130
- `def _parse_cabi_include` - line 141
- `def _parse_cabi_typedef` - line 158
- `def _parse_cabi_struct` - line 169
- `def _parse_cabi_prototype` - line 189
- `def _parse_cabi_param_list` - line 197
- `def _parse_cabi_inline` - line 221
- `def _parse_cabi_conditional` - line 243
- `def _parse_cabi_macro` - line 273
- `def _consume_cabi_type_atom` - line 305
- `def _consume_cabi_type_until` - line 313

### source/parser/parser_control_flow_advanced_impl.py  (187 lines)

- `def _parse_match_pattern` - line 12
- `def _is_match_default` - line 21
- `def _consume_match_default` - line 32
- `def parse_match` - line 42
- `def parse_try` - line 91
- `def parse_throw` - line 159
- `def parse_asm` - line 179

### source/parser/parser_control_flow_impl.py  (647 lines)

- `def _is_elsif_token` - line 24
- `def _consume_elsif` - line 45
- `def _peek_next_type` - line 60
- `def _parse_statements_until` - line 67
- `def _parse_foreach_header` - line 78
- `def parse_if` - line 88
- `def parse_if_continuation` - line 126
- `def _parse_bounded_loop` - line 165
- `def _parse_auto_bound_loop` - line 197
- `def _extract_bound_from_condition` - line 232
- `def _is_max_keyword` - line 250
- `def _parse_inline_max` - line 255
- `def _finish_while_parse` - line 272
- `def _parse_while_with_bound` - line 294
- `def _parse_until_with_bound` - line 301
- `def _parse_for_with_bound` - line 309
- `def _parse_for_with_auto_bound` - line 314
- `def _parse_for_internal` - line 319
- `def _parse_loop_with_bound` - line 380
- `def _parse_foreach_with_bound` - line 402
- `def parse_while` - line 410
- `def parse_do_while` - line 436
- `def parse_unless` - line 464
- `def parse_until` - line 498
- `def parse_for` - line 526
- `def parse_loop` - line 580
- `def parse_foreach` - line 606
- `def parse_repeat` - line 614
- `def parse_spawn` - line 633

### source/parser/parser_declarations_class_impl.py  (229 lines)

- `def _parse_class_destructor` - line 12
- `def _parse_init_params` - line 32
- `def _parse_class_init` - line 52
- `def _parse_class_field` - line 91
- `def parse_class` - line 106
- `def _parse_visibility` - line 141
- `def _is_init_method` - line 152
- `def _parse_method` - line 162

### source/parser/parser_declarations_impl.py  (712 lines)

- `def _parse_decorators` - line 32
- `def _parse_generic_params` - line 85
- `def _parse_where_constraints` - line 134
- `def _parse_generic_args` - line 152
- `def _is_generic_call` - line 177
- `def _parse_generic_call` - line 204
- `def parse_function` - line 229
- `def _infer_string_types` - line 546
- `def parse_record` - line 605
- `def parse_opaque_record` - line 644
- `def parse_union` - line 668
- `def parse_template_block` - line 691

### source/parser/parser_enum_impl.py  (75 lines)

- `def parse_enum` - line 6

### source/parser/parser_expression_callable_impl.py  (170 lines)

- `def _parse_callable_primary` - line 26

### source/parser/parser_expression_impl.py  (669 lines)

- `def parse_expression` - line 33
- `def parse_ternary` - line 43
- `def parse_logical_or` - line 57
- `def parse_logical_and` - line 69
- `def parse_bitwise_or` - line 81
- `def parse_bitwise_xor` - line 97
- `def parse_bitwise_and` - line 113
- `def parse_equality` - line 133
- `def parse_comparison` - line 152
- `def parse_shift` - line 164
- `def parse_range` - line 188
- `def parse_term` - line 206
- `def parse_factor` - line 218
- `def parse_power` - line 230
- `def parse_unary` - line 243
- `def parse_primary` - line 270
- `def _parse_this_primary` - line 338
- `def _parse_paren_or_cast` - line 356
- `def _parse_number_literal` - line 416
- `def _parse_bool_literal` - line 425
- `def _parse_char_literal` - line 431
- `def _parse_heredoc` - line 443
- `def _parse_interpolated_string` - line 457
- `def _parse_array_literal` - line 511
- `def _parse_dict_literal` - line 547
- `def _parse_dict_entry` - line 562
- `def _parse_arg_list` - line 570
- `def _parse_arg_list_simple` - line 598
- `def _parse_postfix_ops` - line 604

### source/parser/parser_internal_abi_impl.py  (193 lines)

- `def _is_internal_keyword` - line 43
- `def _parse_internal_abi_type_after_keyword` - line 47
- `def _parse_internal_abi_type` - line 74
- `def _c_abi_for_ailang_type` - line 81
- `def _parse_internal_param` - line 106
- `def _parse_internal_function` - line 127

### source/parser/parser_module_decls.py  (499 lines)

- `def parse_use` - line 24
- `def _consume_module_name_part` - line 36
- `def _parse_single_use` - line 46
- `def _parse_use_block` - line 69
- `def parse_import` - line 83
- `def _parse_single_import` - line 93
- `def _parse_optional_import_target` - line 110
- `def _parse_import_block` - line 139
- `def parse_from_import` - line 156
- `def _looks_like_inverse_from_import` - line 176
- `def _parse_inverse_from_import_groups` - line 191
- `def parse_library_decl` - line 218
- `def parse_cinclude` - line 228
- `def parse_link_directive` - line 264
- `def parse_cimport` - line 279
- `def _split_directive_target` - line 292
- `def _parse_extern_decl` - line 306
- `def parse_extern_var` - line 318
- `def parse_extern_record` - line 333
- `def _consume_layout_int` - line 417
- `def _consume_extern_symbol_name` - line 422
- `def parse_extern_fn` - line 433

### source/parser/parser_program_impl.py  (450 lines)

- `def _parse_import_statement` - line 18
- `def _is_ui_block` - line 61
- `def _is_ui_include` - line 81
- `def _skip_ui_include` - line 91
- `def _skip_ui_block` - line 104
- `def _parse_definition` - line 121
- `def parse_program` - line 270
- `def _parse_program_impl` - line 285
- `def _parse_global_var` - line 325
- `def _parse_bare_global_const` - line 364
- `def _parse_type_alias_target` - line 405
- `def _parse_type_alias` - line 419

### source/parser/parser_statements_ident_impl.py  (78 lines)

- `def _parse_keyword_as_ident_stmt` - line 10
- `def _parse_ident_stmt` - line 18

### source/parser/parser_statements_impl.py  (739 lines)

- `def _parse_reinterpret_cast` - line 35
- `def _parse_prefix_increment_stmt` - line 53
- `def _parse_return_stmt` - line 73
- `def _parse_break_stmt` - line 92
- `def _parse_continue_stmt` - line 99
- `def _parse_assert_stmt` - line 106
- `def _parse_comptime` - line 120
- `def _parse_static_assert` - line 179
- `def _is_statement_start` - line 198
- `def _parse_print_stmt` - line 254
- `def _parse_typed_var_decl` - line 279
- `def _lookahead_for_assign` - line 303
- `def _lookahead_is_custom_type_decl` - line 311
- `def _parse_tuple_assign` - line 336
- `def _parse_dot_access_stmt` - line 360
- `def _parse_block` - line 424
- `def _parse_subscript_stmt` - line 452
- `def parse_statement` - line 576
- `def _parse_statement_impl` - line 596
- `def _wrap_postfix_conditional` - line 684

### source/parser/parser_statements_object_impl.py  (51 lines)

- `def parse_new` - line 8
- `def _parse_this_stmt` - line 25

### source/parser/parser_statements_range_impl.py  (65 lines)

- `def _lookahead_is_range_decl` - line 10
- `def _parse_range_var_decl` - line 25
- `def _parse_range_bound` - line 49

### source/parser/parser_type_parsing.py  (584 lines)

- `def _parse_single_param` - line 11
- `def _parse_type_name` - line 180
- `def _is_type_token` - line 201
- `def parse_type` - line 260

## pgo

### source/pgo/c_backend.py  (24 lines)

- `def c_pgo_compile_flags` - line 8

### source/pgo/llvm_ir.py  (269 lines)

- `class LLVMProfileMergeError : RuntimeError` - line 18
- `class LLVMPGOProbeResult` - line 23
  - `to_json` - line 36
- `def _resolve_tool` - line 40
- `def default_ailang_clang_target` - line 44
- `def _target_args` - line 51
- `def _run` - line 55
- `def merge_llvm_profraw` - line 72
- `def merge_llvm_profraw_with_tool` - line 78
- `def llvm_pgo_generate_flags` - line 101
- `def llvm_pgo_use_flags` - line 108
- `def llvm_pgo_use_flags_with_tool` - line 115
- `def _write_probe_ir` - line 131
- `def llvm_pgo_probe` - line 138

### source/pgo/llvm_toolchain.py  (105 lines)

- `def _exe_name` - line 11
- `def _env_path` - line 17
- `def _bin_dir` - line 22
- `def _append_existing_unique` - line 28
- `def _windows_system_drive_root` - line 38
- `def _windows_env_llvm_dirs` - line 47
- `def preferred_llvm_bin_dirs` - line 68
- `def resolve_llvm_tool` - line 79
- `def llvm_toolchain_root_for` - line 89
- `def same_llvm_root_tool` - line 96

### source/pgo/paths.py  (28 lines)

- `def sanitize_stem` - line 10
- `def source_identity_tag` - line 16
- `def default_pgo_output_dir` - line 23

## runtime

### source/runtime/arena.py  (551 lines)

- `class ArenaGenerator` - line 57
  - `__init__` - line 72
  - `arena_type` - line 77
  - `_get_malloc` - line 84
  - `_get_free` - line 88
  - `_store_field` - line 92
  - `_load_field` - line 103
  - `create_arena` - line 114
  - `arena_alloc` - line 182
  - `_alloc_new_chunk` - line 253
  - `arena_reset` - line 384
  - `arena_destroy` - line 427
  - `_free_chunk_chain` - line 447
  - `arena_used` - line 490
  - `arena_remaining` - line 524

### source/runtime/modes.py  (114 lines)

- `class CompilationMode : Enum` - line 10
- `class ModeConfig : NamedTuple` - line 17
- `class CompilationContext` - line 55
  - `set_mode` *(classmethod)* - line 63
  - `set_jit` *(classmethod)* - line 69
  - `is_jit` *(classmethod)* - line 74
  - `get_mode` *(classmethod)* - line 79
  - `get_config` *(classmethod)* - line 84
  - `is_freestanding` *(classmethod)* - line 89
  - `has_feature` *(classmethod)* - line 94
  - `require_feature` *(classmethod)* - line 102

### source/runtime/phases.py  (132 lines)

- `class _PhaseRecord` - line 34
- `class PhaseProfile` - line 40
  - `__init__` - line 48
  - `enter` - line 52
  - `exit` - line 55
  - `report` - line 63
- `def get_profile` - line 93
- `def enable_profiling` - line 98
- `def disable_profiling` - line 105
- `class Phase` - line 111
  - `__init__` - line 121
  - `__enter__` - line 124
  - `__exit__` - line 129

### source/runtime/profiler.py  (458 lines)

- `class _State` - line 42
  - `__init__` - line 45
- `def reset` - line 82
- `def install` - line 90
- `def jit_symbols` - line 108
- `def is_enabled` - line 129
- `def set_source_map` - line 134
- `def _on_enter` - line 148
- `def _on_exit` - line 158
- `def compute_blame` - line 177
- `def crash_frames` - line 218
- `def _fmt_ns` - line 232
- `def _fmt_location` - line 243
- `def source_map` - line 263
- `def format_blame` - line 268
- `def format_crash_frames` - line 298
- `def format_folded_stacks` - line 315
- `def write_folded_stacks` - line 355
- `def _sampler_loop` - line 381
- `def start_sampling` - line 399
- `def stop_sampling` - line 411
- `def is_sampling` - line 422
- `def format_sample_hotspots` - line 427

### source/runtime/stdlib.py  (411 lines)

- `class StdFunction` - line 16
- `def get_std_module` - line 382
- `def is_std_module` - line 387
- `def get_std_function` - line 392
- `def list_std_modules` - line 400
- `def list_std_functions` - line 405

### source/runtime/unsafe_registry.py  (185 lines)

- `class UnsafeMode : Enum` - line 13
- `class UnsafeOperation` - line 23
- `class UnsafeRegistry` - line 32
  - `__init__` - line 48
  - `register` - line 53
  - `prompt_all` - line 57
  - `_prompt_interactive` - line 102
  - `_get_warning_for_operation` - line 133
  - `has_unsafe` - line 149
  - `clear` - line 153
- `class _RegistryHolder` - line 159
- `def get_registry` - line 165
- `def set_registry` - line 172
- `def register_unsafe` - line 177
- `def prompt_unsafe` - line 182

## tools

### source/tools/repl.py  (169 lines)

- `class REPL` - line 11
  - `__init__` - line 12
  - `run` - line 17
  - `_update_block_depth` - line 65
  - `execute` - line 84
  - `show_help` - line 142

### source/tools/self_host_analysis.py  (237 lines)

- `class DependencyAnalysis` - line 20
- `def analyze_imports` - line 59
- `def analyze_llvm_usage` - line 87
- `def analyze_file` - line 108
- `def analyze_ailang_codebase` - line 137
- `def print_report` - line 154

### source/tools/transpile.py  (714 lines)

- `class InferredType` - line 87
  - `__str__` - line 94
- `class TypeInferer` - line 98
  - `__init__` - line 128
  - `infer_from_assignment` - line 133
  - `infer_param_from_field` - line 143
  - `infer_return_type` - line 148
  - `infer_literal_type` - line 166
- `class PythonToAILang` - line 179
  - `__init__` - line 232
  - `_safe_name` - line 237
  - `transpile` - line 243
  - `_indent` - line 248
  - `_visit` - line 251
  - `_generic_visit` - line 256
- `class AILangToPython` - line 466
  - `__init__` - line 477
  - `transpile` - line 485
  - `_analyze_types` - line 492
  - `_generate_python` - line 506
  - `_add_param_types` - line 616
- `def python_to_ailang` - line 643
- `def ailang_to_python` - line 649
- `class BidirectionalCode` - line 660
  - `__init__` - line 665
  - `python` - line 670
  - `ailang` - line 675
  - `from_ailang` *(classmethod)* - line 682
  - `save_python` - line 689
  - `save_ailang` - line 694
- `def bidirectional` - line 700

### source/tools/transpile_py2ai_control_expr.py  (485 lines)

- `def _visit_If` - line 10
- `def _visit_While` - line 48
- `def _visit_For` - line 60
- `def _visit_Expr` - line 75
- `def _visit_Pass` - line 79
- `def _visit_Break` - line 83
- `def _visit_Continue` - line 87
- `def _visit_Raise` - line 91
- `def _visit_Try` - line 102
- `def _visit_With` - line 161
- `def _visit_Assert` - line 183
- `def _visit_Global` - line 192
- `def _visit_Nonlocal` - line 197
- `def _visit_Lambda` - line 202
- `def _visit_Name` - line 210
- `def _visit_Constant` - line 221
- `def _visit_JoinedStr` - line 234
- `def _visit_Attribute` - line 260
- `def _visit_Subscript` - line 265
- `def _visit_Slice` - line 269
- `def _visit_IfExp` - line 279
- `def _visit_Set` - line 294
- `def _visit_NamedExpr` - line 300
- `def _visit_Starred` - line 308
- `def _visit_Call` - line 313
- `def _visit_ListComp` - line 345
- `def _visit_DictComp` - line 361
- `def _visit_GeneratorExp` - line 377
- `def _visit_BinOp` - line 392
- `def _visit_UnaryOp` - line 400
- `def _visit_BoolOp` - line 411
- `def _visit_Compare` - line 425
- `def _visit_List` - line 432
- `def _visit_Dict` - line 437
- `def _visit_Tuple` - line 448
- `def _binop_symbol` - line 453
- `def _cmpop_symbol` - line 471

### source/tools/transpile_py2ai_declarations.py  (493 lines)

- `def _get_type_name` - line 10
- `def _visit_Module` - line 37
- `def _visit_Import` - line 86
- `def _visit_ImportFrom` - line 104
- `def _visit_ClassDef` - line 119
- `def _get_default_for_type` - line 231
- `def _is_simple_init` - line 244
- `def _has_complex_expr` - line 287
- `def _visit_init_method` - line 305
- `def _find_field_assignments` - line 366
- `def _visit_FunctionDef` - line 394
- `def _visit_AnnAssign` - line 441
- `def _visit_Assign` - line 456
- `def _visit_AugAssign` - line 481
- `def _visit_Return` - line 489

## transpiler

### source/transpiler/arithmetic_literal_proofs.py  (127 lines)

- `def int_literal_value` - line 15
- `def positive_int_literal` - line 44
- `def shift_amount_literal_in_range` - line 55
- `def int_literal_in_range` - line 63
- `def int_literal_equals` - line 71
- `def neutral_int_arithmetic_safe` - line 77
- `def literal_int_arithmetic_safe` - line 99

### source/transpiler/array_literal_hints.py  (58 lines)

- `def _function_scope` - line 12
- `def update_array_literal_hints` - line 19
- `def get_array_literal_values` - line 36
- `def _literal_int_values` - line 49

### source/transpiler/cbind_flags.py  (34 lines)

- `def headers_from_cflags` - line 6

### source/transpiler/class_field_ownership.py  (182 lines)

- `def owned_field_flag_name` - line 19
- `def owned_param_flag_name` - line 24
- `def string_len_field_name` - line 29
- `def string_len_param_name` - line 34
- `def is_string_type` - line 39
- `def field_type_text` - line 44
- `def normalized_type_text` - line 49
- `def auto_owned_field_kind` - line 54
- `def is_auto_owned_field_type` - line 67
- `def is_auto_owned_string_field_type` - line 75
- `def is_auto_owned_param` - line 80
- `def is_auto_owned_string_param` - line 92
- `def param_name` - line 97
- `def auto_owned_fields` - line 104
- `def auto_owned_field_names` - line 123
- `def auto_owned_string_fields` - line 131
- `def auto_owned_string_field_names` - line 140
- `def _call_name` - line 145
- `def _same_field_access` - line 149
- `def expr_produces_owned_value` - line 161
- `def expr_preserves_field_storage` - line 174

### source/transpiler/codegen_int_ranges.py  (690 lines)

- `class RangeSnapshot` - line 16
- `def _literal_key` - line 23
- `def _range_add` - line 29
- `def _range_sub` - line 33
- `def _range_mul` - line 37
- `def range_fits_int64` - line 47
- `def range_fits_signed_width` - line 51
- `def range_is_positive` - line 59
- `def clear_codegen_int_proofs` - line 63
- `def expr_contains_call` - line 69
- `def call_preserves_local_int_proofs` - line 77
- `def expr_invalidates_local_int_proofs` - line 96
- `def _value_invalidates_local_int_proofs` - line 106
- `def _value_contains_call` - line 122
- `def _parse_c_int_literal` - line 136
- `def _decimal_len_range` - line 148
- `def _single_call_arg` - line 160
- `def expr_string_length_range` - line 168
- `def expr_int_range` - line 205
- `def range_assignment_proven` - line 244
- `def _fixed_dict_range` - line 256
- `def _array_access_range` - line 263
- `def _interval_to_range` - line 303
- `def remember_assign_range` - line 311
- `def remember_string_length_range` - line 324
- `def remember_field_assign_range` - line 334
- `def remember_fixed_dict_range` - line 349
- `def clear_loop_variant_ranges` - line 364
- `def prepare_while_loop_ranges` - line 368
- `def snapshot_codegen_ranges` - line 375
- `def restore_codegen_ranges` - line 385
- `def merge_codegen_ranges` - line 394
- `def _join_range_map` - line 411
- `def _join_fixed_dict_ranges` - line 424
- `def _apply_post_if_refinements` - line 438
- `def _apply_exiting_guard_refinement` - line 456
- `def _body_exits_current_path` - line 472
- `def _false_eq_refinement` - line 478
- `def _declared_range_var_bounds` - line 508
- `def _clamp_if_pattern` - line 521
- `def _clear_loop_variant_ranges` - line 556
- `def _assigned_vars` - line 573
- `def _field_key` - line 606
- `def _clear_field_ranges_for_var` - line 612
- `def _remember_record_init_ranges` - line 620
- `def _merge_loop_field_ranges` - line 635
- `def _assigned_field_exprs` - line 658

### source/transpiler/codegen_loop_range_proofs.py  (382 lines)

- `def derive_counted_loop_ranges` - line 19
- `def _derive_counted_loop_ranges` - line 23
- `def _loop_clamped_accumulator_ranges` - line 81
- `def _while_counter_bound` - line 124
- `def _top_level_counter_step` - line 146
- `def _counter_delta` - line 161
- `def _loop_accumulator_budget` - line 172
- `def _simulate_local_decl_range` - line 241
- `def _while_accumulator_budget` - line 255
- `def _exact_indexed_reduction_budget` - line 289
- `def _exact_indexed_reduction_details` - line 296
- `def _simulate_field_assign_range` - line 334
- `def _self_accumulator_terms` - line 355
- `def _flatten_add` - line 367
- `def _expr_int_range_with_fields` - line 373

### source/transpiler/control_loop_utils.py  (40 lines)

- `def close_streams_if_outer_loop` - line 8
- `def setup_loop_bound` - line 14
- `def and_loop_bound` - line 22
- `def increment_loop_bound` - line 32

### source/transpiler/core.py  (563 lines)

- `class CTranspiler : _CTranspilerStateAliasMixin, _CTranspilerTypeStateMixin, _CTranspilerCleanupReportMixin, _CTranspilerOptimizerReportMixin, _CTranspilerTypeLoweringMixin, _CTranspilerEmitDriverMixin` - line 38
  - `__init__` - line 159
  - `__getattr__` - line 328
- `def transpile_file` - line 507
- `def main` - line 537

### source/transpiler/core_cleanup_reports.py  (522 lines)

- `class _CTranspilerCleanupReportMixin` - line 22
  - `__init__` - line 23
  - `_is_string_expr_for_scan` - line 31
  - `_might_be_string_static` - line 34
  - `_might_be_string` - line 39
  - `_can_elide_binary_safety` - line 42
  - `_why_binary_safety_not_elided` - line 47
  - `_binary_safety_decision` - line 53
  - `_division_safety_decision` - line 58
  - `_modulo_safety_decision` - line 70
  - `_record_check_decision` - line 82
  - `get_check_report` - line 107
  - `_record_format_decision` - line 114
  - `get_format_report` - line 142
  - `_field_ailang_type` - line 149
  - `_class_ptr_type` - line 154
  - `_is_owned_string_alloc` - line 157
  - `_user_fn_call_is_non_capturing` - line 160
  - `_collect_string_locals` - line 163
  - `_collect_mixed_ownership_string_locals` - line 166
  - `_collect_array_locals` - line 173
  - `_collect_with_owning` - line 178
  - `_collect_class_locals` - line 188
  - `_detect_escaping_class_locals` - line 193
  - `_detect_escaping_locals` - line 202
  - `_mixed_owned_flag` - line 209
  - `_auto_owned_string_field_names` - line 214
  - `_auto_owned_field_names` - line 218
  - `_auto_owned_field_kind` - line 222
  - `_auto_owned_param_entries` - line 226
  - `_class_field_owned_flag` - line 230
  - `_expr_produces_owned_value` - line 234
  - `_owned_value_cleanup_lines` - line 249
  - `_owned_field_cleanup_lines` - line 281
  - `_emit_owned_field_cleanup` - line 300
  - `_emit_owned_param_cleanup` - line 305
  - `_emit_owned_string_param_cleanup` - line 324
  - `_has_any_cleanup` - line 330
  - `_emit_class_cleanup` - line 362
  - `_emit_cleanup_list` - line 429
  - `_count_var_reads` - line 441

### source/transpiler/core_emit_driver.py  (386 lines)

- `class _CTranspilerEmitDriverMixin` - line 12
  - `__init__` - line 13
  - `_format_method_param` - line 32
  - `_default_mangle_name` - line 47
  - `_mangle_name` - line 53
  - `_mangle_var` - line 60
  - `emit` - line 66
  - `emit_raw` - line 70
  - `transpile` - line 74
  - `_postprocess_unused_static` - line 254
  - `_emit_fn_call` *(static)* - line 282
  - `_emit_typed_fn_ptr` - line 289
  - `_emit_typed_fn_call` - line 298
  - `_extern_record_layout` - line 318
  - `_emit_sizeof` - line 327
  - `_emit_alignof` - line 346
  - `_emit_offsetof` - line 364

### source/transpiler/core_optimizer_reports.py  (50 lines)

- `class _CTranspilerOptimizerReportMixin` - line 9
  - `_record_optimizer_decision` - line 10
  - `get_optimizer_report` - line 39
  - `_class_locals_constructed_by_new` - line 46

### source/transpiler/core_state_aliases.py  (131 lines)

- `class _CTranspilerStateAliasMixin` - line 11
  - `used_helpers` - line 13
  - `used_helpers` - line 17
  - `_spawn_targets` - line 21
  - `_spawn_targets` - line 25
  - `_needs_arrays` - line 29
  - `_needs_arrays` - line 33
  - `_needs_dicts` - line 37
  - `_needs_dicts` - line 41
  - `_needs_dynamic_arrays` - line 45
  - `_needs_dynamic_arrays` - line 49
  - `_needs_threading` - line 53
  - `_needs_threading` - line 57
  - `_needs_atomics` - line 61
  - `_needs_atomics` - line 65
  - `_needs_channels` - line 69
  - `_needs_channels` - line 73
  - `_needs_inline_asm` - line 77
  - `_needs_inline_asm` - line 81
  - `_needs_sync` - line 85
  - `_needs_sync` - line 89
  - `_needs_exceptions` - line 93
  - `_needs_exceptions` - line 97
  - `_needs_stream_cleanup` - line 101
  - `_needs_stream_cleanup` - line 105
  - `records` - line 109
  - `records` - line 113
  - `unions` - line 117
  - `unions` - line 121
  - `enums` - line 125
  - `enums` - line 129

### source/transpiler/core_type_lowering.py  (552 lines)

- `class _CTranspilerTypeLoweringMixin` - line 17
  - `_resolve_type_alias_spec` - line 18
  - `_looks_like_c_type` - line 45
  - `_parse_fixed_array_type_spec` - line 63
  - `_format_c_declaration` - line 69
  - `_format_c_param_declaration` - line 81
  - `_ailang_type_to_c` - line 107
  - `_function_body_has_value_return` - line 230
  - `_get_return_type` - line 280
  - `_format_params` - line 294
  - `visit` - line 319
  - `expr` - line 331
  - `_infer_assign_type` - line 338
  - `_collect_var_in_stmt` - line 348
  - `_collect_vars_in_body` - line 439
  - `_collect_globally_used_names` - line 446
  - `_collect_used_names_in_body` - line 473
  - `_collect_used_names_in_nodes` - line 479
  - `_collect_used_names_in_node` - line 486

### source/transpiler/core_type_state.py  (138 lines)

- `class _CTranspilerTypeStateMixin` - line 12
  - `classes` - line 14
  - `classes` - line 18
  - `functions` - line 24
  - `functions` - line 28
  - `data_enums` - line 32
  - `data_enums` - line 36
  - `_type_decorators` - line 42
  - `_type_decorators` - line 46
  - `_func_defaults` - line 50
  - `_func_defaults` - line 54
  - `_string_vars` - line 60
  - `_string_vars` - line 64
  - `_vec256_vars` - line 68
  - `_vec256_vars` - line 72
  - `_vec512_vars` - line 76
  - `_vec512_vars` - line 80
  - `_array_vars` - line 84
  - `_array_vars` - line 88
  - `_dict_vars` - line 92
  - `_dict_vars` - line 96
  - `_dyn_array_vars` - line 100
  - `_dyn_array_vars` - line 104
  - `_enum_vars` - line 108
  - `_enum_vars` - line 112
  - `_var_types` - line 116
  - `_var_types` - line 120
  - `_single_use_owned_strings` - line 124
  - `_single_use_owned_strings` - line 128
  - `_recursive_funcs` - line 132
  - `_recursive_funcs` - line 136

### source/transpiler/dict_specialization.py  (199 lines)

- `def _dict_stack_capacity` - line 9
- `def dict_literal_stack_capacity` - line 16
- `def _hash_literal_key` - line 20
- `def _literal_key` - line 29
- `def _literal_dict_slots` - line 35
- `def fixed_dict_literal_slots` - line 55

### source/transpiler/drop_plan.py  (330 lines)

- `class DropKind : str, Enum` - line 20
- `class DropFieldPlan` - line 30
- `class DropPlan` - line 37
  - `field_names` - line 43
- `def field_type_text` - line 50
- `def normalized_type_text` - line 58
- `def _coerce_kind` - line 63
- `def drop_kind_for_type` - line 74
- `def auto_owned_fields` - line 95
- `def declared_field_plans` - line 114
- `def _default_owned_string_alloc` - line 127
- `def _call_name` - line 143
- `def _same_field_access` - line 147
- `def expr_produces_owned_value` - line 159
- `def expr_preserves_field_storage` - line 199
- `def constructor_field_drop_plan` - line 221
- `def _plan_from_owned_names` - line 316

### source/transpiler/emit_expressions.py  (118 lines)

- `class ExprGenerator : _SimdBuiltinsMixin` - line 33
  - `__init__` - line 40
  - `builder` - line 73
  - `function` - line 77
  - `__getattr__` - line 80
  - `generate_expr` - line 108
  - `generic_visit` - line 116

### source/transpiler/emit_statements.py  (144 lines)

- `class StmtGenerator` - line 68
  - `__init__` - line 69
  - `builder` - line 77
  - `func` - line 81
  - `generate_stmt` - line 84
  - `generic_visit` - line 99

### source/transpiler/emit_statements_basic.py  (1022 lines)

- `def _remember_local_constant` - line 60
- `def _forget_local_constant` - line 70
- `def visit_Return` - line 76
- `def visit_Break` - line 155
- `def visit_Continue` - line 165
- `def _cleanup_current_loop_stack_class_locals` - line 175
- `def _cleanup_all_stack_class_locals` - line 185
- `def visit_Assert` - line 198
- `def visit_InlineAsm` - line 235
- `def visit_ComptimeExpr` - line 246
- `def visit_ComptimeBlock` - line 267
- `def visit_ComptimeIf` - line 276
- `def visit_StaticAssert` - line 297
- `def visit_Call` - line 309
- `def _evaluate_comptime` - line 329
- `def visit_VarDecl` - line 405
- `def _fixed_array_decl_spec` - line 522
- `def _is_slice_or_view_type` - line 542
- `def _try_emit_fixed_array_slice_alias` - line 549
- `def visit_RangeVarDecl` - line 594
- `def _emit_range_check` - line 645
- `def _int_number_value` - line 672
- `def _range_bounds` - line 678
- `def _can_elide_range_check_for_expr` - line 686
- `def _can_elide_range_check_for_bounds` - line 697
- `def _llvm_const_int` - line 725
- `def visit_TypeAlias` - line 732
- `def _infer_decl_type_from_expr` - line 737
- `def visit_Assign` - line 755
- `def _try_emit_record_new_assign` - line 876
- `def _try_emit_record_new_into_slot` - line 910
- `def _store_record_string_len` - line 953
- `def _is_string_type_name` - line 979
- `def visit_TupleAssign` - line 983
- `def visit_BlockCall` - line 1012

### source/transpiler/emit_statements_block_each.py  (77 lines)

- `def _block_each` - line 12

### source/transpiler/emit_statements_cleanup.py  (69 lines)

- `def _emit_stack_class_cleanup` - line 8

### source/transpiler/emit_statements_common.py  (6 lines)

- `class StmtGenError : Exception` - line 4

### source/transpiler/emit_statements_control_data.py  (762 lines)

- `def _is_string_type` - line 54
- `def _same_object_expr` - line 58
- `def _clear_local_constants` - line 66
- `def _forget_loop_local_constants` - line 70
- `def _try_emit_field_array_push_in_place` - line 74
- `def _cleanup_immediate_stack_class_locals` - line 162
- `def _push_loop_stack_class_cleanup` - line 166
- `def _pop_loop_stack_class_cleanup` - line 170
- `def _cleanup_current_loop_stack_class_locals` - line 175
- `def _block_times` - line 183
- `def visit_FieldAssign` - line 232
- `def visit_DictAssign` - line 291
- `def visit_If` - line 372
- `def _enter_loop` - line 408
- `def _leave_loop` - line 415
- `def _branch_on_loop_condition` - line 425
- `def _emit_loop_body` - line 442
- `def visit_While` - line 453
- `def visit_DoWhile` - line 474
- `def visit_For` - line 531
- `def visit_Loop` - line 558
- `def visit_Repeat` - line 613
- `def visit_Foreach` - line 675

### source/transpiler/emit_statements_match_exceptions.py  (392 lines)

- `def visit_Match` - line 20
- `def _generate_pattern_match` - line 64
- `def _extract_pattern_bindings` - line 144
- `def _can_use_switch` - line 186
- `def _generate_switch` - line 210
- `def _generate_sequential_match` - line 239
- `def visit_TryExcept` - line 277
- `def visit_Throw` - line 281
- `def _default_value` - line 288
- `def _values_equal` - line 292
- `def _is_string_pointer` - line 319
- `def _visit_foreach_range` - line 326

### source/transpiler/expr_builtin_channel.py  (670 lines)

- `class ExprBuiltinChannelEmitter` - line 32
  - `__init__` - line 35
  - `__getattr__` - line 38
  - `_chan_pointer_type` - line 41
  - `_chan_ptr_from_handle` - line 44
  - `_chan_field_ptr` - line 49
  - `_chan_field_ptrs` - line 58
  - `_chan_write_tail` - line 66
  - `_chan_read_head` - line 81
  - `_chan_try_lock` - line 97
  - `_chan_release_to` - line 111
  - `_chan_enter_locked_path` - line 117
  - `_chan_branch_closed` - line 131
  - `_chan_load_head_tail` - line 142
  - `_chan_branch_has_data` - line 149
  - `_chan_branch_has_space` - line 161
  - `visit_ChannelCreate` - line 176
  - `visit_ChannelSend` - line 239
  - `visit_ChannelRecv` - line 332
  - `_chan_recv_check_closed` - line 427
  - `visit_ChannelTrySend` - line 450
  - `visit_ChannelTryRecv` - line 545
  - `visit_ChannelClose` - line 622

### source/transpiler/expr_builtin_file.py  (473 lines)

- `class ExprBuiltinFileEmitter` - line 30
  - `__init__` - line 35
  - `__getattr__` - line 38
  - `_open_binary_read` - line 52
  - `_read_file_size` - line 68
  - `_guard_read_allocation_size` - line 79
  - `_builtin_input` - line 102
  - `_builtin_read_stdin` - line 181
  - `_builtin_current_dir` - line 280
  - `_builtin_change_dir` - line 338
  - `_builtin_read_file` - line 356
  - `_builtin_write_file` - line 404

### source/transpiler/expr_builtin_file_ops.py  (356 lines)

- `def _builtin_access` - line 12
- `def _builtin_delete_file` - line 58
- `def _builtin_file_can_execute` - line 80
- `def _builtin_file_exists` - line 118
- `def _builtin_file_size` - line 125
- `def _builtin_make_dir` - line 174
- `def _builtin_move_file` - line 200
- `def _builtin_read_bytes` - line 238
- `def _builtin_write_bytes` - line 305

### source/transpiler/expr_builtin_memory.py  (723 lines)

- `class ExprBuiltinMemoryEmitter` - line 20
  - `__init__` - line 23
  - `__getattr__` - line 26
  - `_coerce_to_i8_ptr` - line 29
  - `_raw_pointer_value` - line 45
  - `_offset_to_i64` - line 54
  - `_guard_non_null_pointer` - line 59
  - `_offset_pointer` - line 82
  - `_builtin_alloc` - line 103
  - `_builtin_dealloc` - line 120
  - `_builtin_arena_create` - line 184
  - `_builtin_arena_alloc` - line 201
  - `_builtin_arena_reset` - line 218
  - `_builtin_arena_destroy` - line 233
  - `_builtin_arena_used` - line 258
  - `_builtin_arena_remaining` - line 270
  - `_builtin_arena_use` - line 282
  - `_builtin_dict_has_key` - line 298
  - `_builtin_dict_new` - line 315
  - `_builtin_dict_size` - line 324
  - `_builtin_dict_key_at` - line 337
  - `_builtin_dict_value_at` - line 355
  - `_builtin_dict_remove` - line 366
  - `_builtin_dict_get_type` - line 378
  - `_builtin_dict_get_string` - line 395
  - `_builtin_peek64` - line 412
  - `_builtin_poke64` - line 458
  - `_builtin_peek_generic` - line 510
  - `_builtin_poke_generic` - line 529
  - `_builtin_peek32` - line 557
  - `_builtin_poke32` - line 561
  - `_builtin_peek8` - line 565
  - `_builtin_poke8` - line 569
  - `_builtin_addressof` - line 573
  - `_builtin_memcpy` - line 587
  - `_builtin_memset` - line 618
  - `_builtin_memmove` - line 647
  - `_builtin_realloc` - line 680
  - `_builtin_calloc` - line 701

### source/transpiler/expr_builtin_memory_stack.py  (50 lines)

- `def _builtin_ptr_array` - line 9
- `def _builtin_stack_alloc` - line 41

### source/transpiler/expr_builtin_meta.py  (348 lines)

- `class ExprBuiltinMetaEmitter` - line 17
  - `__init__` - line 20
  - `__getattr__` - line 23
  - `_dispatch_len` - line 26
  - `_dispatch_single_arg` - line 32
  - `_builtin_typeof` - line 38
  - `_builtin_sizeof` - line 54
  - `_builtin_alignof` - line 80
  - `_builtin_offsetof` - line 105
  - `_builtin_target_os` - line 151
  - `_builtin_target_backend` - line 159
  - `_type_name_to_llvm` - line 165
  - `_resolve_type_name` - line 196
  - `_extern_record_layout` - line 206
  - `_align_to` *(static)* - line 214
  - `_get_union_size_bytes` - line 219
  - `_get_union_align_bytes` - line 228
  - `_get_struct_layout` - line 235
  - `_get_type_size_bytes` - line 248
  - `_get_type_align_bytes` - line 269
  - `_get_type_size_bits` - line 291
  - `_llvm_type_to_name` - line 295

### source/transpiler/expr_builtin_sql.py  (745 lines)

- `class ExprBuiltinSqlEmitter` - line 28
  - `__init__` - line 31
  - `__getattr__` - line 34
  - `_builtin_sql_open_with_flags` - line 37
  - `_builtin_sql_open` - line 67
  - `_builtin_sql_open_readonly` - line 77
  - `_builtin_sql_exec` - line 84
  - `_builtin_sql_close` - line 131
  - `_builtin_sql_prepare` - line 173
  - `_builtin_sql_step` - line 240
  - `_builtin_sql_bind_int` - line 286
  - `_builtin_sql_bind_text` - line 333
  - `_builtin_sql_bind_text_i64` - line 389
  - `_builtin_sql_bind_text_i64_parts` - line 397
  - `_builtin_sql_bind_null` - line 451
  - `_builtin_sql_clear_bindings` - line 497
  - `_builtin_sql_reset` - line 543
  - `_builtin_sql_column_int` - line 589
  - `_builtin_sql_column_text` - line 638
  - `_builtin_sql_finalize` - line 701

### source/transpiler/expr_builtin_sql_text.py  (216 lines)

- `def emit_sql_bind_text_i64_direct` - line 13
- `def _unique` - line 56
- `def _append_cstr` - line 60
- `def _append_i64` - line 89
- `def _collect_digits` - line 134
- `def _flush_digits_reverse` - line 163
- `def _append_byte` - line 192
- `def _terminate` - line 212

### source/transpiler/expr_call_dispatch.py  (356 lines)

- `class ExprBuiltinCallDispatcher` - line 13
  - `__init__` - line 20
  - `__getattr__` - line 24
  - `_get_call_dispatch` - line 27

### source/transpiler/expr_calls.py  (770 lines)

- `def _is_string_type` - line 34
- `def _string_len_name` - line 38
- `class ExprCallEmitter` - line 42
  - `__init__` - line 45
  - `__getattr__` - line 48
  - `_emit_string_len_for_expr` - line 51
  - `_is_virtual_string_expr` - line 76
  - `_can_elide_virtual_string_arg` - line 87
  - `visit_Call` - line 96
  - `_try_fold_pure_call` - line 146
  - `_call_user_function` - line 159
  - `_call_callback_variable` - line 193
  - `visit_FieldAccess` - line 228
  - `visit_SafeFieldAccess` - line 301
  - `visit_MethodCall` - line 348
  - `_try_inline_stack_method_return_expr` - line 468
  - `visit_NewExpr` - line 514
  - `visit_ThisExpr` - line 627
  - `visit_EnumConstruct` - line 636
  - `visit_EnumFieldAccess` - line 702
  - `visit_MatchPattern` - line 765

### source/transpiler/expr_collections.py  (510 lines)

- `class ExprCollectionEmitter` - line 19
  - `__init__` - line 22
  - `__getattr__` - line 25
  - `visit_ArrayAccess` - line 28
  - `_known_dynamic_array_len` - line 131
  - `_can_elide_array_bounds` - line 147
  - `visit_StringSlice` - line 167
  - `_get_dict_type_tag` - line 231
  - `_convert_dict_value` - line 250
  - `visit_DictLit` - line 279
  - `visit_DictAccess` - line 321
  - `visit_TupleLit` - line 344
  - `visit_TupleAccess` - line 372
  - `visit_GenericInstantiation` - line 388
  - `visit_ComptimeExpr` - line 411
  - `_evaluate_comptime` - line 430
  - `visit_Cast` - line 498
- `def _gep_index_value` - line 506

### source/transpiler/expr_common.py  (22 lines)

- `class ExprGenError : Exception` - line 12

### source/transpiler/expr_gen.py  (646 lines)

- `class CExprEmitter` - line 47
  - `__init__` - line 62
  - `__getattr__` - line 67
  - `__setattr__` - line 76
  - `expr` - line 86
  - `_flatten_string_concat` - line 188
  - `_emit_strcat_n` - line 212
  - `_emit_lit_i64_concat` - line 233
  - `_emit_virtual_strlen` - line 257
  - `_emit_known_strlen` - line 281
  - `_is_virtual_string_expr` - line 337
  - `_can_elide_virtual_string_arg` - line 350
  - `_cached_field_strlen` - line 359
  - `_str_arg_is_known_integer` - line 380
  - `_is_integer_type_name` - line 408
  - `_expr_new` - line 436
  - `_expr_method_call` - line 482
  - `_expr_enum_construct` - line 507
  - `_expr_concurrency` - line 527
  - `_expr_atomic` - line 570
  - `_expr_channel` - line 593

### source/transpiler/expr_gen_array_impl.py  (182 lines)

- `def _expr_array_access` - line 11
- `def _known_array_len_hint` - line 142
- `def _can_elide_index_safety` - line 164

### source/transpiler/expr_gen_basic_impl.py  (150 lines)

- `def _expr_literal` - line 9
- `def _expr_interpolated_string` - line 36
- `def _expr_unary_op` - line 88
- `def _expr_ternary_op` - line 97
- `def _expr_field_access` - line 104
- `def _expr_tuple_lit` - line 125
- `def _expr_string_slice` - line 131
- `def _expr_comptime` - line 140

### source/transpiler/expr_gen_binary_impl.py  (243 lines)

- `def _expr_binary_op` - line 18

### source/transpiler/expr_gen_call_builtin_map.py  (398 lines)

- `def _emit_ptr_array` - line 12
- `def _emit_index_of` - line 20
- `def c_builtin_mappings` - line 32

### source/transpiler/expr_gen_call_entry.py  (16 lines)

- `def _generate_call` - line 11

### source/transpiler/expr_gen_call_fd.py  (22 lines)

- `def fd_c_builtin_mappings` - line 6

### source/transpiler/expr_gen_call_impl.py  (493 lines)

- `def _int_range_fits_c_type` - line 27
- `def _plain_c_int_literal` - line 35
- `def _narrow_integer_arg_expr` - line 44
- `def _generate_call` - line 59

### source/transpiler/expr_gen_call_process.py  (90 lines)

- `def process_c_builtin_mappings` - line 6

### source/transpiler/expr_gen_call_syscall.py  (19 lines)

- `def _emit_syscall_call` - line 6

### source/transpiler/expr_gen_call_win32.py  (65 lines)

- `def win32_c_builtin_mappings` - line 8

### source/transpiler/expr_gen_type_impl.py  (420 lines)

- `def _infer_vec_call_type` - line 10
- `def _infer_type` - line 42
- `def _infer_typeof` - line 385

### source/transpiler/expr_literals.py  (355 lines)

- `class ExprLiteralEmitter` - line 25
  - `__init__` - line 33
  - `__getattr__` - line 36
  - `visit_Number` - line 39
  - `visit_Bool` - line 67
  - `visit_Null` - line 70
  - `visit_ReinterpretCast` - line 74
  - `visit_StringLit` - line 109
  - `visit_InterpolatedString` - line 112
  - `visit_ArrayLit` - line 187
  - `visit_ListComprehension` - line 242

### source/transpiler/expr_ops.py  (605 lines)

- `class ExprOpsEmitter` - line 25
  - `__init__` - line 28
  - `__getattr__` - line 31
  - `visit_Variable` - line 34
  - `visit_UnaryOp` - line 100
  - `_check_constant_overflow` - line 129
  - `_try_emit_literal_str_concat` - line 168
  - `visit_BinaryOp` - line 219
  - `_safe_shift` - line 541
  - `visit_TernaryOp` - line 579

### source/transpiler/expr_simd.py  (15 lines)

- `class _SimdBuiltinsMixin : _SimdBuiltinsCoreMixin, _SimdBuiltinsAdvancedMixin` - line 13

### source/transpiler/expr_simd_advanced_impl.py  (515 lines)

- `class _SimdBuiltinsAdvancedMixin : _SimdBuiltinsHostMixin` - line 10
  - `_builtin_vec_minmax` - line 12
  - `_builtin_vec_avg` - line 32
  - `_builtin_vec_sad` - line 64
  - `_builtin_vec_hadd` - line 93
  - `_builtin_vec_shuffle_bytes` - line 130
  - `_builtin_vec_abs` - line 178
  - `_builtin_vec_blend` - line 194
  - `_builtin_vec_dot` - line 226
  - `_builtin_vec_cmpstr` - line 267
  - `_builtin_vec_permute` - line 308
  - `_builtin_vec_gather` - line 345
  - `_builtin_vec_compress` - line 390
  - `_builtin_vec_expand` - line 421
  - `_builtin_vec_fma` - line 453
  - `_builtin_vec_fms` - line 484

### source/transpiler/expr_simd_core_impl.py  (373 lines)

- `class _SimdBuiltinsCoreMixin : _SimdBuiltinsHostMixin` - line 10
  - `_builtin_vec_load` - line 12
  - `_builtin_vec_loadu` - line 35
  - `_builtin_vec_storeu` - line 53
  - `_builtin_vec_store` - line 66
  - `_builtin_vec_broadcast` - line 85
  - `_builtin_vec_binop` - line 114
  - `_builtin_vec_not` - line 157
  - `_builtin_vec_cmp` - line 167
  - `_builtin_vec_movemask` - line 188
  - `_vec_movemask_sse2` - line 231
  - `_vec_movemask_avx2` - line 245
  - `_vec_movemask_avx512` - line 259
  - `_vec_movemask_portable` - line 303
  - `_builtin_vec_shuffle` - line 325
  - `_builtin_vec_extract` - line 336
  - `_builtin_vec_insert` - line 353

### source/transpiler/expr_simd_host.py  (33 lines)

- `class _SimdBuiltinsHostMixin` - line 10

### source/transpiler/expr_string_fastpath.py  (118 lines)

- `def _literal_bytes` - line 10
- `def _is_stable_expr` - line 17
- `def _c_string_literal` - line 28
- `def _emit_streq_literal_call` - line 39
- `def emit_streq_literal_fastpath` - line 63
- `def _int_literal` - line 75
- `def literal_ord_byte_value` - line 86
- `def literal_char_at_byte_value` - line 96
- `def static_string_byte_length` - line 111

### source/transpiler/expr_strlen_dynamic.py  (30 lines)

- `def emit_dynamic_strlen_c` - line 14

### source/transpiler/expr_system.py  (286 lines)

- `class ExprBuiltinSystemEmitter` - line 165
  - `__init__` - line 168
  - `__getattr__` - line 171

### source/transpiler/expr_system_argv.py  (81 lines)

- `def _ensure_argv_globals` - line 9
- `def _builtin_argc` - line 38
- `def _builtin_argv` - line 52

### source/transpiler/expr_system_fd.py  (319 lines)

- `def _target_is_windows` - line 14
- `def _i64_const` - line 19
- `def _to_i32` - line 23
- `def _to_i64` - line 34
- `def _to_i8_ptr` - line 47
- `def _declare` - line 59
- `def _native_open_flags` - line 66
- `def _builtin_fd_open` - line 133
- `def _builtin_fd_read` - line 162
- `def _builtin_fd_write` - line 185
- `def _builtin_fd_close` - line 208
- `def _builtin_fd_dup` - line 225
- `def _builtin_fd_dup2` - line 242
- `def _builtin_fd_tell` - line 260
- `def _builtin_fd_seek` - line 282
- `def _builtin_fd_flush` - line 305

### source/transpiler/expr_system_lowlevel.py  (665 lines)

- `def _as_i64` - line 15
- `def _builtin_poke` - line 31
- `def _builtin_peek` - line 58
- `def _builtin_outb` - line 81
- `def _builtin_inb` - line 110
- `def _builtin_syscall` - line 137
- `def _builtin_getpid` - line 166
- `def _builtin_ptr_add` - line 194
- `def _builtin_ptr_sub` - line 219
- `def _builtin_math_unary` - line 249
- `def _builtin_pow` - line 284
- `def _literal_bytes` - line 311
- `def _emit_literal_ptr_compare` - line 318
- `def _emit_substr_literal_compare` - line 372
- `def _emit_streq_literal_fastpath` - line 443
- `def _builtin_streq` - line 465
- `def _builtin_parse_int` - line 488
- `def _builtin_popcount` - line 523
- `def _builtin_clz` - line 560
- `def _builtin_ctz` - line 598
- `def _builtin_rdtsc` - line 640

### source/transpiler/expr_system_process.py  (109 lines)

- `def _target_is_windows` - line 24
- `def _call_posix_i32_identity` - line 29
- `def _to_i32` - line 45
- `def _builtin_getppid` - line 57
- `def _builtin_getuid` - line 63
- `def _builtin_geteuid` - line 69
- `def _builtin_getgid` - line 75
- `def _builtin_getegid` - line 81
- `def _builtin_getgeid` - line 87
- `def _builtin_process_umask` - line 93

### source/transpiler/expr_system_split.py  (510 lines)

- `def _decl_type_for_arg` - line 12
- `def _builtin_split` - line 20
- `def _builtin_split_ints` - line 52
- `def _builtin_split_len` - line 88
- `def _builtin_split_get` - line 108
- `def _builtin_split_str_get` - line 137
- `def _builtin_split_set` - line 173
- `def _ensure_libc_functions` - line 205
- `def _create_split_common` - line 266
- `def _begin_split_parse_loop` - line 363
- `def _continue_split_parse_loop` - line 387
- `def _finish_split_helper` - line 407
- `def _create_split_helper` - line 417
- `def _create_split_ints_helper` - line 465

### source/transpiler/expr_system_status.py  (97 lines)

- `def _errno_pointer_function_name` - line 12
- `def _errno_pointer` - line 29
- `def _builtin_errno_get` - line 46
- `def _builtin_errno_clear` - line 59
- `def _builtin_errno_set` - line 72

### source/transpiler/expr_system_time.py  (339 lines)

- `def _builtin_time_ms` - line 11
- `def _time_ms_windows` - line 29
- `def _time_ms_linux` - line 68
- `def _builtin_time_ns` - line 119
- `def _time_ns_windows` - line 132
- `def _time_ns_linux` - line 167
- `def _builtin_clock_ns` - line 205
- `def _clock_ns_windows` - line 232
- `def _clock_ns_posix` - line 285

### source/transpiler/expr_system_win32.py  (661 lines)

- `def _win32_target_enabled` - line 9
- `def _builtin_win32_load_library` - line 14
- `def _builtin_win32_get_proc_address` - line 28
- `def _builtin_win32_free_library` - line 44
- `def _builtin_win32_get_last_error` - line 59
- `def _emit_win32_utf16_from_utf8_value` - line 71
- `def _builtin_win32_utf16_from_utf8` - line 128
- `def _builtin_win32_local_free` - line 138
- `def _emit_owned_empty_i8_string` - line 156
- `def _builtin_win32_full_path` - line 162
- `def _builtin_win32_shell_execute_runas` - line 204
- `def _emit_win32_load_library_name` - line 265
- `def _emit_win32_free_library_value` - line 276
- `def _emit_win32_proc_value` - line 284
- `def _emit_win32_hcs_module` - line 295
- `def _emit_win32_invoke_i32_proc` - line 303
- `def _emit_win32_invoke_ptr_proc` - line 313
- `def _emit_win32_invoke_void_proc` - line 324
- `def _builtin_win32_is_user_admin` - line 333
- `def _builtin_win32_hcs_vmcompute_available` - line 409
- `def _builtin_win32_hcs_computecore_available` - line 422
- `def _builtin_win32_hcs_create_operation` - line 435
- `def _builtin_win32_hcs_close_operation` - line 452
- `def _builtin_win32_hcs_close_compute_system` - line 469
- `def _builtin_win32_hcs_open_compute_system` - line 486
- `def _builtin_win32_hcs_wait_operation_result` - line 517
- `def _builtin_win32_hcs_create_compute_system` - line 549
- `def _emit_win32_hcs_action3` - line 586
- `def _builtin_win32_hcs_start_compute_system` - line 611
- `def _builtin_win32_hcs_save_compute_system` - line 615
- `def _builtin_win32_hcs_shutdown_compute_system` - line 619
- `def _builtin_win32_hcs_terminate_compute_system` - line 623
- `def _builtin_win32_hcs_get_compute_system_properties` - line 627
- `def _builtin_win32_hcs_modify_compute_system` - line 631

### source/transpiler/expr_threading.py  (148 lines)

- `class ExprBuiltinThreadingEmitter` - line 80
  - `__init__` - line 83
  - `__getattr__` - line 86

### source/transpiler/expr_threading_core.py  (546 lines)

- `def visit_Spawn` - line 12
- `def _spawn_windows` - line 57
- `def _spawn_pthread` - line 119
- `def visit_Join` - line 175
- `def _join_windows` - line 198
- `def _join_pthread` - line 229
- `def visit_Await` - line 251
- `def visit_AtomicOp` - line 273
- `def _get_variable_ptr` - line 345
- `def _builtin_atomic_load` - line 371
- `def _builtin_atomic_store` - line 380
- `def _builtin_atomic_add` - line 390
- `def _builtin_atomic_sub` - line 399
- `def _builtin_atomic_exchange` - line 408
- `def _builtin_atomic_cmpxchg` - line 417
- `def _builtin_thread_id` - line 430
- `def _builtin_num_cpus` - line 452
- `def _builtin_yield_thread` - line 483
- `def _builtin_sleep_ms` - line 507

### source/transpiler/expr_threading_socket.py  (563 lines)

- `def _socket_is_windows` - line 11
- `def _socket_handle_ty` - line 16
- `def _socket_handle_to_i64` - line 26
- `def _socket_invalid_const` - line 37
- `def _ensure_wsa_init` - line 47
- `def _emit_htons` - line 93
- `def _emit_socket_close_native` - line 110
- `def _emit_socket_nodelay` - line 119
- `def _emit_libc_memset` - line 150
- `def _build_sockaddr_in` - line 173
- `def _builtin_tcp_listen` - line 231
- `def _builtin_tcp_accept` - line 297
- `def _builtin_tcp_recv` - line 347
- `def _builtin_tcp_send` - line 419
- `def _builtin_tcp_close` - line 519

### source/transpiler/expr_threading_sync.py  (259 lines)

- `def _sync_alloc_and_init` - line 11
- `def _sync_call_void` - line 45
- `def _sync_get_free` - line 59
- `def _builtin_mutex_create` - line 69
- `def _builtin_mutex_lock` - line 79
- `def _builtin_mutex_unlock` - line 84
- `def _builtin_mutex_destroy` - line 91
- `def _builtin_cond_create` - line 104
- `def _builtin_cond_wait` - line 114
- `def _builtin_cond_signal` - line 140
- `def _builtin_cond_broadcast` - line 147
- `def _builtin_cond_destroy` - line 154
- `def _builtin_rwlock_create` - line 168
- `def _builtin_rwlock_read_lock` - line 178
- `def _builtin_rwlock_write_lock` - line 185
- `def _builtin_rwlock_read_unlock` - line 192
- `def _builtin_rwlock_write_unlock` - line 199
- `def _builtin_rwlock_destroy` - line 206
- `def _builtin_system` - line 220

### source/transpiler/expr_threading_tcp_connect.py  (220 lines)

- `def _addrinfo_layout` - line 11
- `def _emit_i32_store_at` - line 32
- `def _emit_load_at` - line 43
- `def _builtin_tcp_connect` - line 56

### source/transpiler/expr_type_helpers.py  (284 lines)

- `class ExprTypeHelperEmitter` - line 18
  - `__init__` - line 21
  - `__getattr__` - line 25
  - `_is_float_type` - line 28
  - `_both_strings` - line 31
  - `_is_string_pointer` - line 34
  - `_byte_to_string` - line 41
  - `cast_value` - line 54
  - `_safe_fptosi` - line 122
  - `_coerce_numeric_operands` - line 168
  - `_narrow_integer_literal` - line 192
  - `_literal_fits_int_type` - line 211
  - `ensure_int64` - line 222
  - `_compare_strings` - line 247
  - `_get_pow_intrinsic` - line 265
  - `_is_unsigned_node` - line 279

### source/transpiler/fixed_array_types.py  (25 lines)

- `def parse_fixed_array_type_spec` - line 8

### source/transpiler/helper_scanner.py  (810 lines)

- `class HelperScanner` - line 55
  - `__init__` - line 208
  - `run` - line 240
  - `_scan_node` - line 248
  - `_collect_local_type_hints` - line 484
  - `_scan_length_only_string_assignment` - line 548
  - `_scan_call` - line 587
  - `_scan_binary_op` - line 641
  - `_scan_interp_string` - line 692
  - `_scan_if` - line 699
  - `_scan_for` - line 712
  - `_scan_foreach` - line 722
  - `_scan_array_access` - line 729
  - `_scan_fixed_dict_literal_assignment` - line 743
  - `_is_fixed_dict_expr` - line 756
  - `_scan_dict_assign` - line 761
  - `_scan_match` - line 778
  - `_scan_try_except` - line 789

### source/transpiler/helper_scanner_concurrency.py  (66 lines)

- `def _scan_concurrency` - line 6
- `def _scan_channel` - line 37

### source/transpiler/helper_scanner_string_array.py  (248 lines)

- `def _array_access_literal_proven` - line 13
- `def _cached_strlen_field_arg` - line 18
- `def _class_field_is_string` - line 32
- `def _field_assign_targets_string` - line 44
- `def _is_integer_type_name` - line 53
- `def _known_array_len_hint` - line 82
- `def _literal_char_at_length_proven` - line 103
- `def _scan_methodcall_hidden_string_lengths` - line 115
- `def _scan_newexpr_hidden_string_lengths` - line 149
- `def _scan_streq_slice_fastpath` - line 174
- `def _str_arg_is_known_integer` - line 200
- `def _virtual_concat_numeric_arg` - line 229
- `def _virtual_strlen_numeric_arg` - line 244

### source/transpiler/import_resolver.py  (737 lines)

- `class ImportResolver` - line 36
  - `run` - line 48
  - `_process_file_imports` - line 77
  - `_resolve_cimport_path` - line 125
  - `_cimport_candidate_paths` - line 167
  - `_resolve_module_path` - line 194
  - `_add_imported_node` - line 225
  - `_parse_import_file` - line 285
  - `_parse_probe_import_file` - line 307
  - `_probe_payload_from_json` - line 373
  - `_load_cbind_probe_tool` *(static)* - line 412
  - `_iter_probe_constants` *(static)* - line 424
  - `_normalize_probe_header` *(static)* - line 441
  - `_probe_constant_node` *(static)* - line 462
  - `_probe_enum_node` *(static)* - line 496
  - `_dict_key_sort_key` *(static)* - line 536
  - `_probe_record_node` *(static)* - line 541
  - `_probe_record_layout_constant_nodes` *(static)* - line 613
  - `_normalize_identifier` *(static)* - line 661
  - `_int_constant_node` *(static)* - line 672
  - `_probe_fn_node` *(static)* - line 681
  - `_tag_source_file` *(static)* - line 717
  - `_sort_key` *(static)* - line 726

### source/transpiler/llvm_fixed_dicts.py  (120 lines)

- `def _literal_key` - line 14
- `def _scan_literal_dict_locals` - line 20
- `def analyze_llvm_fixed_dicts` - line 45
- `def _slot_name` - line 52
- `def emit_fixed_dict_init` - line 58
- `def try_fixed_dict_access` - line 90
- `def try_fixed_dict_assign` - line 102

### source/transpiler/llvm_int_narrowing.py  (171 lines)

- `def maybe_narrow_local_type` - line 21
- `def maybe_narrow_param_value` - line 42
- `def effective_local_type_name` - line 74
- `def cast_for_narrowed_storage` - line 86
- `def _can_narrow_param` - line 101
- `def _declared_param_range` - line 116
- `def _param_type_can_narrow` - line 129
- `def _scope_interval` - line 135
- `def _dynamic_interval` - line 143
- `def _is_i64_type` - line 151
- `def _is_i64ish_type_name` - line 155
- `def _fits_i32_interval` - line 160

### source/transpiler/llvm_stack_arrays.py  (232 lines)

- `def emit` - line 12
- `def emit_assign` - line 26
- `def _emit_literal` - line 49
- `def _collect_direct_aliases` - line 107
- `def _uses_are_stack_safe` - line 123
- `def _stmt_ok` - line 132
- `def _node_ok` - line 174
- `def _is_statement` - line 185
- `def _is_alias_decl` - line 201
- `def _expr_ok` - line 205
- `def _is_allowed_metadata_call` - line 226

### source/transpiler/local_constant_flow.py  (105 lines)

- `def clear_local_constants` - line 8
- `def forget_local_constants` - line 14
- `def loop_assigned_names` - line 22
- `def branch_assigned_names` - line 40
- `def _collect_names` - line 47
- `def _collect_generic_bodies` - line 94

### source/transpiler/local_int_narrowing.py  (277 lines)

- `def apply_proven_i32_narrowing` - line 19
- `def apply_proven_i32_signature_narrowing` - line 40
- `def _can_narrow_function` - line 54
- `def _narrow_params` - line 68
- `def _narrow_locals` - line 108
- `def _param_name_type` - line 127
- `def _set_param_type` - line 136
- `def _is_i64ish` - line 148
- `def _fits_i32_interval` - line 153
- `def _assigned_names` - line 163
- `def _assignment_values_for` - line 175
- `def _param_uses_are_i32_storage_safe` - line 188
- `def param_uses_are_i32_storage_safe` - line 197
- `def _node_uses_name_in_unsafe_context` - line 203
- `def _node_contains_var` - line 221
- `def _walk_nodes` - line 235
- `def _expr_is_intlike` - line 247

### source/transpiler/optimizer_decisions.py  (62 lines)

- `def record_stack_array_fields` - line 9
- `def record_stack_class` - line 32
- `def record_virtual_string_arg` - line 45

### source/transpiler/ownership_analyzer.py  (638 lines)

- `class OwnershipAnalyzer` - line 28
  - `__init__` - line 84
  - `is_owned_string_alloc` - line 96
  - `user_fn_call_is_non_capturing` - line 142
  - `collect_string_locals` - line 158
  - `collect_mixed_ownership_string_locals` - line 166
  - `_scan_string_assigns` - line 175
  - `collect_array_locals` - line 233
  - `collect_with_owning` - line 238
  - `collect_class_locals` - line 308
  - `class_locals_constructed_by_new` - line 373
  - `detect_escaping_class_locals` - line 422
  - `detect_escaping_locals` - line 436

### source/transpiler/prologue_emitter.py  (729 lines)

- `class PrologueEmitter` - line 43
  - `__init__` - line 49
  - `_parse_fixed_array_type_spec` - line 73
  - `_format_decl` - line 76
  - `_emit_header` - line 86
  - `_emit_type_definitions` - line 334
  - `_emit_callback_typedefs` - line 431
  - `_format_method_param` - line 452
  - `_emit_class_method_forward_decls` - line 463
  - `_emit_forward_declarations` - line 495
  - `_emit_dynamic_collection_typedefs` - line 559
  - `_extract_template_function_signatures` - line 596
  - `_emit_template_blocks` - line 663
  - `_emit_cinclude_directives` - line 684
  - `_emit_link_directives` - line 707
  - `_emit_extern_fn_decl` - line 716

### source/transpiler/pure_call_hoist.py  (30 lines)

- `def hoisted_pure_call_replacement` - line 17

### source/transpiler/pure_eval.py  (551 lines)

- `class PureEvalUnsupported : Exception` - line 10
- `class _ReturnSignal : Exception` - line 15
- `class _EvalBudget` - line 20
  - `spend` - line 23
- `class _BreakSignal : Exception` - line 29
- `def stable_literal_bindings` - line 33
- `def try_eval_call` - line 66
- `def _literal_value` - line 82
- `def _eval_function` - line 92
- `def _exec_block` - line 116
- `def _exec_stmt` - line 130
- `def _try_exec_fixed_array_reduction` - line 192
- `def _outer_counted_loop` - line 249
- `def _inner_fixed_array_reduction` - line 274
- `def _inner_break_array_reduction` - line 283
- `def _inner_counted_array_reduction` - line 304
- `def _counted_index_limit` - line 323
- `def _array_reduction_add` - line 333
- `def _break_index` - line 354
- `def _is_increment` - line 371
- `def _is_number_value` - line 382
- `def _exec_signal` - line 390
- `def _eval_expr` - line 406
- `def _eval_binary` - line 470
- `def _eval_call` - line 508
- `def _truthy` - line 539
- `def _to_int` - line 545

### source/transpiler/range_facts.py  (544 lines)

- `class RangeFacts : RangeFactsProofMixin` - line 37
  - `has_expr_scope_snapshot` - line 88
  - `get_var_range` - line 93
  - `set_var_range` - line 104
  - `clear_var_range` - line 111
  - `lock_var_range` - line 116
  - `set_unknown_reason` - line 119
  - `clear_unknown_reason` - line 124
  - `set_loop_reason` - line 127
  - `clear_loop_reason` - line 132
  - `get_array_info` - line 135
  - `set_array_info` - line 146
  - `clear_array_info` - line 158
  - `get_dict_value_info` - line 163
  - `set_dict_value_info` - line 178
  - `set_dict_value_infos` - line 185
  - `clear_dict_value_info` - line 190
  - `observe_call_arg_interval` - line 203
  - `observe_call_arg_string_info` - line 210
  - `observe_function_return_interval` - line 217
  - `set_string_info` - line 225
  - `get_string_info` - line 230
  - `clear_string_info` - line 241
  - `set_string_len_var` - line 246
  - `clear_string_len_var` - line 251
  - `mark_safe_char_at_call` - line 260
  - `is_safe_char_at_call` - line 265
  - `mark_nonnegative_var` - line 270
  - `clear_nonnegative_var` - line 273
  - `is_nonnegative_var` - line 276
  - `capture_expr_scope` - line 279
  - `_expr_scope_snapshot` - line 308
  - `_expr_unknown_snapshot` - line 313
  - `_expr_array_snapshot` - line 318
  - `_expr_dict_value_snapshot` - line 323
  - `_expr_string_snapshot` - line 328
  - `_expr_loop_reason_snapshot` - line 333
  - `_expr_relation_snapshot` - line 338
  - `_range_from_scope` *(static)* - line 344
  - `_unknown_from_scope` *(static)* - line 352
- `class RangeFactsAnalyzer` - line 360
  - `__init__` - line 394
  - `run` - line 398
  - `_collect_type_alias_ranges` - line 454
  - `_scan_nodes` - line 463
  - `_scan_node` - line 474
  - `_infer_array_info` - line 495
  - `_range_from_type_name` - line 517
  - `_range_from_range_type` - line 523

### source/transpiler/range_facts_loop_patterns.py  (775 lines)

- `def while_true_break_guard_bounds` - line 20
- `def derive_specialized_while_ranges` - line 91
- `def _clamped_accumulator_ranges` - line 190
- `def _scalar_reduction_budget` - line 242
- `def _string_info_from_assignment` - line 342
- `def _expr_interval_with_transient_strings` - line 365
- `def _iter_assignments` - line 415
- `def _is_self_accumulator_write` - line 423
- `def _symbolic_step_one_counter_range` - line 433
- `def _while_counter_bound` - line 468
- `def _assignment_count_for_var` - line 494
- `def _assignment_count_in_node` - line 501
- `def _iter_ast_children` - line 510
- `def _top_level_counter_step` - line 521
- `def _top_level_counter_delta` - line 526
- `def _nested_reduction_budget` - line 553
- `def is_branch_heavy_loop_body` - line 656
- `def _is_break_guard_if` - line 686
- `def _self_reduction_budget` - line 695

### source/transpiler/range_facts_loop_state.py  (139 lines)

- `def dict_state_from_facts` - line 13
- `def expr_interval_with_loop_state` - line 24
- `def literal_dict_key_access` - line 101
- `def literal_dict_assignment` - line 113
- `def self_accumulator_growth_terms` - line 123
- `def _flatten_add` - line 135

### source/transpiler/range_facts_proofs.py  (704 lines)

- `class RangeFactsProofMixin` - line 11
  - `_expr_scope_snapshot` - line 19
  - `_expr_unknown_snapshot` - line 24
  - `_expr_array_snapshot` - line 29
  - `_expr_dict_value_snapshot` - line 34
  - `_expr_string_snapshot` - line 39
  - `_expr_loop_reason_snapshot` - line 44
  - `_expr_relation_snapshot` - line 49
  - `_range_from_scope` - line 54
  - `_unknown_from_scope` - line 59
  - `get_var_range` - line 64
  - `get_array_info` - line 69
  - `get_dict_value_info` - line 74
  - `get_string_info` - line 79
  - `can_prove_no_overflow` - line 84
  - `can_prove_no_overflow_for_int` - line 93
  - `can_prove_safe_modulo` - line 109
  - `can_prove_safe_division` - line 123
  - `_can_prove_positive_rhs` - line 137
  - `explain_no_overflow` - line 155
  - `explain_no_overflow_for_int` - line 162
  - `_classify_proven_reason` - line 215
  - `_overflow_unknown_taint` - line 253
  - `_iter_arithmetic_proof_vars` - line 285
  - `can_prove_index_in_bounds` - line 303
  - `explain_index_in_bounds` - line 311
  - `can_prove_range_assignment` - line 332
  - `_expr_interval` - line 350
  - `_expr_interval_with_reason` - line 366
  - `_binary_interval` *(static)* - line 614
  - `_relation_proves_ge` *(static)* - line 632
  - `_additive_nonnegative_by_relation` - line 648
  - `_linear_terms` *(classmethod)* - line 694

### source/transpiler/range_facts_protocol.py  (367 lines)

- `def _decimal_accumulator_target` - line 16
- `def _is_break_guard_for` - line 73
- `def _positive_modulus` - line 89
- `def _collect_assignments_by_var` - line 99
- `def _expr_is_nonnegative` - line 129
- `def _decimal_accumulator_targets` - line 188
- `def _derive_modulo_assignment_ranges` - line 213
- `def _derive_protocol_loop_ranges` - line 263
- `def _mark_symbolic_guarded_char_at_calls` - line 325

### source/transpiler/range_facts_scan.py  (585 lines)

- `def _dict_literal_ranges` - line 26
- `def _remember_or_clear_dict_info` - line 44
- `def scan_if` - line 58
- `def scan_function` - line 153
- `def scan_node` - line 177
- `def scan_loop` - line 508

### source/transpiler/range_facts_types.py  (62 lines)

- `class Interval` - line 7
  - `union` - line 11
- `class StringInfo` - line 16
  - `union` - line 21
- `def string_info_from_literal` - line 29
- `def string_info_from_format_call` - line 42
- `def _unsigned_digits` - line 56

### source/transpiler/range_facts_utils.py  (509 lines)

- `def collect_assigned_vars` - line 11
- `def capture_expr_tree` - line 38
- `def walk_ast` - line 51
- `def iter_child_nodes` - line 57
- `def invalidate_non_locked_scope` - line 74
- `def invalidate_for_side_effect` - line 101
- `def node_is_unknown_side_effect_barrier` - line 112
- `def expr_contains_unknown_side_effect` - line 139
- `def contains_unknown_side_effect_call` - line 148
- `def infer_array_info` - line 158
- `def observe_calls_in_expr` - line 200
- `def _string_info_from_expr` - line 227
- `def _strlen_source_var` - line 252
- `def _remember_or_clear_strlen_var` - line 263
- `def _remember_or_clear_string_info` - line 275
- `def _expr_roots_for_guarded_char_at` - line 290
- `def _stmt_assigns_any` - line 330
- `def _intersect_interval` - line 338
- `def _refine_scope_with_var_bound` - line 349
- `def _refine_scope_for_condition` - line 368
- `def _relation_for_condition` - line 437
- `def _drop_relations_for_var` - line 461
- `def _relations_with_condition` - line 472
- `def _body_exits_current_path` - line 482
- `def _all_assignments_are_positive_increment` - line 488

### source/transpiler/runtime_emit_atomics.py  (67 lines)

- `def emit_runtime_atomics` - line 10

### source/transpiler/runtime_emit_baseconv.py  (118 lines)

- `def emit_base_conversion_helpers` - line 4

### source/transpiler/runtime_emit_channels.py  (273 lines)

- `def emit_runtime_channels` - line 8

### source/transpiler/runtime_emit_collections.py  (389 lines)

- `def emit_runtime_dict` - line 8
- `def emit_runtime_dynamic_array` - line 209
- `def emit_runtime_str_array` - line 274

### source/transpiler/runtime_emit_fd.py  (176 lines)

- `def emit_runtime_fd` - line 8

### source/transpiler/runtime_emit_io.py  (251 lines)

- `def emit_runtime_sqlite` - line 8
- `def emit_runtime_fileops` - line 198

### source/transpiler/runtime_emit_math.py  (155 lines)

- `def emit_runtime_math` - line 8

### source/transpiler/runtime_emit_process.py  (570 lines)

- `def emit_runtime_process` - line 23
- `def _emit_windows_argv_helpers` - line 76
- `def _emit_posix_identity_helper` - line 147
- `def _emit_process_umask` - line 162
- `def _emit_process_group_helpers` - line 177
- `def _emit_process_exec_errno_helpers` - line 260
- `def _emit_signal_helpers` - line 364
- `def _emit_process_run_argv` - line 505

### source/transpiler/runtime_emit_process_capture_pipeline.py  (712 lines)

- `def _emit_process_capture_pipeline_argv_redirs` - line 6

### source/transpiler/runtime_emit_process_io.py  (362 lines)

- `def _emit_process_capture_argv_env_redirs` - line 6
- `def _emit_process_pipe_argv_redirs` - line 176
- `def _emit_process_pipeline_argv_redirs` - line 328

### source/transpiler/runtime_emit_process_lifecycle.py  (653 lines)

- `def _emit_process_lifecycle` - line 6

### source/transpiler/runtime_emit_process_redirs.py  (294 lines)

- `def _emit_redirection_helpers` - line 6
- `def _emit_process_run_argv_redirs` - line 199
- `def _emit_process_run_argv_env_redirs` - line 275

### source/transpiler/runtime_emit_safety.py  (699 lines)

- `def emit_safety_helpers` - line 10

### source/transpiler/runtime_emit_safety_tail.py  (196 lines)

- `def emit_safety_tail_helpers` - line 8

### source/transpiler/runtime_emit_simd.py  (609 lines)

- `def emit_runtime_simd` - line 13
- `def emit_simd_header` - line 22
- `def emit_simd_basic_ops` - line 45
- `def emit_simd_advanced_ops` - line 343

### source/transpiler/runtime_emit_sockets.py  (280 lines)

- `def emit_runtime_sockets` - line 10

### source/transpiler/runtime_emit_status.py  (40 lines)

- `def emit_runtime_status` - line 8

### source/transpiler/runtime_emit_string.py  (744 lines)

- `def emit_runtime_string` - line 18
- `def emit_split_ints_helper` - line 548
- `def emit_split_helper` - line 636
- `def emit_parse_int_helper` - line 721

### source/transpiler/runtime_emit_string_aux.py  (606 lines)

- `def emit_file_io_helpers` - line 19

### source/transpiler/runtime_emit_string_aux_extra.py  (256 lines)

- `def emit_arena_helper` - line 12
- `def emit_input_helper` - line 146
- `def emit_dynamic_array_helpers` - line 200

### source/transpiler/runtime_emit_string_writers.py  (85 lines)

- `def emit_typed_writer_helpers` - line 6

### source/transpiler/runtime_emit_sync.py  (268 lines)

- `def emit_runtime_sync` - line 10

### source/transpiler/runtime_emit_syscall.py  (41 lines)

- `def emit_runtime_syscall` - line 8

### source/transpiler/runtime_emit_system.py  (89 lines)

- `def emit_runtime_system` - line 10

### source/transpiler/runtime_emit_threading.py  (150 lines)

- `def emit_runtime_threading` - line 8
- `def _spawn_box_name` - line 135
- `def _spawn_thunk_name` - line 139
- `def _spawn_caller_name` - line 143

### source/transpiler/runtime_emit_threading_utils.py  (83 lines)

- `def emit_runtime_threading_utils` - line 10

### source/transpiler/runtime_emit_time.py  (101 lines)

- `def emit_runtime_time` - line 10

### source/transpiler/runtime_emit_win32.py  (501 lines)

- `def emit_runtime_win32` - line 10

### source/transpiler/runtime_emitter.py  (359 lines)

- `class RuntimeEmitter` - line 74
  - `__init__` - line 79
  - `run` - line 93
  - `_emit_runtime_time` - line 187
  - `_emit_runtime_string` - line 191
  - `_emit_split_ints_helper` - line 194
  - `_emit_split_helper` - line 197
  - `_emit_parse_int_helper` - line 200
  - `_emit_file_io_helpers` - line 203
  - `_emit_arena_helper` - line 206
  - `_emit_input_helper` - line 209
  - `_emit_base_conversion_helpers` - line 212
  - `_emit_dynamic_array_helpers` - line 215
  - `_emit_runtime_math` - line 218
  - `_emit_safety_helpers` - line 221
  - `_emit_runtime_simd` - line 224
  - `_emit_simd_header` - line 227
  - `_emit_simd_basic_ops` - line 230
  - `_emit_simd_advanced_ops` - line 233
  - `_emit_runtime_dict` - line 236
  - `_emit_runtime_dynamic_array` - line 239
  - `_emit_runtime_str_array` - line 242
  - `_emit_runtime_sqlite` - line 245
  - `_emit_runtime_fileops` - line 248
  - `_emit_runtime_fd` - line 251
  - `_emit_runtime_threading` - line 254
  - `_spawn_box_name` - line 257
  - `_spawn_thunk_name` - line 260
  - `_spawn_caller_name` - line 263
  - `_emit_spawn_thunks` - line 266
  - `_emit_runtime_threading_utils` - line 321
  - `_emit_runtime_atomics` - line 325
  - `_emit_runtime_channels` - line 329
  - `_emit_runtime_sync` - line 332
  - `_emit_runtime_system` - line 336
  - `_emit_runtime_syscall` - line 340
  - `_emit_runtime_process` - line 344
  - `_emit_runtime_status` - line 348
  - `_emit_runtime_sockets` - line 352
  - `_emit_runtime_win32` - line 356

### source/transpiler/runtime_needs.py  (172 lines)

- `class RuntimeNeeds` - line 85
  - `family_flags` - line 133
  - `helper_counts_by_family` - line 154

### source/transpiler/stack_class_c.py  (27 lines)

- `def emit_stack_class_zero_init` - line 14

### source/transpiler/stack_class_lowering.py  (271 lines)

- `def _is_string_type` - line 23
- `def _try_emit_stack_class_vardecl` - line 27

### source/transpiler/stmt_visit.py  (185 lines)

- `class CStmtEmitter` - line 79
  - `__init__` - line 108
  - `__getattr__` - line 111
  - `__setattr__` - line 114

### source/transpiler/stmt_visit_calls.py  (619 lines)

- `def _escape_c_string_fragment` - line 12
- `def _build_interpolation_writer_plan` - line 23
- `def _emit_interpolation_writer_chunks` - line 88
- `def _get_printf_spec` - line 122
- `def _baseconv_writer_kind` - line 178
- `def _get_printf_arg` - line 187
- `def _emit_print_call` - line 200
- `def _emit_dealloc_arg` - line 368
- `def visit_Call` - line 436
- `def _resolve_method_class` - line 451
- `def _emit_method_call_text` - line 464
- `def _try_inline_stack_method_return_expr` - line 517
- `def visit_MethodCall` - line 567
- `def visit_Spawn` - line 578
- `def visit_Join` - line 585
- `def visit_AtomicOp` - line 590
- `def visit_ChannelSend` - line 594
- `def visit_ChannelClose` - line 598
- `def visit_ChannelTrySend` - line 602
- `def visit_ChannelTryRecv` - line 606
- `def visit_ChannelRecv` - line 610
- `def visit_ChannelCreate` - line 615

### source/transpiler/stmt_visit_class.py  (713 lines)

- `def _param_parts` - line 32
- `def _can_seed_call_hint_ranges` - line 39
- `def _seed_call_hint_param_ranges` - line 47
- `def _declared_param_range` - line 74
- `def _is_literal_return_guard` - line 95
- `def _is_decreasing_self_arg` - line 111
- `def _iter_ast_nodes` - line 121
- `def _self_calls_are_decreasing` - line 132
- `def _can_elide_recursion_guard` - line 147
- `def visit_Function` - line 176
- `def visit_RecordDef` - line 387
- `def visit_GenericRecord` - line 391
- `def visit_GenericClass` - line 397
- `def visit_GenericFunction` - line 403
- `def visit_EnumDef` - line 409
- `def visit_TemplateBlock` - line 413
- `def visit_CInclude` - line 417
- `def visit_LinkDirective` - line 421
- `def visit_ExternFn` - line 425
- `def visit_ExternVar` - line 429
- `def visit_ExternRecordDef` - line 433
- `def visit_UnionDef` - line 437
- `def visit_ReinterpretCast` - line 441
- `def visit_ComptimeExpr` - line 451
- `def visit_ComptimeBlock` - line 464
- `def visit_ComptimeIf` - line 470
- `def visit_StaticAssert` - line 486
- `def _evaluate_comptime` - line 498
- `def visit_ClassDef` - line 569
- `def _class_new_signature` - line 598
- `def _emit_class_new_wrapper` - line 645
- `def _sanitize_method_name` - line 705

### source/transpiler/stmt_visit_class_method.py  (329 lines)

- `def _explicitly_deallocated_locals` - line 18
- `def _scan_dict_locals` - line 62
- `def _prepare_owned_local_cleanup` - line 86
- `def _emit_owned_local_initializers` - line 176
- `def _generate_class_method` - line 219

### source/transpiler/stmt_visit_control.py  (656 lines)

- `def _condition_text` - line 20
- `def _return_temp_open` - line 38
- `def _visit_cache_scoped_body` - line 52
- `def _emit_loop_body` - line 61
- `def _emit_outer_loop_stream_cleanup` - line 69
- `def _assigned_names` - line 75
- `def _drop_assigned_strlen_cache` - line 92
- `def _visit_loop_body_and_close` - line 99
- `def visit_If` - line 113
- `def visit_TryExcept` - line 153
- `def visit_Throw` - line 229
- `def _error_type_hash` - line 242
- `def visit_While` - line 250
- `def visit_DoWhile` - line 277
- `def visit_For` - line 307
- `def visit_Foreach` - line 340
- `def visit_Loop` - line 373
- `def visit_Repeat` - line 395
- `def visit_Return` - line 402
- `def visit_Break` - line 467
- `def visit_Continue` - line 472
- `def visit_InlineAsm` - line 477
- `def visit_Block` - line 496
- `def visit_Match` - line 506

### source/transpiler/stmt_visit_data.py  (697 lines)

- `def _emit_stack_class_construct` - line 32
- `def _emit_dyn_array_push_in_place` - line 185
- `def _emit_tracked_local_reassign` - line 210
- `def visit_Assign` - line 304
- `def _infer_ailang_type` - line 372
- `def _generate_list_comprehension` - line 450
- `def visit_TupleAssign` - line 516
- `def visit_VarDecl` - line 535
- `def visit_RangeVarDecl` - line 622
- `def visit_TypeAlias` - line 664
- `def _type_name_to_ailang` - line 678
- `def visit_Assert` - line 683

### source/transpiler/stmt_visit_data_fields.py  (227 lines)

- `def visit_FieldAssign` - line 16
- `def visit_DictAssign` - line 139

### source/transpiler/stmt_visit_dict.py  (69 lines)

- `def _can_stack_back_dict_literal` - line 10
- `def _emit_stack_dict_literal_assign` - line 18
- `def _emit_dict_literal_assign` - line 52

### source/transpiler/stmt_visit_list_comprehension.py  (47 lines)

- `def _generate_list_comprehension` - line 8

### source/transpiler/stmt_visit_slices.py  (64 lines)

- `def try_emit_fixed_array_slice_alias` - line 9
- `def _is_i64_slice_type` - line 31
- `def _fixed_array_len_hint` - line 36
- `def _is_i64_fixed_array_source` - line 49

### source/transpiler/string_length_plan.py  (72 lines)

- `class StringLengthPlan` - line 16
- `def _literal_byte_length` - line 21
- `def _merge` - line 29
- `def dynamic_string_length_plan` - line 36
- `def grouped_dynamic_terms` - line 56

### source/transpiler/strlen_assign_cache.py  (377 lines)

- `def strlen_cache_var_name` - line 18
- `def _is_integer_type_name` - line 22
- `def _is_known_integer_expr` - line 42
- `def str_known_integer_arg` - line 67
- `def baseconv_known_integer_arg` - line 78
- `def baseconv_len_expr` - line 93
- `def string_length_producer_arg` - line 99
- `def _has_cached_strlen` - line 112
- `def interpolation_known_length` - line 118
- `def is_length_only_string_producer` - line 140
- `def collect_strlen_cache_var` - line 150
- `def update_strlen_cache_after_assign` - line 157
- `def collect_length_only_string_locals` - line 194
- `def emit_length_only_string_reassign` - line 369

### source/transpiler/strlen_cache.py  (52 lines)

- `def lookup_c_strlen_cache` - line 14
- `def enter_strlen_cache_control` - line 31
- `def leave_strlen_cache_control` - line 44

### source/transpiler/type_collector.py  (473 lines)

- `class TypeCollector` - line 25
  - `__init__` - line 28
  - `run` - line 33
  - `_collect_types` - line 44
  - `_collect_record_fields` *(static)* - line 109
  - `_collect_class_fields` *(static)* - line 141
  - `_collect_function_info` *(static)* - line 170
  - `_identify_owned_string_returns` - line 219
  - `_return_values` - line 249
  - `_local_string_ownership` - line 279
  - `_expr_returns_owned_string` - line 321
  - `_expr_is_string` - line 343
  - `_identify_recursive_functions` - line 369
  - `_walk_calls` - line 408
  - `_resolve_method_class` - line 463

### source/transpiler/type_info.py  (330 lines)

- `class TypeInfo` - line 42
  - `is_string_expr_for_scan` - line 191
  - `might_be_string_static` - line 215
  - `might_be_string` - line 250
  - `field_ailang_type` - line 279
  - `class_ptr_type` - line 290

### source/transpiler/type_name_aliases.py  (65 lines)

- `def type_name_to_ailang` - line 62

### source/transpiler/var_typing_scanner.py  (254 lines)

- `class VarTypingScanner` - line 26
  - `run` - line 39
  - `_scan_assigns` - line 67
  - `_process_function` - line 102
  - `_process_assign` - line 114
  - `_process_var_decl` - line 150
  - `_add_string_var` *(static)* - line 185
  - `_add_vec256_var` *(static)* - line 193
  - `_add_vec512_var` *(static)* - line 201
  - `_get_vec_type_from_call` *(static)* - line 209

### source/transpiler/virtual_array_fields.py  (626 lines)

- `class StackArrayFieldPlan` - line 26
- `def _node_children` - line 32
- `def _node_uses_this` - line 40
- `def _is_this_field` - line 46
- `def _is_var_field` - line 54
- `def _is_array_new` - line 63
- `def _is_this_field_push` - line 73
- `def _array_field_names` - line 81
- `def constructor_stack_array_fields` - line 93
- `def constructor_body_replayable_with_stack_arrays` - line 132
- `def class_array_field_uses_are_stack_safe` - line 157
- `def _node_uses_this_array_field_safely` - line 171
- `def function_stack_array_field_uses_are_safe` - line 190
- `def function_stack_array_field_direct_scalar_reads` - line 202
- `def _node_directly_reads_var_array_field` - line 222
- `def function_stack_array_field_method_scalar_reads` - line 242
- `def _node_stack_array_method_scalar_reads` - line 258
- `def _node_directly_reads_this_array_field` - line 288
- `def _method_single_return_expr` - line 306
- `def _node_uses_var_array_field_safely` - line 317
- `def emit_stack_array_constructor_llvm` - line 340
- `def _emit_stack_array_field_init_llvm` - line 416
- `def _emit_stack_array_field_push_llvm` - line 456
- `def emit_stack_array_c_declarations` - line 493
- `def emit_stack_array_constructor_c` - line 511

### source/transpiler/virtual_string_analysis.py  (203 lines)

- `def analyze_virtual_string_materialization` - line 19
- `def _collect_string_fields` - line 54
- `def _scan_field_reads` - line 67
- `def _field_targets` - line 146
- `def _param_is_virtual_transfer_only` - line 162

## ui_dsl

### source/ui_dsl/ast.py  (70 lines)

- `class UiValue` - line 11
  - `as_css` - line 20
- `class UiProperty` - line 31
- `class UiNode` - line 39
  - `property` - line 47
  - `property_map` - line 53
- `class UiInclude` - line 58
- `class UiDocument` - line 66

### source/ui_dsl/export_utils.py  (115 lines)

- `def css_prop` - line 8
- `def int_prop` - line 15
- `def px_prop` - line 27
- `def bool_prop` - line 39
- `def caption_type` - line 46
- `def caption_controls_position` - line 57
- `def caption_title_x` - line 69
- `def caption_node` - line 77
- `def caption_controls_node` - line 81
- `def node_label` - line 88
- `def has_box_props` - line 96
- `def has_position_props` - line 103
- `def has_position_props_for` - line 109
- `def join_style` - line 113

### source/ui_dsl/exporters.py  (676 lines)

- `def ui_document_to_dict` - line 25
- `def _node_to_dict` - line 41
- `def _value_to_dict` - line 58
- `def ui_document_to_html` - line 65
- `def _visible_nodes` - line 249
- `def _node_to_html` - line 254
- `def _container_html` - line 381
- `def _property_grid_html` - line 387
- `def _box_style` - line 432
- `def _text_style` - line 446
- `def _position_style` - line 456
- `def _size_style` - line 479
- `def _fill_style` - line 492
- `def _border_style` - line 502
- `def _border_bottom_style` - line 509
- `def _radius_style` - line 516
- `def _shadow_style` - line 523
- `def _layout_style` - line 532
- `def _window_caption` - line 541
- `def _caption_style` - line 557
- `def _caption_title_style` - line 577
- `def _caption_icon_html` - line 588
- `def _caption_controls_html` - line 603
- `def _caption_button_html` - line 646
- `def write_preview` - line 667

### source/ui_dsl/parser.py  (366 lines)

- `class Token : NamedTuple` - line 21
- `def _token_from_raw` - line 28
- `class UiDslParser` - line 51
  - `__init__` - line 52
  - `peek` - line 68
  - `peek_type` - line 74
  - `peek_text` - line 78
  - `advance` - line 82
  - `expect` - line 89
  - `parse_document` - line 97
  - `_is_include` - line 122
  - `_parse_include` - line 129
  - `_resolve_include` - line 140
  - `_is_node_start` - line 150
  - `_node_colon_offset` - line 157
  - `_parse_node` - line 166
  - `_parse_block` - line 194
  - `_is_property_start` - line 204
  - `_parse_property` - line 210
  - `_consume_property_name` - line 222
  - `_is_property_name` *(static)* - line 231
  - `_parse_value` - line 236
  - `_consume_optional_unit` - line 277
  - `_number_value` *(static)* - line 287
  - `_token_name_value` *(static)* - line 294
  - `_skip_non_ui_construct` - line 299
- `def parse_ui_source` - line 328
- `def parse_ui_file` - line 346

### source/ui_dsl/svg_exporter.py  (485 lines)

- `def ui_document_to_svg` - line 18
- `def _visible_nodes` - line 47
- `def _window_to_svg` - line 52
- `def _caption_icon_svg` - line 82
- `def _caption_controls_to_svg` - line 96
- `def _default_caption_controls_to_svg` - line 160
- `def _svg_caption_button_face` - line 178
- `def _svg_minimize_glyph` - line 184
- `def _svg_maximize_glyph` - line 189
- `def _svg_close_glyph` - line 197
- `def _svg_children` - line 208
- `def _is_svg_absolute` - line 242
- `def _svg_axis` - line 256
- `def _absolute_node_to_svg` - line 276
- `def _property_grid_to_svg` - line 339
- `def _svg_text_top` - line 376
- `def _grid_to_svg` - line 386
- `def _grid_child_to_svg` - line 403
- `def _svg_box_to_svg` - line 465

### source/ui_dsl/validation.py  (56 lines)

- `def validate_ui_document` - line 12
- `def _validate_node` - line 17
- `def _validate_caption_type` - line 39
- `def _validate_control_position` - line 47
