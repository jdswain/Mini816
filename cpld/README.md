# Mini816 CPLD (ATF1504AS-10JU44)

`mini816.v` is the glue logic: clock generation and I/O cycle stretching,
the bank latch, memory and I/O decode, and the strobes. Pin numbers are the
`//PIN:` lines at the end of the file. They match the Logic sheet of the
schematic, so keep the two in step.

| File | Purpose |
|---|---|
| `mini816.v` | the design |
| `tb_mini816.v` | test bench: bus cycles like a 65C816, checks cycle lengths, the bank latch and every select |
| `build.sh` | simulate, synthesise (Yosys), fit (Atmel `fit1504.exe` under Wine) |

## Behaviour

* CLK14 = 14.7456 MHz in. PCLK = 7.3728 MHz out to the SCC, never stretched.
* PHI2 is low for one CLK14 period and high for one. That's a 135.6 ns cycle,
  7.3728 MHz.
* FDCRST (pin 18) = NOT RESB: the 82077AA floppy controller's active-high
  reset (rev B; this pin was the TIM-Bus /IOSEL in rev A, and pins 19 and 20
  are now spare).
* For a valid (VDA or VPA) access to $00:C000-$00:CFFF, PHI2 stays high for
  15 periods instead. That's a 1.085 us cycle: `IO_HIGH`, or io_cycle_clks = 8
  in the em16 profile. The cycle type is decided at the end of PHI2 low, so
  the CPU's address and bank byte must be valid and decoded within one CLK14
  period (67.8 ns). Check that against the W65C816S address delay (tADS) at
  5 V, plus about 10 ns through the CPLD.
* The bank latch is transparent while PHI2 is low. A16-A18 and the chip
  selects come straight from it, so they are valid early in the cycle.

## Building on macOS (Apple Silicon)

1. Tools from Homebrew:

       brew install yosys icarus-verilog

2. Wine: Gcenx's Wine build. It runs x86 Windows programs, 32-bit included,
   through Rosetta 2:

       softwareupdate --install-rosetta --agree-to-license
       brew install --cask --no-quarantine wine-stable

3. The flow: `git clone https://github.com/hoglet67/atf15xx_yosys.git`
   somewhere, for example `~/Developer/Tools/atf15xx_yosys`.

4. The fitter files go in its `vendor/` folder: `fit1504.exe`, `aprim.lib`
   and `atmel.std` (and `fit1502.exe` / `fit1508.exe` if you like). They come
   from Microchip's ProChip Designer (`ProChip5.0.1.zip`).
   * The README in atf15xx_yosys installs it with a 32-bit Wine prefix and
     winetricks. Current macOS Wine doesn't do 32-bit prefixes, so the
     installer may not run there.
   * If it doesn't, extract the files on the Linux laptop, following the
     atf15xx_yosys README, or on any Windows machine, and copy them across.
   * The README lists the expected SHA-1 sums.

5. Simulate, then build:

       ./build.sh sim
       ATF15XX=~/Developer/Tools/atf15xx_yosys ./build.sh

   This writes `mini816.jed`, plus the fitter report `mini816.fit`. Check
   that it says the pins were kept as assigned.

If Wine on macOS won't run the fitter, the same `build.sh` works on the Linux
laptop with `wine` installed, or you can run the atf15xx_yosys scripts there
as its README describes.

## Programming

Program `mini816.jed` with ATMISP and the Microchip programmer on the
ThinkPad, over the JTAG header (J2). JTAG stays enabled, and TDI and TMS have
pull-ups both on the board and in the device.
