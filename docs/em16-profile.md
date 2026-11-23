# Mini816: hardware specification for an em16 profile

This describes the Mini816 (rev A schematic, `~/Developer/Hardware/Mini816`,
with the keyboard in `~/Developer/Hardware/Mini816-Keyboard`)
as an emulator needs to see it. It is written for an agent adding a Mini816
profile to em16. Where the hardware is not yet fixed (the CPLD Verilog, the
the SD module) the value is marked **provisional**: implement it as a
profile parameter rather than a constant.

Source of truth for anything not covered here: the KiCad schematic and the
notes on each sheet.

## 1. Summary

| Item | Part | Emulation notes |
|---|---|---|
| CPU | W65C816S | 7.3728 MHz PHI2 |
| RAM | AS6C4008, 512K | banks $00-$07 |
| ROM | SST39SF040, 512K flash | banks $08-$0F, plus 12K boot window in bank 0; in-system programmable |
| Glue | ATF1504AS CPLD | bank latch, decode, clock, I/O cycle stretching |
| VIA | W65C22N at $00:C000 | 64-key keyboard and joystick (scanned matrix), SD card (bit-banged SPI), sound, VDP interrupt |
| SCC | Z85C30 at $00:C010 | two async serial ports; channel A is the console |
| Video | TMS9118 at $00:C020 | 16K VRAM, NTSC composite, 256x192 |
| Expansion | TIM-Bus | Apple II slot style selects; no cards by default |

Interrupts: VIA, SCC and TIM-Bus cards share the CPU's IRQB (open drain,
wired OR). The VDP interrupt does not go to IRQB directly; it goes to VIA
CB1. NMIB comes from a push button and the TIM-Bus.

## 2. Clocks and timing

* Master clock 14.7456 MHz into the CPLD.
* CPU PHI2 = 7.3728 MHz (one CPU cycle = 135.6 ns) for memory accesses.
* **I/O cycle stretching:** every access to $00:C000-$00:CFFF (VIA, SCC,
  VDP, TIM-Bus) has PHI2 high for 15 master clocks instead of 1, so the
  access takes 16 master clocks = 1.085 us. That's the time of 8 normal CPU
  cycles: model it as `io_cycle_clks` = 8 (fixed by `IO_HIGH` in
  `cpld/mini816.v`).
  Only cycles with VDA or VPA high are I/O accesses; internal operation
  cycles (VDA = VPA = 0) are never stretched and never select a device.
* The VIA is clocked by PHI2, so its timers decrement **once per CPU cycle**,
  including a stretched I/O cycle (which counts as one tick, not 8). Timer
  rates are therefore in CPU cycles, not wall time.
* SCC PCLK = 7.3728 MHz, never stretched (exact baud rates).
* VDP has its own 10.738635 MHz crystal, independent of the CPU (NTSC timing).
* No wait states on RAM or flash.

## 3. Memory map

The CPLD latches bank bits BA0-BA3 only, so the 24-bit address space repeats
every 16 banks: **effective bank = bank AND $0F**. Everything below,
including the I/O page and boot window, therefore also appears in banks
$10, $20, ... $F0.

| CPU address (bank & $0F) | Device | Physical address in device |
|---|---|---|
| $00:0000-$00:BFFF | RAM | $00000-$0BFFF |
| $00:C000-$00:CFFF | I/O page (section 4) | |
| $00:D000-$00:FFFF | Flash boot window | $7D000-$7FFFF (top 12K of the flash) |
| $01:0000-$07:FFFF | RAM | (bank * $10000) + addr |
| $08:0000-$0F:FFFF | Flash | ((bank - 8) * $10000) + addr |

* RAM at $00:C000-$00:FFFF (physical $0C000-$0FFFF) exists but is not
  reachable from the CPU.
* Reset and interrupt vectors at $00:FFE0-$00:FFFF are flash $7FFE0-$7FFFF.
  The flash also appears at $0F:D000-$0F:FFFF.
* Reads from RAM or flash have no side effects. Writes to RAM are normal.
* Writes to flash go to the flash state machine (section 5), never directly
  to the array.

### Profile options (jumpers and smaller parts)

* `ram_size`: 512K (default) or 128K. With a 128K AS6C1008 the RAM_SIZE
  jumper ties pin 30 (CE2) high, and RAM banks $02-$07 mirror $00-$01
  (physical address AND $1FFFF).
* `flash_size`: 512K (default), 256K or 128K (SST39SF020A/010A). Smaller
  chips mirror: physical address AND (size - 1). The boot window always maps
  to the top of the chip.
* `flash_write_enable`: true (default). The FLASH_WRITE jumper removed means
  flash /WE is held high: all flash writes are ignored, including command
  sequences.

## 4. I/O page ($00:C000-$00:CFFF)

| Range | Select | Device, register |
|---|---|---|
| $C000-$C00F | VIA | W65C22 register = A3-A0 |
| $C010-$C01F | SCC | A1 = A/~B, A0 = D/~C; mirrored every 4 bytes |
| $C020-$C02F | VDP | A0 = MODE; mirrored every 2 bytes |
| $C030-$C03F | spare (IO_SP3) | nothing fitted: open bus |
| $C040-$C07F | none | open bus |
| $C080-$C0FF | TIM-Bus /DEVSEL | slot n at $C080 + n*16 (n = 0-7) |
| $C100-$C7FF | TIM-Bus /IOSEL | slot n at $Cn00-$CnFF (n = 1-7) |
| $C800-$CFFF | TIM-Bus /IOSTRB | shared expansion ROM space |

SCC register addresses:

| Address | Register |
|---|---|
| $C010 | channel B control |
| $C011 | channel B data |
| $C012 | channel A control |
| $C013 | channel A data |

VDP register addresses:

| Address | Read | Write |
|---|---|---|
| $C020 | VRAM data | VRAM data |
| $C021 | status register | register / address setup |

**Open bus:** reads from unselected addresses return a floating bus. Return
$FF (recommended), or make it a profile option.

## 5. Flash: SST39SF040 behaviour

Model the JEDEC/SST software command set. Command addresses are **chip
offsets** (A14-A0 of the chip address), so software issues commands through
banks $08-$0F, for example $08:5555 and $08:2AAA. The boot window cannot
reach chip offset $5555, so commands written there are not recognised.

| Operation | Bus cycles (chip offset / data) |
|---|---|
| Byte program | 5555/AA, 2AAA/55, 5555/A0, addr/data |
| Sector erase (4K) | 5555/AA, 2AAA/55, 5555/80, 5555/AA, 2AAA/55, sector/30 |
| Chip erase | 5555/AA, 2AAA/55, 5555/80, 5555/AA, 2AAA/55, 5555/10 |
| Software ID entry | 5555/AA, 2AAA/55, 5555/90 |
| Software ID exit | any address/F0, or 5555/AA, 2AAA/55, 5555/F0 |

* In ID mode, offset 0 reads $BF (SST) and offset 1 reads the device ID:
  $B7 for the 040, $B6 for the 020A, $B5 for the 010A.
* Programming can only change 1s to 0s: new byte = old AND data. Erase sets
  a whole 4K sector, or the chip, to $FF.
* Timing, optional: byte program about 14-20 us; sector erase about 18-25 ms;
  chip erase about 70-100 ms.
* During an operation, reads return status:
  * DQ7 = complement of the data being written (data# polling).
  * DQ6 toggles on each read (toggle bit).
  
  Completing instantly is acceptable for a first version. If timing is
  modelled, programs must also run from RAM during an operation, because the
  array cannot be read while busy.
* Persist the flash image to a file.

## 6. VIA (W65C22N) at $C000

Standard 6522 register set, timers and shift register. IRQ goes to IRQB.

### Port A: keyboard rows (input)

* PA0-PA7 = ROW0-ROW7, pulled up.
* A row reads **0** when a key in the currently selected column is pressed.
* Port A is input only in practice. If software sets DDRA bits to output,
  emulate the pin driving as normal.

### Port B

| Bit | Dir | Function |
|---|---|---|
| PB0-PB2 | out | Keyboard column select, bits 0-2 (bit 3 is CA2). A 74HC154 on the keyboard PCB drives the selected column low. |
| PB3 | out | SD card MOSI |
| PB4 | out | SD card SCK |
| PB5 | out | SD card CS, active low, pulled up |
| PB6 | in | SD card MISO, pulled up. Bit 6 lets `BIT $C000` test it into the V flag. |
| PB7 | out | Sound: timer 1 PB7 square-wave output, when ACR bit 7 is set, or the plain ORB bit |

### Control lines

| Pin | Function |
|---|---|
| CA1 | SD card detect, pulled up. Polarity depends on the module: make it a profile option, default low = card present. |
| CA2 | Keyboard column select bit 3, pulled up. Software drives it as a manual output (PCR CA2 control = 110 low / 111 high). |
| CB1 | VDP /INT. The VDP pulls it low while its interrupt flag F is set and interrupts are enabled (register 1 bit 5); the VIA sees a falling edge. Pulled up. |
| CB2 | spare, pulled up, not connected. Can be used as a second sound voice via the shift register in free-run mode. |

### Keyboard matrix

The column number is 4 bits: PB0-PB2 give bits 0-2 and CA2 gives bit 3,
so select column c with PB = c AND 7 and CA2 = c >> 3. A pressed key reads
0 on its row while its column is selected. A diode on each key and joystick
line means multiple presses do not ghost, so any combination is readable.

* Columns 0-7 hold the 64-key keyboard. Its layout is
  `keyboard-layout-2.json`, a keyboard-layout-editor file: 15 / 14 / 13 /
  12 keys on the main rows, plus an inverted-T arrow cluster and a bottom
  row of Caps, Super, Alt, Space, Alt, Super.
* Each matrix row holds 8 physically neighbouring keys, along the physical
  key rows. The columns are chosen to keep the column tracks short. The
  Matrix field on each switch in the keyboard schematic gives its position.
* Column 15 is the joystick: an Atari-style DE-9 port on the keyboard PCB.
  Columns 8-14 are not connected and read $FF.

| Row \ Col | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 15 (joystick) |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Esc | 7 | 2 | 6 | 4 | 1 | 3 | 5 | Up |
| 1 | 8 | 9 | - | 0 | = | Del | `` ` `` | \\ | Down |
| 2 | U | I | P | [ | O | Y | T | ] | Left |
| 3 | Tab | Control | A | S | E | Q | W | R | Right |
| 4 | J | K | ; | D | L | H | G | F | Fire |
| 5 | M | , | . | / | ' | Enter | RShift | Up | (none) |
| 6 | Caps | LShift | Z | X | C | N | B | V | (none) |
| 7 | LSuper | Space | RAlt | LAlt | RSuper | Down | Left | Right | (none) |

Notes on the labels:

* Both Shift keys, both Alt keys and both Super keys are separate matrix
  positions, so software can tell them apart.
* `Control` is the key left of A, where Caps Lock usually is. `Caps` is
  bottom left.
* The keycaps are labelled as on a US PC layout, with shifted symbols on the
  same keys: for example Shift+1 = !, Shift+' = ". Character mapping is
  software's job. The emulator only reports matrix positions.
* Map host keys to matrix positions by key identity (host scancode), not by
  the character typed. Map the host arrow keys to the matrix arrow keys, and
  provide separate host keys or a game controller for the joystick.

### Sound

PB7 drives a small speaker through a transistor: it's a 1-bit output.
Generate audio from the PB7 level over time, using the timer 1 free-run
toggle or software toggling of ORB bit 7. Optionally add CB2 shift-register
output, mixed in, as a second voice.

## 7. SD card (bit-banged SPI on the VIA)

* The card is a microSD module with its own level shifting, in SPI mode.
* Mode 0: the card samples MOSI on the SCK rising edge. MISO changes after
  the falling edge; present the next bit on MISO after each falling edge.
* CS is active low. When CS is high, MISO reads 1 (pull-up).
* Emulate an SDHC/SDXC card in SPI mode backed by an image file. Commands
  needed:
  * CMD0, CMD8, CMD55 + ACMD41, CMD58
  * CMD16 (accept 512)
  * CMD17 / CMD24: single block read/write
  * CMD18 / CMD25 / CMD12: optional multi-block
  * CMD13, CMD9 / CMD10: optional CSD/CID
  
  Respond with standard R1/R3/R7 responses, data tokens ($FE) and data
  response tokens.
* Card detect on VIA CA1 follows "image mounted" (see the polarity option in
  section 6).

## 8. SCC (Z85C30) at $C010

* Standard Z8530 register model: WR0-WR15 and RR0-RR15, with the register
  pointer in WR0. Async mode is enough to start; sync/SDLC is optional.
* PCLK = 7.3728 MHz. Baud generator: rate = PCLK / (2 * clock_mode *
  (TC + 2)). In x16 mode: TC 0 = 115200 baud, TC 22 = 9600 baud.
* /RTxCA, /RTxCB, /TRxCA, /TRxCB and /SYNCA, /SYNCB are pulled up and carry
  no clocks. Software must use the baud generator, clocked from PCLK.
* /DCDA and /DCDB are tied low (asserted), so RR0 DCD = 1 and the receiver
  is always enabled under Auto Enables.
* /CTSA and /CTSB come from the serial headers, pulled up. With nothing
  attached, CTS is inactive (RR0 CTS = 0). With a host attached, assert it
  unless the host is applying flow control.
* /RTSA and /RTSB go to the host's CTS: use them for flow control towards
  the host.
* /INTACK and IEI are tied high. There's no interrupt acknowledge cycle:
  software reads RR2 (the modified vector) or RR3 (pending bits). /INT is
  open drain onto IRQB.
* **The SCC has no reset pin wired.** It is not reset by RESB, so its
  power-on state persists across a CPU reset. Software resets it with WR9
  ($C0 = hardware reset). Emulate power-on as reset, and leave the SCC alone
  on a CPU reset.
* **Channel A** is the console. Its header takes a USB-serial module that
  also powers the board. Connect it to the emulator's console: terminal,
  stdio or a pty. **Channel B** is a second port: connect it to a pty or a
  socket, or leave it unconnected.
* Recovery time between SCC accesses can be ignored.

## 9. VDP (TMS9118) at $C020

* Behaves as a TMS9918A (TMS9118 = 9918A with a different DRAM interface):
  * 16K VRAM.
  * Registers R0-R7 and the status register.
  * Graphics I, Graphics II, Multicolour and Text modes.
  * 32 sprites, 4 per line, with the 5th-sprite flag and the coincidence
    flag.
  * Fixed 16-entry palette, with colour 0 transparent.
* Port protocol, the standard one:
  * Write address/register: two writes to $C021.
  * Then read or write VRAM via $C020, with auto-increment.
  * Reading $C021 returns the status register and clears F, 5S and C.
  * The address latch flip-flop is reset by a status read.
* NTSC timing: 262 lines per frame, 342 pixel clocks per line, about
  59.94 Hz.
* The F flag is set at the end of the active display (after line 191).
* /INT is asserted while F = 1 and R1 bit 5 (IE) = 1, and goes to VIA CB1
  (section 6), not to IRQB.
* Output: composite NTSC to a small LCD monitor. Render 256x192 with the
  usual border, using a standard TMS9918A palette.
* VRAM access timing: the real chip needs gaps between CPU VRAM accesses, up
  to several microseconds in some modes. Accept accesses at any rate (most
  emulators do). Optionally warn when accesses are closer than the
  mode-dependent minimum.
* The VDP is reset by RESB.

## 10. TIM-Bus expansion

* Apple II slot pinout. Only A0-A7 and D0-D7 are carried, plus /DEVSEL,
  /IOSEL, /IOSTRB, R/W, PHI2, RESB, IRQB, NMIB and RDY.
* No cards fitted by default: those address ranges read as open bus.
* Leave a hook for cards to be added later, with slot n at $C080 + n*16,
  $Cn00 and the shared $C800 space.

## 11. Reset and interrupts

| Signal | Sources | Notes |
|---|---|---|
| RESB | Power-on, reset button | Resets CPU, CPLD, VIA, VDP and TIM-Bus cards. The SCC is **not** reset. |
| IRQB | VIA IRQ, SCC /INT, TIM-Bus /IRQ | Level, wired OR (low if any source is asserting) |
| NMIB | NMI button, TIM-Bus /NMI | Falling edge. Expose the button as an emulator command. |
| ABORTB | Pulled up | Unused |
| RDY | Pulled up | WAI pulls it low until an interrupt |
| BE | Pulled up | Always enabled |

* After reset the CPU is in emulation mode and fetches the reset vector
  from $00:FFFC, which is flash $7FFFC.
* MiniMon, the boot monitor, lives at the top of flash, from $7D000
  upwards, in the boot window.

## 12. Suggested profile parameters

| Parameter | Default | Values |
|---|---|---|
| `cpu_clock_hz` | 7372800 | |
| `io_cycle_clks` | 8 | set by the CPLD (`IO_HIGH` = 15) |
| `ram_size` | 524288 | 524288 or 131072 |
| `flash_size` | 524288 | 524288, 262144 or 131072 |
| `flash_image` | | path, persisted |
| `flash_write_enable` | true | |
| `open_bus_value` | $FF | |
| `sd_image` | none | path |
| `sd_cd_active_low` | true | |
| `scc_a` | console | console / pty / socket / none |
| `scc_b` | none | console / pty / socket / none |
| `keymap` | section 6 table | host key to (column, row) |
| `joystick` | arrows + fire key | arrows + key / gamepad |

## 13. Open items (not yet fixed in hardware)

1. SD module card-detect polarity.
2. Whether CB2 is used as a second sound voice.
