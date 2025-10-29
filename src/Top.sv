module Top (
	input i_rst_n,
	input i_clk,
	input i_key_0, // record/pause
	input i_key_1, // play/pause
	input i_key_2, // stop
	input [3:0] i_speed, // design how user can decide mode on your own
	input i_interpolation, // 0: constant, 1: linear
	input i_fast, // 0: slow mode, 1: fast mode
	
	// AudDSP and SRAM
	output [19:0] o_SRAM_ADDR,
	inout  [15:0] io_SRAM_DQ,
	output        o_SRAM_WE_N,
	output        o_SRAM_CE_N,
	output        o_SRAM_OE_N,
	output        o_SRAM_LB_N,
	output        o_SRAM_UB_N,
	
	// I2C
	input  i_clk_100k,
	output o_I2C_SCLK,
	inout  io_I2C_SDAT,
	
	// AudPlayer
	input  i_AUD_ADCDAT,
	inout  i_AUD_ADCLRCK,
	inout  i_AUD_BCLK,
	inout  i_AUD_DACLRCK,
	output o_AUD_DACDAT,

	// SEVENDECODER (optional display)
	// output [5:0] o_record_time,
	// output [5:0] o_play_time,

	// LCD (optional display)
	// input        i_clk_800k,
	// inout  [7:0] o_LCD_DATA,
	// output       o_LCD_EN,
	// output       o_LCD_RS,
	// output       o_LCD_RW,
	// output       o_LCD_ON,
	// output       o_LCD_BLON,

	// LED
	// output  [8:0] o_ledg,
	output [17:0] o_ledr
);

// design the FSM and states as you like
parameter S_IDLE       = 0;
parameter S_I2C        = 1;
parameter S_RECD       = 2;
parameter S_RECD_PAUSE = 3;
parameter S_PLAY       = 4;
parameter S_PLAY_PAUSE = 5;

logic [2:0] state_w, state_r;

logic [17:0] o_ledr_r, o_ledr_w;
assign o_ledr = o_ledr_w;

logic I2C_finish;
logic record_finish, play_finish; // reached max memory jump back to IDLE

logic record_start_w, record_start_r;
logic record_pause_w, record_pause_r;
logic record_resume_w, record_resume_r;
logic record_stop_w, record_stop_r;

logic dsp_start_w, dsp_start_r;
logic dsp_pause_w, dsp_pause_r;
logic dsp_resume_w, dsp_resume_r;
logic dsp_stop_w, dsp_stop_r;

logic i2c_oen, i2c_sdat;
logic [19:0] addr_record, addr_play;
logic [15:0] data_record, data_play, dac_data;

assign io_I2C_SDAT = (i2c_oen) ? i2c_sdat : 1'bz;

assign o_SRAM_ADDR = (state_r == S_RECD) ? addr_record : addr_play[19:0];
assign io_SRAM_DQ  = (state_r == S_RECD) ? data_record : 16'dz; // sram_dq as output
assign data_play   = (state_r != S_RECD) ? io_SRAM_DQ : 16'd0; // sram_dq as input

assign o_SRAM_WE_N = (state_r == S_RECD) ? 1'b0 : 1'b1;
assign o_SRAM_CE_N = 1'b0;
assign o_SRAM_OE_N = 1'b0;
assign o_SRAM_LB_N = 1'b0;
assign o_SRAM_UB_N = 1'b0;

// below is a simple example for module division
// you can design these as you like

// === I2cInitializer ===
// sequentially sent out settings to initialize WM8731 with I2C protocal
I2cInitializer init0(
	.i_rst_n(i_rst_n),
	.i_clk(i_clk_100k),
	.i_start(1'b1),	// inside I2C module, start I2C when !i_rst_n 
	.o_finished(I2C_finish),
	.o_sclk(o_I2C_SCLK),
	.o_sdat(i2c_sdat),
	.o_oen(i2c_oen) // you are outputing (you are not outputing only when you are "ack"ing.)
);

// === AudDSP ===
// responsible for DSP operations including fast play and slow play at different speed
// in other words, determine which data addr to be fetch for player 
AudDSP dsp0(
	.i_rst_n(i_rst_n),
	.i_clk(i_AUD_BCLK),
	.i_start(dsp_start_r),
	.i_pause(dsp_pause_r),
	.i_resume(dsp_resume_r),
	.i_stop(dsp_stop_r),
	.i_speed(i_speed),
	.i_fast(i_fast),
	.i_slow_0(!i_interpolation), // constant interpolation
	.i_slow_1(i_interpolation), // linear interpolation
	.i_daclrck(i_AUD_DACLRCK),
	.i_sram_data(data_play),
	.o_dac_data(dac_data),
	.o_sram_addr(addr_play),
	.o_finish(play_finish)
);

// === AudPlayer ===
// receive data address from DSP and fetch data to sent to WM8731 with I2S protocal
AudPlayer player0(
	.i_rst_n(i_rst_n),
	.i_bclk(i_AUD_BCLK),
	.i_daclrck(i_AUD_DACLRCK),
	.i_en(state_r == S_PLAY), // enable AudPlayer only when playing audio, work with AudDSP
	.i_dac_data(dac_data), //dac_data
	.o_aud_dacdat(o_AUD_DACDAT)
);

// === AudRecorder ===
// receive data from WM8731 with I2S protocal and save to SRAM
AudRecorder recorder0(
	.i_rst_n(i_rst_n), 
	.i_clk(i_AUD_BCLK),
	.i_lrc(i_AUD_ADCLRCK),
	.i_start(record_start_r),
	.i_pause(record_pause_r),
	.i_resume(record_resume_r),
	.i_stop(record_stop_r),
	.i_data(i_AUD_ADCDAT),
	.o_address(addr_record),
	.o_data(data_record),
	.o_finish(record_finish)
);

always_comb begin
	// design your control here
	state_w = state_r;

	record_start_w = 0;
	record_pause_w = 0;
	record_resume_w = 0;
	record_stop_w = 0;

	dsp_start_w = 0;
	dsp_pause_w = 0;
	dsp_resume_w = 0;
	dsp_stop_w = 0;

	o_ledr_w = 0;

	case (state_r)
		S_IDLE: begin
			if (i_key_0) begin
				state_w = S_RECD;
				record_start_w = 1;
				o_ledr_w = 18'b00_0000_0000_0000_0001;
			end
			else if (i_key_1) begin
				state_w = S_PLAY;
				dsp_start_w = 1;
				o_ledr_w[1] = 1;
				o_ledr_w = 18'b00_0000_0001_0000_0000;
			end
		end
		S_I2C: begin
			if (I2C_finish) begin
				state_w = S_IDLE;
				o_ledr_w = 18'b01_0000_0000_0000_0000;
			end
		end
		S_RECD: begin
			if (i_key_0) begin
				state_w = S_RECD_PAUSE;
				record_pause_w = 1;
				o_ledr_w = 18'b00_0000_0000_0000_0010;
			end
			else if (i_key_2) begin
				state_w = S_IDLE;
				record_stop_w = 1;
				o_ledr_w = 18'b01_0000_0000_0000_0000;
			end
			else if (record_finish) begin
				state_w = S_IDLE;
				o_ledr_w = 18'b01_0000_0000_0000_0000;
			end
		end
		S_RECD_PAUSE: begin
			if (i_key_0) begin
				state_w = S_RECD;
				record_resume_w = 1;
				o_ledr_w = 18'b00_0000_0000_0000_0001;
			end
			else if (i_key_2) begin
				state_w = S_IDLE;
				record_stop_w = 1;
				o_ledr_w = 18'b01_0000_0000_0000_0000;
			end
		end
		S_PLAY: begin
			if (i_key_1) begin
				state_w = S_PLAY_PAUSE;
				dsp_pause_w = 1;
				o_ledr_w = 18'b00_0000_0010_0000_0000;
			end
			else if (i_key_2) begin
				state_w = S_IDLE;
				dsp_stop_w = 1;
				o_ledr_w = 18'b01_0000_0000_0000_0000;
			end
			else if (play_finish) begin
				state_w = S_IDLE;
				o_ledr_w = 18'b01_0000_0000_0000_0000;
			end
		end
		S_PLAY_PAUSE: begin
			if (i_key_1) begin
				state_w = S_PLAY;
				dsp_resume_w = 1;
				o_ledr_w = 18'b00_0000_0001_0000_0000;
			end
			else if (i_key_2) begin
				state_w = S_IDLE;
				dsp_stop_w = 1;
				o_ledr_w = 18'b01_0000_0000_0000_0000;
			end
		end
	endcase
end

always_ff @(posedge i_AUD_BCLK or negedge i_rst_n) begin
	if (!i_rst_n) begin
		state_r <= S_I2C; // start from I2C initialization
		record_start_r <= 0;
		record_pause_r <= 0;
		record_resume_r <= 0;
		record_stop_r <= 0;
		dsp_start_r <= 0;
		dsp_pause_r <= 0;
		dsp_resume_r <= 0;
		dsp_stop_r <= 0;
		o_ledr_r <= 18'b10_0000_0000_0000_0000;
	end
	else begin
		state_r <= state_w;
		record_start_r <= record_start_w;
		record_pause_r <= record_pause_w;
		record_resume_r <= record_resume_w;
		record_stop_r <= record_stop_w;
		dsp_start_r <= dsp_start_w;
		dsp_pause_r <= dsp_pause_w;
		dsp_resume_r <= dsp_resume_w;
		dsp_stop_r <= dsp_stop_w;
		o_ledr_r <= o_ledr_w;
	end
end

endmodule
