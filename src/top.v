/*
 * Copyright (c) 2024 Adonai Cruz
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_adonairc_dda (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
	parameter N = 16; // Posit word size
	parameter ES = 1; // Posit ES

	// All output pins must be assigned. If not used, assign to 0.
	assign uo_out  = 0;
	assign uio_out[7:3] = 0;
	assign uio_out[1:0] = 0;
	assign uio_oe[7:4]  = 0;
	
	// SPI pins
	wire sclk, cs, mosi, miso;

	// Output port (MISO)
	assign uio_oe[2] = 1; 

	// Input ports
	assign cs  = uio_in[0];
	assign uio_oe[0] = 0;
	assign mosi  = uio_in[1];
	assign uio_oe[1] = 0;
	assign sclk  = uio_in[3];
	assign uio_oe[3] = 0;
	
	// Dynamical system parameters
	reg [N-1:0] icx, icy; // Initial conditions for variables x and y

	wire [N-1:0] mu; // Van-der-Pol parameter
	reg [N-1:0] r_mu;

	// DDA
	reg clk_dda; // DDA clock

	assign mu = r_mu;

	// SPI
	reg [2:0] r_SCK;
	reg [2:0] r_CS;
	reg [1:0] r_MOSI;
	reg [4:0] bitcnt; // bit counter
	reg is_data_received; // high when a byte has been received
	reg [31:0] data_received;
	reg [31:0] data_sent;
	reg [31:0] cnt;

	// state variables
	wire [N-1:0] x,y;

	// Van-Der-Pol DDA instance
	dda #(.N(N), .ES(ES)) van_der_pol(
		.clk(clk_dda),
		.rst_n(rst_n),
		.x(x),
		.y(y),
		.icx(icx),
		.icy(icy),
		.mu(mu)
	);

	// Reset to enable DDA and set initial conditions
	always @(posedge clk)  begin
		if (!rst_n) begin
			icx <= 16'h3000;
			icy <= 16'h3000;
		end
	end

	// 
	// SPI interface
	//

	// Sync SCK to FPGA clock using a 3-bits shift register;
	always @(posedge clk) r_SCK <= {r_SCK[1:0], sclk};
	wire SCK_risingedge = (r_SCK[2:1]==2'b01); // detect SCK rising edge
	wire SCK_fallingedge = (r_SCK[2:1]==2'b10); // SCK falling edge

	// Sync CS
	always @(posedge clk) r_CS <= {r_CS[1:0], cs};
	wire CS_active = ~r_CS[1]; // CS is active low
	wire CS_startmessage = (r_CS[2:1]==2'b10); // message starts at falling edge
	wire CS_endmessage = (r_CS[2:1]==2'b01); // message stops at rising edge

	// Sync MOSI
	always @(posedge clk) r_MOSI <= {r_MOSI[0], mosi};
	wire MOSI_data = r_MOSI[1];

	// Handle SPI data in 32-bits word format
	always @(posedge clk)
	begin
		if (~CS_active)
			bitcnt <= 0;
		else
		if (SCK_risingedge)
		begin
			bitcnt <= bitcnt + 1;
			// implement a shift-left register (since we receive the data MSB first)
			data_received <= {data_received[30:0], MOSI_data};
		end
	end

	always @(posedge clk) is_data_received <= CS_active &&  SCK_risingedge && (bitcnt == 5'b11111);

	// Updates system parameter mu
	always @(posedge clk) if(is_data_received) r_mu <= data_received[15:0];

	// Data write
	always @(posedge clk) begin
		if(!rst_n) begin
			clk_dda <= 0;
		end
		if (CS_startmessage) begin
			clk_dda <= !clk_dda; // clock the DDA
		end
	end

	always @(posedge clk)
	if (CS_active)
	begin
		if (CS_startmessage) data_sent <= {x,y};
		else
		if (SCK_fallingedge) data_sent <= (bitcnt == 5'b00000)? x : {data_sent[30:0], 1'b0};
	end

	assign uio_out[2] = data_sent[31]; // send MSB first (MISO)

endmodule
