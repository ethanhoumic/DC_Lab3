module AudPlayer (
    input               i_rst_n,
    input               i_bclk,
    input               i_daclrck,
    input               i_en,
    input signed [15:0] i_dac_data,
    output              o_aud_dacdat
);

    logic [15:0] shift_reg_r, shift_reg_w;
    logic [4:0]  bit_cnt_r, bit_cnt_w;
    logic        daclrck_prev_r;

    wire daclrck_posedge = i_daclrck && !daclrck_prev_r;

    // Latch data on DACLRCK rising edge
    always_comb begin
        shift_reg_w = shift_reg_r;
        bit_cnt_w = bit_cnt_r;

        if (daclrck_posedge && i_en) begin
            // Latch new data at start of channel
            shift_reg_w = i_dac_data;
            bit_cnt_w = 5'd0;
        end else if (i_en && i_daclrck && bit_cnt_r < 5'd16) begin
            // Shift out data during channel time
            shift_reg_w = shift_reg_r << 1;
            bit_cnt_w = bit_cnt_r + 1;
        end
    end

    // Output MSB when enabled and DACLRCK is high
    assign o_aud_dacdat = (i_en && i_daclrck) ? shift_reg_r[15] : 1'bz;

    always_ff @(posedge i_bclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            shift_reg_r <= 16'd0;
            bit_cnt_r <= 5'd0;
            daclrck_prev_r <= 1'b0;
        end else begin
            shift_reg_r <= shift_reg_w;
            bit_cnt_r <= bit_cnt_w;
            daclrck_prev_r <= i_daclrck;
        end
    end

endmodule