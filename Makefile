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
