`timescale 1ns/1ps
`include "AudDSP.sv"

module tb_AudDSP;

    // Signals
    logic        clk, rst_n;
    logic        daclrck;
    logic        start, pause, stop;
    logic [3:0]  speed;
    logic        fast, slow_0, slow_1;
    logic signed [15:0] sram_data, dac_data;
    logic [19:0] sram_addr;
    
    logic signed [15:0] test_memory [0:1023];

    // DUT
    AudDSP dut (
        .i_rst_n(rst_n),
        .i_clk(clk),
        .i_start(start),
        .i_pause(pause),
        .i_stop(stop),
        .i_speed(speed),
        .i_fast(fast),
        .i_slow_0(slow_0),
        .i_slow_1(slow_1),
        .i_daclrck(daclrck),
        .i_sram_data(sram_data),
        .o_dac_data(dac_data),
        .o_sram_addr(sram_addr)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk;  // 50MHz
    end

    initial begin
        daclrck = 0;
        // forever #15625 daclrck = ~daclrck;  // 32kHz
        forever #110 daclrck = ~daclrck; // for simulation
    end

    // Memory model
    logic [19:0] prev_addr;
    integer access_count;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_addr <= 20'hFFFFF;
            access_count <= 0;
            sram_data <= 16'd0;
        end else begin
            if (sram_addr < 1024) begin
                sram_data <= test_memory[sram_addr];
                
                if (sram_addr != prev_addr) begin
                    access_count <= access_count + 1;
                    $display("[%0t] SRAM[%4d] = %6d", $time, sram_addr, test_memory[sram_addr]);
                end
                prev_addr <= sram_addr;
            end else begin
                sram_data <= 16'd0;
            end
        end
    end

    // Monitor DAC output
    integer output_count;
    
    always @(posedge daclrck or negedge rst_n) begin
        if (!rst_n) begin
            output_count <= 0;
        end else if (dut.playing_r) begin
            output_count <= output_count + 1;
            $display("[%0t] OUT[%2d] = %6d (Mode=%s, Speed=%0d)", 
                     $time, output_count + 1, dac_data, dut.mode_r.name(), speed);
        end
    end

    // Display state changes
    always @(dut.fetch_state_r) begin
        $display("[%0t] >>> Fetch State: %0d", $time, dut.fetch_state_r);
    end

    // Helper tasks
    task init_memory(input string pattern);
        integer i;
        case (pattern)
            "linear": begin
                for (i = 0; i < 1024; i++) begin
                    test_memory[i] = i * 8;
                end
                $display("Memory: LINEAR (addr * 8 = data)");
            end
            "step": begin
                for (i = 0; i < 1024; i++) begin
                    test_memory[i] = (i / 100) * 1000;
                end
                $display("Memory: STEP pattern");
            end
            "ramp": begin
                for (i = 0; i < 1024; i++) begin
                    test_memory[i] = i * 32;
                end
                $display("Memory: RAMP pattern");
            end
            default: begin
                for (i = 0; i < 1024; i++) begin
                    test_memory[i] = i;
                end
            end
        endcase
    endtask

    task reset_system();
        $display("\n========== RESET ==========");
        rst_n = 0;
        start = 0;
        pause = 0;
        stop = 0;
        speed = 0;
        fast = 0;
        slow_0 = 0;
        slow_1 = 0;
        repeat(2) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
    endtask

    task test_fast(input [3:0] spd, input integer samples);
        $display("\n===== TEST: Fast %0dx (expect %0d samples) =====", spd, samples);
        @(posedge clk);
        speed = spd;
        fast = 1;
        slow_0 = 0;
        slow_1 = 0;
        start = 1;
        @(posedge clk);
        start = 0;
        
        repeat(samples) @(posedge daclrck);
        
        @(posedge clk);
        stop = 1;
        @(posedge clk);
        stop = 0;
        
        $display(">>> Completed: %0d outputs, %0d SRAM accesses", output_count, access_count);
        repeat(5) @(posedge clk);
    endtask

    task test_slow_const(input [3:0] spd, input integer samples);
        $display("\n===== TEST: Slow Const 1/%0dx (expect %0d samples) =====", spd, samples);
        @(posedge clk);
        speed = spd;
        fast = 0;
        slow_0 = 1;
        slow_1 = 0;
        start = 1;
        @(posedge clk);
        start = 0;
        
        repeat(samples) @(posedge daclrck);
        
        @(posedge clk);
        stop = 1;
        @(posedge clk);
        stop = 0;
        
        $display(">>> Completed: %0d outputs, %0d SRAM accesses", output_count, access_count);
        repeat(5) @(posedge clk);
    endtask

    task test_slow_linear(input [3:0] spd, input integer samples);
        $display("\n===== TEST: Slow Linear 1/%0dx (expect %0d samples) =====", spd, samples);
        @(posedge clk);
        speed = spd;
        fast = 0;
        slow_0 = 0;
        slow_1 = 1;
        start = 1;
        @(posedge clk);
        start = 0;
        
        repeat(samples) @(posedge daclrck);
        
        @(posedge clk);
        stop = 1;
        @(posedge clk);
        stop = 0;
        
        $display(">>> Completed: %0d outputs, %0d SRAM accesses", output_count, access_count);
        repeat(5) @(posedge clk);
    endtask

    // Main test
    initial begin
        $display("\n*** AudDSP Testbench ***\n");
        
        reset_system();
        init_memory("linear");

        // Fast mode tests
        test_fast(3, 10);
        reset_system();
        
        test_fast(6, 10);
        reset_system();

        // Slow constant tests
        init_memory("linear");
        test_slow_const(2, 10);
        reset_system();
        
        test_slow_const(4, 20);
        reset_system();

        // Slow linear tests
        init_memory("linear");
        test_slow_linear(3, 10);
        reset_system();
        
        test_slow_linear(5, 20);
        reset_system();

        $display("\n*** AudDSP Tests Complete ***\n");
        #5000;
        $finish;
    end

    initial begin
        $fsdbDumpfile("tb_AudDSP.fsdb");
        $fsdbDumpvars(0, tb_AudDSP);
    end

    initial begin
        #10_000_000;
        $display("\nERROR: Timeout!");
        $finish;
    end

endmodule