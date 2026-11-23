// Mini816 glue logic for the ATF1504AS-10JU44 (PLCC-44)
//
// Pin numbers match the Logic sheet of the Mini816 schematic.
//
//  * Clocks:   CLK14 = 14.7456 MHz in.
//              PCLK  = CLK14 / 2 = 7.3728 MHz, never stretched (SCC baud rates).
//              PHI2  = CLK14 / 2 for memory cycles: low 1, high 1 CLK14 period.
//                      I/O cycles ($00:C000-$00:CFFF) are stretched: PHI2 stays
//                      high for IO_HIGH periods, so the cycle is about 1.085 us.
//  * Bank latch: BA0-BA3 follow CD0-CD3 while PHI2 is low (the 65C816 puts the
//              bank byte on its data pins then) and hold while PHI2 is high.
//  * Memory map (bank & $0F):
//              $00:0000-$00:BFFF   RAM
//              $00:C000-$00:CFFF   I/O
//              $00:D000-$00:FFFF   flash $7D000-$7FFFF (boot window, vectors)
//              $01-$07             RAM
//              $08-$0F             flash
//  * Strobes:  nRD / nWR are PHI2-qualified, shared by RAM, flash and the SCC.
//              nBUFOE enables the 74AHC245 data buffer while PHI2 is high.
//  * I/O:      nIOC0   $C000-$C0FF (74HC138 splits $C000-$C07F by A4-A6:
//                      VIA $C000, SCC $C010, VDP $C020, spare $C030)
//              nDEVSEL $C080-$C0FF, nIOSEL $C100-$C7FF, nIOSTRB $C800-$CFFF
//              (TIM-Bus, Apple II style, PHI2-qualified)
//  * Selects are only asserted on valid cycles (VDA or VPA high).

module mini816 (
    input  CLK14,           // 14.7456 MHz oscillator
    input  RESB,            // system reset (unused by the logic, clocks keep running)
    input  RW,              // CPU R/W (1 = read)
    input  VDA,
    input  VPA,
    input  [15:7] A,        // CPU address A7-A15
    input  [3:0] CD,        // CPU data D0-D3 (bank byte while PHI2 is low)

    output reg PHI2,        // CPU / VIA / TIM-Bus clock
    output reg PCLK,        // SCC clock
    output A16,
    output A17,
    output A18,
    output nRAMCE,
    output nROMCE,
    output nRD,
    output nWR,
    output nIOC0,
    output nBUFOE,
    output nDEVSEL,
    output nIOSEL,
    output nIOSTRB
);

    // PHI2 high time for an I/O cycle, in CLK14 periods (low time is always 1).
    // 15 gives a 16-period (1.085 us) cycle: em16 profile io_cycle_clks = 8.
    parameter IO_HIGH = 15;

    // ---------------------------------------------------------------- bank latch
    reg [3:0] BA;
    always @(*)
        if (!PHI2)
            BA <= CD;

    // ---------------------------------------------------------------- decode
    wire valid  = VDA | VPA;
    wire bank0  = (BA == 4'h0);
    wire io     = bank0 & (A[15:12] == 4'hC);
    wire boot   = bank0 & (A[15:12] == 4'hD | A[15:12] == 4'hE | A[15:12] == 4'hF);
    wire ram    = ~BA[3] & ~io & ~boot;
    wire rom    = BA[3] | boot;

    assign A16 = boot | BA[0];
    assign A17 = boot | BA[1];
    assign A18 = boot | BA[2];

    assign nRAMCE  = ~(valid & ram);
    assign nROMCE  = ~(valid & rom);
    assign nRD     = ~(PHI2 & RW);
    assign nWR     = ~(PHI2 & ~RW);
    assign nBUFOE  = ~PHI2;

    wire page_c0   = io & (A[11:8] == 4'h0);
    assign nIOC0   = ~(valid & page_c0);
    assign nDEVSEL = ~(valid & PHI2 & page_c0 & A[7]);
    assign nIOSEL  = ~(valid & PHI2 & io & ~A[11] & (A[10:8] != 3'h0));
    assign nIOSTRB = ~(valid & PHI2 & io & A[11]);

    // ---------------------------------------------------------------- clocks
    reg [3:0] cnt;

`ifdef SIM
    // the ATF1504 clears its registers at power-up; tell the simulator
    initial begin PHI2 = 0; PCLK = 0; cnt = 0; end
`endif

    always @(posedge CLK14)
        PCLK <= ~PCLK;

    // PHI2 is low for one CLK14 period.  At the end of it the address, VDA/VPA
    // and bank byte are valid, so the cycle type is known when PHI2 rises.
    always @(posedge CLK14)
        if (!PHI2) begin
            PHI2 <= 1'b1;
            cnt  <= (valid & io) ? IO_HIGH - 1 : 4'd0;
        end else if (cnt == 4'd0)
            PHI2 <= 1'b0;
        else
            cnt <= cnt - 4'd1;

endmodule

//PIN: CHIP "mini816" ASSIGNED TO AN PLCC44
//PIN: RESB    : 1
//PIN: RW      : 2
//PIN: nIOC0   : 4
//PIN: nROMCE  : 5
//PIN: nBUFOE  : 6
//PIN: VPA     : 8
//PIN: CD_0    : 9
//PIN: CD_1    : 11
//PIN: nRAMCE  : 12
//PIN: PCLK    : 14
//PIN: CD_2    : 16
//PIN: CD_3    : 17
//PIN: nIOSEL  : 18
//PIN: nDEVSEL : 19
//PIN: nIOSTRB : 20
//PIN: A17     : 21
//PIN: PHI2    : 24
//PIN: A_11    : 25
//PIN: A_10    : 26
//PIN: A_9     : 27
//PIN: A_7     : 28
//PIN: A_12    : 29
//PIN: A_8     : 31
//PIN: A_14    : 33
//PIN: A_13    : 34
//PIN: A_15    : 36
//PIN: nWR     : 37
//PIN: nRD     : 39
//PIN: A18     : 40
//PIN: A16     : 41
//PIN: CLK14   : 43
//PIN: VDA     : 44
