.PHONY: check
check:
	printf '%s\n' \
		'lappend auto_path [file join [pwd] vendor bdw]' \
		'package require Bluetcl' \
		'package require Virtual' \
		'package require SignalTypes' \
		'puts "Virtual=[package present Virtual] SignalTypes=[package present SignalTypes]"' \
		| bluetcl
	@bluetcl annotate_bsv_vcd.tcl --help >/dev/null 2>&1; test $$? -eq 2
	@bluetcl report_bsv_utilization.tcl --help >/dev/null 2>&1; test $$? -eq 2
	@tclsh collect_vivado_primitives.tcl --help >/dev/null 2>&1; test $$? -eq 2
	@tclsh report_vivado_bsv_tables.tcl --help >/dev/null 2>&1; test $$? -eq 2
