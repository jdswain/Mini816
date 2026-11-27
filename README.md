# Mini816 (rev B)

This is the `v2` branch: rev B adds a floppy controller, moves the CPU
and flash to PLCC, drops TIM-Bus, and puts the external connectors along
the back edge for a case like the Atari ST (internal floppy drive and
keyboard). Rev A is on `main`.

A small 65C816 teaching computer: a gift kit for two first-year
computer science students. Through-hole parts throughout, for soldering
practice.

* W65C816S (PLCC-44 socket) at 7.3728 MHz, from a 14.7456 MHz oscillator
  divided in the CPLD
* 512K SRAM (AS6C4008-55) and 512K flash (SST39SF040, PLCC-32 socket): banks $00-$07
  RAM, $08-$0F flash. 128K parts fit the same sockets (see the Memory sheet
  for the RAM_SIZE jumper)
* ATF1504AS CPLD (PLCC-44 socket): bank latch, decode, strobes, clock
  generation and stretching for I/O cycles
* W65C22N VIA: 64-key keyboard on its own PCB (`../Mini816-Keyboard`),
  scanned through a 4-bit column select (PB0-PB2 + CA2) into a 74HC154 on
  the keyboard; Atari joystick (DE-9 on the keyboard PCB) on column 15; SD card over bit-banged SPI
  (microSD module); timer-1 sound; VDP interrupt on CB1, floppy interrupt on CB2
* Z85C30 SCC: two TTL serial ports on FTDI-style 6-pin headers; channel A
  takes a USB-C USB-serial module, which can also power the board
* TMS9118 video (NTSC composite, 256x192, 32 sprites) with two TMS4416
  VRAMs, driving a small composite LCD monitor
* Intel 82077AA floppy controller (PLCC-68 socket) at $C030, PC 34-pin
  drive header and 4-pin drive power header, for a 3.5" 720K/1.44M drive;
  no DMA (the CPU moves the data through the FIFO)
* 12 V barrel jack, metal toggle switch, Recom R-78K5.0-2.0 switching
  regulator (2 A, enough for the floppy drive) for 5 V; 12 V on a 2-pin header for the composite LCD. A jumper
  can instead take 5 V from the USB-serial module (bench use, no LCD)

All fine-pitch parts (USB, USB-serial chip, microSD socket) are on
plug-in modules, so the board itself is through-hole only.

Sheets: CPU, Memory, Logic, IO, Serial, Video, Floppy, Power. Each sheet
carries notes on its part of the design.

Symbols: `lib/65Parts.kicad_sym` is a copy of the 65-16 library;
`lib/Mini816.kicad_sym` holds the PLCC-44 and PDIP-40 W65C816S, W65C22 and Z85C30,
the TMS9118, TMS4416 and DS1813 (plus the now-unused ERM240128FS-2).

The CPLD pin assignment is on the Logic sheet; the Verilog must match it.

`docs/em16-profile.md` describes the machine for emulation (em16).

Board layout (rev B): 200 x 125 mm, 4 layers (inner 1 GND plane, inner 2
signals with a +5V pour). Back edge, left to right: 12 V jack, power
switch, LCD 12 V header, RCA video, SD module, serial A, serial B. Front
edge: keyboard ribbon header. Right edge: floppy drive header and drive
power. Four M3 mounting holes.
