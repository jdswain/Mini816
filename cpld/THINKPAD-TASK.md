# Task for Claude Code on the ThinkPad: build and program the Mini816 CPLD

You are setting up the CPLD toolchain on Jason's ThinkPad (x86 Linux) for the
Mini816 board. Read `README.md` in this folder first: it describes the design.
Work in this `cpld/` folder. Ask Jason before installing anything system-wide
with sudo, and before anything that writes to a device.

## Context

* Device: Microchip ATF1504AS-10JU44 (PLCC-44, 5 V), on the Mini816 board.
  JTAG is on the board's 2x5 header J2 (ATF_JTAG pinout, as on Jason's other
  65xx boards). TDI and TMS have pull-ups on the board.
* Design: `mini816.v` (Verilog). Pins are fixed by the `//PIN:` comments at
  the end of the file. **The PCB is already routed to these pins, so the
  fitter must keep them.** If it cannot, do not change pins yourself: report
  the fitter's message to Jason, because the fix is a board change.
* Test bench: `tb_mini816.v`. `./build.sh sim` must print PASS.
* Flow: Yosys + hoglet67's atf15xx_yosys (cells.lib / techmap.v), then
  Atmel's `fit1504.exe` under Wine. `build.sh` already holds the Yosys
  script and the fitter call; it was written on a Mac and has never been run
  end to end, so check it against atf15xx_yosys's own `run_yosys.sh` and
  `run_fitter.sh` and fix any differences in options (keep `-preassign keep`).

## Part 1: build the JEDEC file

1. Install `yosys`, `iverilog`, `wine` (32-bit support, `wine32` /
   multiarch on Debian/Ubuntu) and `winetricks` from the distro.
2. Clone https://github.com/hoglet67/atf15xx_yosys to
   `~/Developer/Tools/atf15xx_yosys`.
3. Follow its README to get the fitter files into its `vendor/` folder
   (`fit1504.exe`, `aprim.lib`, `atmel.std`, from Microchip's ProChip
   Designer 5.0.1 installer, installed into a 32-bit Wine prefix). Check the
   SHA-1 sums it lists. Jason may need to download the ProChip zip from
   Microchip himself (it needs a login); ask him if you can't fetch it.
4. `./build.sh sim` → PASS.
5. `ATF15XX=~/Developer/Tools/atf15xx_yosys ./build.sh` → `mini816.jed`.
6. Check `mini816.fit`: every pin in `mini816.pin` placed where assigned,
   and the design fits (64 macrocells max). Report the macrocell and
   product-term usage to Jason.

## Part 2: programming setup

Jason has a Microchip/Atmel USB JTAG programmer (find out which: probably the
ATDH1150USB; check `lsusb` with it plugged in).

Options, in order of preference — check which actually works here:

1. **ATMISP 7.x under Wine** (Microchip's free ISP tool for ATF15xx).
   Install it into the same Wine prefix. Whether it can reach the USB
   programmer through Wine depends on the programmer's driver; test it with
   the programmer plugged in and no board, and say what you find.
2. **If ATMISP can't see the programmer under Wine:** use ATMISP only to
   convert `mini816.jed` to an SVF file (it can write SVF without hardware),
   then play the SVF with OpenOCD (or urjtag) through a JTAG adapter that
   Linux supports. If the Microchip programmer is FTDI-based, OpenOCD's
   ftdi driver may drive it; otherwise any FT232H/FT2232H or USB-Blaster
   clone works. An OpenOCD config for this device looks like:

       adapter speed 400
       transport select jtag
       jtag newtap atf1504 tap -irlen 3 -expected-id 0x0150403f
       svf -progress mini816.svf

   plus the adapter's interface config. Check the IDCODE against the
   ATF1504AS datasheet before trusting it.

Write a short `program.sh` (or a section in `README.md`) with the exact
commands that worked, so programming the three boards is one command.

## When you report back

Tell Jason: tool versions, whether the fit kept every pin, resource usage,
which programming route works, and anything that still needs him (downloads
behind a login, udev rules, buying an adapter). Don't program a board until
he says one is connected and powered.
