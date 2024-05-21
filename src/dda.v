/*
 * Copyright (c) 2024 Adonai Cruz
 * SPDX-License-Identifier: Apache-2.0
 */

module dda (
    input clk, // Clock
    input rst_n, // Reset (active low)
    output [N-1:0] x,y, // Dynamical system state variables
    input [N-1:0] icx, icy, // Initial conditions
    input [N-1:0] mu // Van-der-Pol parameter
);

// Posit parameters
parameter N = 16;
parameter ES = 1;

// Multiplications
wire [N-1:0] w_mult1, w_mult2, w_mult3;

posit_mult #(.N(N),.ES(ES)) mult1(.in1(x), .in2(x), .out(w_mult1)); // Multiply x*x
posit_mult #(.N(N),.ES(ES)) mult2(.in1(mu), .in2(w_sub1), .out(w_mult2)); // Multiply mu*(1-x*x)
posit_mult #(.N(N),.ES(ES)) mult3(.in1(w_mult2), .in2(y), .out(w_mult3)); // Multiply mu*(1-x*x)*y

// Subtraction
wire [N-1:0] w_sub1, w_sub2;

wire [N-1:0] w_neg_mult1;
assign w_neg_mult1 = {~w_mult1[N-1], ~w_mult1[N-2:0]+1'b1};

wire [N-1:0] w_neg_x;
assign w_neg_x = {~x[N-1], ~x[N-2:0]+1'b1};

posit_add #(.N(N),.ES(ES)) sub_1_mult_x_x(.in1(16'b0100000000000000), .in2(w_neg_mult1), .out(w_sub1)); // Subtract 1 - x*x
posit_add #(.N(N),.ES(ES)) sub_rho_z(.in1(w_mult3), .in2(w_neg_x), .out(w_sub2)); // Subtract mu*(1-x*x)y - x

// Van der Pol oscillator
// dx/dt = y
// dy/dt = mu*(1 - x*x) - x

euler_integrator  #(.N(N),.ES(ES)) int1(.out(x), .funct(y), .ic(icx), .clk(clk), .rst_n(rst_n));
euler_integrator  #(.N(N),.ES(ES)) int2(.out(y), .funct(w_sub2), .ic(icy), .clk(clk), .rst_n(rst_n));

endmodule


/// Euler integrator
module euler_integrator(out, funct, clk, rst_n, ic);
	parameter N = 16;
	parameter ES = 1;

	input clk, rst_n;
	output [N-1:0] out; // state variable
	input [N-1:0] funct; // the dV/dt function
	input [N-1:0] ic; // initial condition

	wire [N-1:0] out, v1new;
	reg [N-1:0] v1;

	wire [N-1:0] out_mult;
	
	wire [N-1:0] dt = 16'h0400; // Time step

	// compute new state variable with dt 
	// v1(n+1) = v1(n) + dt*funct(n)

    // Multiply funct(n) by constant dt
	posit_mult  #(
		.N(N),
		.ES(ES)
	) mult (
		.in1(funct),
		.in2(dt),
		.out(out_mult)
	);

	posit_add #(
		.N(N),
		.ES(ES)
	)
	add(
		.in1(out_mult),
		.in2(v1),
		.out(v1new)
	);

	always @(posedge clk)
	begin
		if (!rst_n)
			v1 <= ic;
		else
			v1 <= v1new;
	end
	assign out = v1;

endmodule

