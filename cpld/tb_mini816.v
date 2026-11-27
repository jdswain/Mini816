// Test bench for mini816.v (Icarus Verilog):
//   iverilog -o tb tb_mini816.v mini816.v && vvp tb
// Drives the CPU side like a 65C816 (address and bank byte 30 ns after PHI2
// falls, CD switches to data 10 ns after PHI2 rises) and checks cycle length,
// bank latch, chip selects and strobes.
`timescale 1ns/1ps

module tb;
    reg  CLK14 = 0;
    reg  RESB = 0, RW = 1, VDA = 0, VPA = 0;
    reg  [15:0] ADDR = 0;
    reg  [3:0]  CDV = 0;
    wire PHI2, PCLK, A16, A17, A18, nRAMCE, nROMCE, nRD, nWR, nIOC0, nBUFOE,
         FDCRST;

    mini816 dut(.CLK14(CLK14), .RESB(RESB), .RW(RW), .VDA(VDA), .VPA(VPA),
                .A(ADDR[15:7]), .CD(CDV), .PHI2(PHI2), .PCLK(PCLK),
                .A16(A16), .A17(A17), .A18(A18), .nRAMCE(nRAMCE), .nROMCE(nROMCE),
                .nRD(nRD), .nWR(nWR), .nIOC0(nIOC0), .nBUFOE(nBUFOE),
                .FDCRST(FDCRST));

    // 14.7456 MHz: 67.817 ns period
    always #33.9084 CLK14 = ~CLK14;

    integer errors = 0;
    task check(input cond, input [8*64-1:0] msg);
        if (!cond) begin
            errors = errors + 1;
            $display("FAIL at %0t: %0s", $time, msg);
        end
    endtask

    // One bus cycle: bank, address, valid flags, R/W.  Returns when PHI2 falls.
    real t_rise, t_fall, t_prev_fall;
    reg [2:0] s_a; reg s_ram, s_rom, s_io;
    task cycle(input [7:0] bank, input [15:0] addr, input vda, input vpa, input rw,
               input expect_io,
               input exp_ram, input exp_rom, input [2:0] exp_a1816,
               input exp_ioc0, input exp_devsel, input exp_iosel, input exp_iostrb);
        begin
            // PHI2 is low: present address and bank byte after tADS = 30 ns
            #30;
            ADDR = addr; VDA = vda; VPA = vpa; RW = rw; CDV = bank[3:0];
            @(posedge PHI2); t_rise = $realtime;
            #10 CDV = ~bank[3:0];                 // data replaces the bank byte
            #20;                                  // mid high phase: check
            check({A18, A17, A16} === exp_a1816, "A16-A18");
            check(nRAMCE === ~exp_ram, "nRAMCE");
            check(nROMCE === ~exp_rom, "nROMCE");
            check(nRD === ~rw, "nRD");
            check(nWR === rw, "nWR");
            check(nBUFOE === 1'b0, "nBUFOE");
            check(nIOC0 === ~exp_ioc0, "nIOC0");
            check(FDCRST === ~RESB, "FDCRST");
            s_a = {A18, A17, A16}; s_ram = ~nRAMCE; s_rom = ~nROMCE; s_io = ~nIOC0;
            @(negedge PHI2); t_fall = $realtime;
            #1;
            check(nRD === 1'b1 && nWR === 1'b1 && nBUFOE === 1'b1, "strobes off in low phase");
            if (expect_io)
                check((t_fall - t_rise) > 1010 && (t_fall - t_rise) < 1020, "I/O high time 15 x 67.8 ns");
            else
                check((t_fall - t_rise) > 67 && (t_fall - t_rise) < 69, "memory high time 67.8 ns");
            $display("  bank %02h addr %04h %s  cycle %7.1f ns  A18-16=%b  ram=%b rom=%b ioc0=%b",
                         bank, addr, rw ? "R" : "W", t_prev_fall > 0 ? t_fall - t_prev_fall : 0.0,
                         s_a, s_ram, s_rom, s_io);
            t_prev_fall = t_fall;
        end
    endtask

    initial begin
        t_prev_fall = 0;
        #20 RESB = 1;
        // let the clocks settle into step
        repeat (3) @(negedge PHI2);

        //      bank   addr    vda vpa rw  io  ram rom a18-16 ioc0 dev  iosel strb
        cycle(8'h00, 16'h0200, 1, 0, 1,  0,  1,  0, 3'b000, 0,   0,   0,    0);  // RAM bank 0
        cycle(8'h00, 16'hBFFF, 1, 0, 0,  0,  1,  0, 3'b000, 0,   0,   0,    0);  // top of bank 0 RAM, write
        cycle(8'h00, 16'hD000, 0, 1, 1,  0,  0,  1, 3'b111, 0,   0,   0,    0);  // boot window
        cycle(8'h00, 16'hFFFC, 1, 0, 1,  0,  0,  1, 3'b111, 0,   0,   0,    0);  // reset vector
        cycle(8'h05, 16'h1234, 1, 0, 1,  0,  1,  0, 3'b101, 0,   0,   0,    0);  // RAM bank 5
        cycle(8'h07, 16'hC000, 1, 0, 0,  0,  1,  0, 3'b111, 0,   0,   0,    0);  // bank 7 $C000 is RAM
        cycle(8'h08, 16'h5555, 1, 0, 0,  0,  0,  1, 3'b000, 0,   0,   0,    0);  // flash command address
        cycle(8'h0F, 16'hFFFF, 1, 0, 1,  0,  0,  1, 3'b111, 0,   0,   0,    0);  // top of flash
        cycle(8'h18, 16'h0010, 1, 0, 1,  0,  0,  1, 3'b000, 0,   0,   0,    0);  // bank $18 mirrors $08
        cycle(8'h10, 16'hC010, 1, 0, 1,  1,  0,  0, 3'b000, 1,   0,   0,    0);  // bank $10 mirrors bank 0 I/O
        cycle(8'h00, 16'hC000, 1, 0, 1,  1,  0,  0, 3'b000, 1,   0,   0,    0);  // VIA
        cycle(8'h00, 16'hC013, 1, 0, 0,  1,  0,  0, 3'b000, 1,   0,   0,    0);  // SCC write
        cycle(8'h00, 16'hC021, 1, 0, 1,  1,  0,  0, 3'b000, 1,   0,   0,    0);  // VDP status
        cycle(8'h00, 16'hC0A0, 1, 0, 1,  1,  0,  0, 3'b000, 1,   1,   0,    0);  // rev A DEVSEL area: still an I/O cycle
        cycle(8'h00, 16'hC300, 1, 0, 1,  1,  0,  0, 3'b000, 0,   0,   1,    0);  // rev A IOSEL area
        cycle(8'h00, 16'hC800, 1, 0, 1,  1,  0,  0, 3'b000, 0,   0,   0,    1);  // rev A IOSTRB area
        cycle(8'h00, 16'hC000, 0, 0, 1,  0,  0,  0, 3'b000, 0,   0,   0,    0);  // internal cycle: no select, no stretch
        cycle(8'h00, 16'h0300, 1, 1, 1,  0,  1,  0, 3'b000, 0,   0,   0,    0);  // back to RAM at full speed

        // PCLK must be an unstretched 7.3728 MHz square wave
        begin : pclk
            real a, b;
            @(posedge PCLK) a = $realtime;
            @(posedge PCLK) b = $realtime;
            check((b - a) > 135 && (b - a) < 136, "PCLK period 135.6 ns");
        end

        if (errors == 0) $display("PASS: all checks");
        else $display("%0d check(s) failed", errors);
        $finish;
    end
endmodule
