module AudDSP (
    input                i_rst_n,
    input                i_clk,
    input                i_start,
    input                i_pause,
    input                i_stop,
    input         [3:0]  i_speed,  // 2 ~ 8
    input                i_fast,
    input                i_slow_0,
    input                i_slow_1,
    input                i_daclrck,
    input  signed [15:0] i_sram_data,
    output signed [15:0] o_dac_data,
    output        [19:0] o_sram_addr
);

    typedef enum logic [1:0] {
        MODE_FAST    = 0,
        MODE_SLOW_0  = 1,
        MODE_SLOW_1  = 2
    } mode_t;

    mode_t mode_r, mode_w;

    logic [3:0]  speed_r, speed_w;
    logic [3:0]  interp_cnt_r, interp_cnt_w;
    logic [19:0] addr_r, addr_w;
    logic [19:0] sram_addr_r, sram_addr_w;
    
    logic signed [15:0] curr_sample_r, curr_sample_w;
    logic signed [15:0] next_sample_r, next_sample_w;
    logic signed [15:0] output_r, output_w;
    
    logic [2:0]  fetch_state_r, fetch_state_w;
    logic        daclrck_prev_r;
    logic        playing_r, playing_w;

    wire daclrck_posedge = i_daclrck && !daclrck_prev_r;
    wire daclrck_negedge = !i_daclrck && daclrck_prev_r;

    // Interpolation calculation
    logic signed [15:0] diff, diff_neg, step;
    
    assign diff = next_sample_r - curr_sample_r;
    assign diff_neg = ~diff + 16'd1;

    always_comb begin
        case (speed_r)
            4'd2: step = diff[15] ? (16'd1 + ~(diff_neg >> 1)) : (diff >> 1);
            4'd3: step = diff[15] ? (16'd1 + ~((diff_neg >> 2) + (diff_neg >> 4) + (diff_neg >> 6))) 
                                  : ((diff >> 2) + (diff >> 4) + (diff >> 6));
            4'd4: step = diff[15] ? (16'd1 + ~(diff_neg >> 2)) : (diff >> 2);
            4'd5: step = diff[15] ? (16'd1 + ~((diff_neg >> 3) + (diff_neg >> 4) + (diff_neg >> 6))) 
                                  : ((diff >> 3) + (diff >> 4) + (diff >> 6));
            4'd6: step = diff[15] ? (16'd1 + ~((diff_neg >> 3) + (diff_neg >> 5) + (diff_neg >> 7))) 
                                  : ((diff >> 3) + (diff >> 5) + (diff >> 7));
            4'd7: step = diff[15] ? (16'd1 + ~((diff_neg >> 3) + (diff_neg >> 6) + (diff_neg >> 9))) 
                                  : ((diff >> 3) + (diff >> 6) + (diff >> 9));
            4'd8: step = diff[15] ? (16'd1 + ~(diff_neg >> 3)) : (diff >> 3);
            default: step = 16'd0;
        endcase
    end

    wire signed [15:0] interpolated = curr_sample_r + step * interp_cnt_r;

    // Parameter capture
    always_comb begin
        speed_w = speed_r;
        mode_w = mode_r;

        if (fetch_state_r == 3'd0) begin  // Capture at idle
            if (i_start) begin
                speed_w = i_speed;
                if (i_fast) begin
                    mode_w = MODE_FAST;
                end
                else if (i_slow_0) begin
                    mode_w = MODE_SLOW_0;
                end
                else begin
                    mode_w = MODE_SLOW_1;
                end
            end
        end
    end

    // Main fetch state machine
    always_comb begin
        addr_w = addr_r;
        sram_addr_w = sram_addr_r;
        curr_sample_w = curr_sample_r;
        next_sample_w = next_sample_r;
        output_w = output_r;
        interp_cnt_w = interp_cnt_r;
        fetch_state_w = fetch_state_r;
        playing_w = playing_r;

        case (fetch_state_r)
            3'd0: begin  // IDLE - wait for start
                if (i_start && !playing_r) begin
                    addr_w = 20'd0;
                    sram_addr_w = 20'd0;  // Pre-request first address
                    interp_cnt_w = 4'd0;
                    playing_w = 1'b1;
                    fetch_state_w = 3'd1;  // Go to pre-fetch
                end
            end

            3'd1: begin  // PRE-FETCH - get first sample before sync
                if (playing_r) begin
                    // Capture first sample immediately
                    case (mode_r)
                        MODE_FAST: begin
                            curr_sample_w = i_sram_data;
                            output_w = i_sram_data;
                        end
                        
                        MODE_SLOW_0: begin
                            curr_sample_w = i_sram_data;
                            output_w = i_sram_data;
                        end
                        
                        MODE_SLOW_1: begin
                            curr_sample_w = i_sram_data;
                            sram_addr_w = addr_r + 1;
                            output_w = i_sram_data;
                            // Need to fetch next sample too
                        end
                    endcase
                    fetch_state_w = 3'd6;  // New state: wait for sync
                end
            end

            3'd6: begin  // SYNC - wait for first posedge with data ready
                if (daclrck_posedge && playing_r) begin
                    if (mode_r == MODE_SLOW_1) begin
                        output_w = interpolated;
                        next_sample_w = i_sram_data;
                    end
                    fetch_state_w = 3'd4;  // Go to WAIT state
                    // Output is already set in 3'd1
                end
            end

            3'd2: begin  // REQUEST - set SRAM address
                if (playing_r) begin
                    if (mode_r != MODE_SLOW_1) sram_addr_w = addr_r;
                    fetch_state_w = 3'd3;
                end
            end

            3'd3: begin  // CAPTURE - get data from SRAM
                if (playing_r) begin
                    case (mode_r)
                        MODE_FAST: begin
                            curr_sample_w = i_sram_data;
                            output_w = i_sram_data;
                            fetch_state_w = 3'd4;  // Done, wait for DACLRCK
                        end

                        MODE_SLOW_0: begin
                            if (interp_cnt_r == 4'd0) begin
                                curr_sample_w = i_sram_data;
                                output_w = i_sram_data;  // FIXED: output immediately
                            end else begin
                                output_w = curr_sample_r;
                            end
                            fetch_state_w = 3'd4;
                        end

                        MODE_SLOW_1: begin
                            if (interp_cnt_r == 4'd0) begin
                                curr_sample_w = i_sram_data;
                                sram_addr_w = addr_r + 1;  // Request next sample
                                fetch_state_w = 3'd5;  // Need to fetch next sample
                            end else begin
                                output_w = interpolated;
                                fetch_state_w = 3'd4;
                            end
                        end
                    endcase
                end
            end

            3'd5: begin  // CAPTURE_NEXT (for linear interpolation)
                if (playing_r) begin
                    output_w = interpolated;
                    fetch_state_w = 3'd4;
                end
            end

            3'd4: begin  // WAIT - wait for DACLRCK negedge, then update address
                next_sample_w = i_sram_data;
                if (daclrck_negedge && playing_r) begin
                    case (mode_r)
                        MODE_FAST: begin
                            addr_w = addr_r + speed_r;
                            sram_addr_w = addr_r + speed_r;
                        end
                        
                        MODE_SLOW_0: begin
                            if (interp_cnt_r >= speed_r - 1) begin
                                interp_cnt_w = 4'd0;
                                addr_w = addr_r + 1;
                                sram_addr_w = addr_r + 1;
                            end else begin
                                interp_cnt_w = interp_cnt_r + 1;
                            end
                        end
                        MODE_SLOW_1: begin
                            if (interp_cnt_r >= speed_r - 1) begin
                                interp_cnt_w = 4'd0;
                                addr_w = addr_r + 1;
                            end else begin
                                interp_cnt_w = interp_cnt_r + 1;
                            end
                        end
                    endcase
                    fetch_state_w = 3'd2;  // Go back to request next sample
                end
            end
        endcase

        // Control overrides
        if (i_pause) begin
            playing_w = 1'b0;
            fetch_state_w = 3'd0;
        end
        
        if (i_stop || addr_r >= 20'd1023999) begin
            playing_w = 1'b0;
            fetch_state_w = 3'd0;
        end
    end

    assign o_sram_addr = sram_addr_r;
    assign o_dac_data = output_r;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            mode_r <= MODE_FAST;
            speed_r <= 4'd0;
            interp_cnt_r <= 4'd0;
            addr_r <= 20'd0;
            sram_addr_r <= 20'd0;
            curr_sample_r <= 16'd0;
            next_sample_r <= 16'd0;
            output_r <= 16'd9999;  // For distinguishment from reset and data at addr = 0
            fetch_state_r <= 3'd0;
            daclrck_prev_r <= 1'b0;
            playing_r <= 1'b0;
        end else begin
            mode_r <= mode_w;
            speed_r <= speed_w;
            interp_cnt_r <= interp_cnt_w;
            addr_r <= addr_w;
            sram_addr_r <= sram_addr_w;
            curr_sample_r <= curr_sample_w;
            next_sample_r <= next_sample_w;
            output_r <= output_w;
            fetch_state_r <= fetch_state_w;
            daclrck_prev_r <= i_daclrck;
            playing_r <= playing_w;
        end
    end

endmodule