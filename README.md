# BlueLens

BlueLens reads hierarchy and type information from elaborated Bluespec
SystemVerilog (BSV) designs.

The first utility, `annotate_bsv_vcd.tcl`, uses BlueTcl hierarchy and type
metadata to add a structured BSV view to an existing VCD. It does not analyze
waveform values.

## Requirements

- Bluespec Compiler tools, including `bluetcl`
- An elaborated Bluesim build containing the requested top module
- A VCD generated from that build

## Usage

Run the utility from the root of the BSV project:

```sh
bluetcl /path/to/bluelens/annotate_bsv_vcd.tcl \
  --top mkTop \
  --build build \
  --vcd build/dump.vcd \
  --out build/dump.typed.vcd
```

Useful options:

```text
--include GLOB    Select BSV hierarchy paths; may be repeated
--hide-source     Remove mapped declarations from the physical VCD hierarchy
```

Without explicit paths, BlueLens looks under `hdl/build` relative to the
current working directory.
