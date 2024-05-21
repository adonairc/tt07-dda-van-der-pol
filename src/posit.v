/*
 * Copyright (c) 2024 Adonai Cruz
 * SPDX-License-Identifier: Apache-2.0
 */

module posit_add (in1, in2, out);

function [31:0] log2;
input reg [31:0] value;
	begin
	value = value-1;
	for (log2=0; value>0; log2=log2+1)
        	value = value>>1;
      	end
endfunction

parameter N = 16;
parameter Bs = log2(N); 
parameter ES = 1;

input [N-1:0] in1, in2;
output [N-1:0] out;
wire inf, zero;

wire s1 = in1[N-1];
wire s2 = in2[N-1];
wire zero_tmp1 = |in1[N-2:0];
wire zero_tmp2 = |in2[N-2:0];
wire inf1 = in1[N-1] & (~zero_tmp1),
	inf2 = in2[N-1] & (~zero_tmp2);
wire zero1 = ~(in1[N-1] | zero_tmp1),
	zero2 = ~(in2[N-1] | zero_tmp2);
assign inf = inf1 | inf2,
	zero = zero1 & zero2;

//Data Extraction
wire rc1, rc2;
wire [Bs-1:0] regime1, regime2;
wire [ES-1:0] e1, e2;
wire [N-ES-1:0] mant1, mant2;
wire [N-1:0] xin1 = s1 ? -in1 : in1;
wire [N-1:0] xin2 = s2 ? -in2 : in2;
data_extract_v1 #(.N(N),.ES(ES)) uut_de1(.in(xin1), .rc(rc1), .regime(regime1), .exp(e1), .mant(mant1));
data_extract_v1 #(.N(N),.ES(ES)) uut_de2(.in(xin2), .rc(rc2), .regime(regime2), .exp(e2), .mant(mant2));

wire [N-ES:0] m1 = {zero_tmp1,mant1}, 
	m2 = {zero_tmp2,mant2};

//Large Checking and Assignment
wire in1_gt_in2 = (xin1[N-2:0] >= xin2[N-2:0]) ? 1'b1 : 1'b0;

wire ls = in1_gt_in2 ? s1 : s2;
wire op = s1 ~^ s2;

wire lrc = in1_gt_in2 ? rc1 : rc2;
wire src = in1_gt_in2 ? rc2 : rc1;

wire [Bs-1:0] lr = in1_gt_in2 ? regime1 : regime2;
wire [Bs-1:0] sr = in1_gt_in2 ? regime2 : regime1;

wire [ES-1:0] le = in1_gt_in2 ? e1 : e2;
wire [ES-1:0] se = in1_gt_in2 ? e2 : e1;

wire [N-ES:0] lm = in1_gt_in2 ? m1 : m2;
wire [N-ES:0] sm = in1_gt_in2 ? m2 : m1;

//Exponent Difference: Lower Mantissa Right Shift Amount
wire [ES+Bs+1:0] diff;
wire [Bs:0] lr_N;
wire [Bs:0] sr_N;
a_abs_regime #(.N(Bs)) uut_abs_regime1 (lrc, lr, lr_N);
a_abs_regime #(.N(Bs)) uut_abs_regime2 (src, sr, sr_N);
a_sub_N #(.N(ES+Bs+1)) uut_ediff ({lr_N,le}, {sr_N, se}, diff);
wire [Bs-1:0] exp_diff = (|diff[ES+Bs:Bs]) ? {Bs{1'b1}} : diff[Bs-1:0];

//DSR Right Shifting
wire [N-1:0] DSR_right_in;
generate
	if (ES >= 2) 
	assign DSR_right_in = {sm,{ES-1{1'b0}}};
	else 
	assign DSR_right_in = sm;
endgenerate

wire [N-1:0] DSR_right_out;
wire [Bs-1:0] DSR_e_diff  = exp_diff;
DSR_right_N_S #(.N(N), .S(Bs))  dsr1(.a(DSR_right_in), .b(DSR_e_diff), .c(DSR_right_out));

//Mantissa Addition
wire [N-1:0] add_m_in1;
generate
	if (ES >= 2) 
	assign add_m_in1 = {lm,{ES-1{1'b0}}};
	else 
	assign add_m_in1 = lm;
endgenerate

wire [N:0] add_m;
a_add_sub_N #(.N(N)) uut_add_sub_N (op, add_m_in1, DSR_right_out, add_m);
wire [1:0] mant_ovf = add_m[N:N-1];

//LOD
wire [N-1:0] LOD_in = {(add_m[N] | add_m[N-1]), add_m[N-2:0]};
wire [Bs-1:0] left_shift;
LOD_N #(.N(N)) l2(.in(LOD_in), .out(left_shift));

//DSR Left Shifting
wire [N-1:0] DSR_left_out_t;
DSR_left_N_S #(.N(N), .S(Bs)) dsl1(.a(add_m[N:1]), .b(left_shift), .c(DSR_left_out_t));
wire [N-1:0] DSR_left_out = DSR_left_out_t[N-1] ? DSR_left_out_t[N-1:0] : {DSR_left_out_t[N-2:0],1'b0}; 


//Exponent and Regime Computation
wire [ES+Bs+1:0] le_o_tmp, le_o;
a_sub_N #(.N(ES+Bs+1)) sub3 ({lr_N,le}, {{ES+1{1'b0}},left_shift}, le_o_tmp);
add_1 #(.N(ES+Bs+1)) uut_add_mantovf (le_o_tmp, mant_ovf[1], le_o);

wire [ES-1:0] e_o;
wire [Bs-1:0] r_o;
a_reg_exp_op #(.ES(ES), .Bs(Bs)) uut_reg_ro (le_o[ES+Bs:0], e_o, r_o);

//Exponent and Mantissa Packing
wire [2*N-1+3:0] tmp_o;
generate
	if(ES > 2)
		assign tmp_o = { {N{~le_o[ES+Bs]}}, le_o[ES+Bs], e_o, DSR_left_out[N-2:ES-2], |DSR_left_out[ES-3:0]};
	else 
		assign tmp_o = { {N{~le_o[ES+Bs]}}, le_o[ES+Bs], e_o, DSR_left_out[N-2:0], {3-ES{1'b0}} };

endgenerate

//Including/Pushing Regime bits in Exponent-Mantissa Packing
wire [3*N-1+3:0] tmp1_o;
DSR_right_N_S #(.N(3*N+3), .S(Bs)) dsr2 (.a({tmp_o,{N{1'b0}}}), .b(r_o), .c(tmp1_o));

//Rounding RNE : ulp_add = G.(R + S) + L.G.(~(R+S))
wire L = tmp1_o[N+4], G = tmp1_o[N+3], R = tmp1_o[N+2], St = |tmp1_o[N+1:0],
     ulp = ((G & (R | St)) | (L & G & ~(R | St)));
wire [N-1:0] rnd_ulp = {{N-1{1'b0}},ulp};

wire [N:0] tmp1_o_rnd_ulp;
a_add_N #(.N(N)) uut_add_ulp (tmp1_o[2*N-1+3:N+3], rnd_ulp, tmp1_o_rnd_ulp);
wire [N-1:0] tmp1_o_rnd = (r_o < N-ES-2) ? tmp1_o_rnd_ulp[N-1:0] : tmp1_o[2*N-1+3:N+3];

//Final Output
wire [N-1:0] tmp1_oN = ls ? -tmp1_o_rnd : tmp1_o_rnd;
assign out = inf|zero|(~DSR_left_out[N-1]) ? {inf,{N-1{1'b0}}} : {ls, tmp1_oN[N-1:1]};

endmodule


module posit_mult(in1, in2, out);

function [31:0] log2;
input reg [31:0] value;
	begin
	value = value-1;
	for (log2=0; value>0; log2=log2+1)
        	value = value>>1;
      	end
endfunction

parameter N = 16;
parameter Bs = log2(N); 
parameter ES = 1;

input [N-1:0] in1, in2;
output [N-1:0] out;
wire inf, zero;

wire s1 = in1[N-1];
wire s2 = in2[N-1];
wire zero_tmp1 = |in1[N-2:0];
wire zero_tmp2 = |in2[N-2:0];
wire inf1 = in1[N-1] & (~zero_tmp1),
	inf2 = in2[N-1] & (~zero_tmp2);
wire zero1 = ~(in1[N-1] | zero_tmp1),
	zero2 = ~(in2[N-1] | zero_tmp2);
assign inf = inf1 | inf2,
	zero = zero1 & zero2;

//Data Extraction
wire rc1, rc2;
wire [Bs-1:0] regime1, regime2;
wire [ES-1:0] e1, e2;
wire [N-ES-1:0] mant1, mant2;
wire [N-1:0] xin1 = s1 ? -in1 : in1;
wire [N-1:0] xin2 = s2 ? -in2 : in2;
data_extract_v1 #(.N(N),.ES(ES)) uut_de1(.in(xin1), .rc(rc1), .regime(regime1), .exp(e1), .mant(mant1));
data_extract_v1 #(.N(N),.ES(ES)) uut_de2(.in(xin2), .rc(rc2), .regime(regime2), .exp(e2), .mant(mant2));

wire [N-ES:0] m1 = {zero_tmp1,mant1}, 
	m2 = {zero_tmp2,mant2};

//Sign, Exponent and Mantissa Computation
wire mult_s = s1 ^ s2;

wire [2*(N-ES)+1:0] mult_m = m1*m2;
wire mult_m_ovf = mult_m[2*(N-ES)+1];
wire [2*(N-ES)+1:0] mult_mN = ~mult_m_ovf ? mult_m << 1'b1 : mult_m;

wire [Bs+1:0] r1 = rc1 ? {2'b0,regime1} : -regime1;
wire [Bs+1:0] r2 = rc2 ? {2'b0,regime2} : -regime2;
wire [Bs+ES+1:0] mult_e;
m_add_N_Cin #(.N(Bs+ES+1)) uut_add_exp ({r1,e1}, {r2,e2}, mult_m_ovf, mult_e);

//Exponent and Regime Computation
wire [ES-1:0] e_o;
wire [Bs:0] r_o;
m_reg_exp_op #(.ES(ES), .Bs(Bs)) uut_reg_ro (mult_e[ES+Bs+1:0], e_o, r_o);

//Exponent, Mantissa and GRS Packing
wire [2*N-1+3:0]tmp_o = {{N{~mult_e[ES+Bs+1]}},mult_e[ES+Bs+1],e_o,mult_mN[2*(N-ES):2*(N-ES)-(N-ES-1)+1], mult_mN[2*(N-ES)-(N-ES-1):2*(N-ES)-(N-ES-1)-1], |mult_mN[2*(N-ES)-(N-ES-1)-2:0] }; 


//Including Regime bits in Exponent-Mantissa Packing
wire [3*N-1+3:0] tmp1_o;
DSR_right_N_S #(.N(3*N+3), .S(Bs+1)) dsr2 (.a({tmp_o,{N{1'b0}}}), .b(r_o[Bs] ? {Bs{1'b1}} : r_o), .c(tmp1_o));

//Rounding RNE : ulp_add = G.(R + S) + L.G.(~(R+S))
wire L = tmp1_o[N+4], G = tmp1_o[N+3], R = tmp1_o[N+2], St = |tmp1_o[N+1:0],
     ulp = ((G & (R | St)) | (L & G & ~(R | St)));
wire [N-1:0] rnd_ulp = {{N-1{1'b0}},ulp};

wire [N:0] tmp1_o_rnd_ulp;
m_add_N #(.N(N)) uut_add_ulp (tmp1_o[2*N-1+3:N+3], rnd_ulp, tmp1_o_rnd_ulp);
wire [N-1:0] tmp1_o_rnd = (r_o < N-ES-2) ? tmp1_o_rnd_ulp[N-1:0] : tmp1_o[2*N-1+3:N+3];


//Final Output
wire [N-1:0] tmp1_oN = mult_s ? -tmp1_o_rnd : tmp1_o_rnd;
assign out = inf|zero|(~mult_mN[2*(N-ES)+1]) ? {inf,{N-1{1'b0}}} : {mult_s, tmp1_oN[N-1:1]};
endmodule

/////////////////////////////
// Adder auxiliary modules //
////////////////////////////


/////////////////
module a_sub_N (a,b,c);
parameter N=10;
input [N-1:0] a,b;
output [N:0] c;
wire [N:0] ain = {1'b0,a};
wire [N:0] bin = {1'b0,b};
a_sub_N_in #(.N(N)) s1 (ain,bin,c);
endmodule

/////////////////////////
module a_add_N (a,b,c);
parameter N=10;
input [N-1:0] a,b;
output [N:0] c;
wire [N:0] ain = {1'b0,a};
wire [N:0] bin = {1'b0,b};
a_add_N_in #(.N(N)) a1 (ain,bin,c);
endmodule

/////////////////////////
module a_sub_N_in (a,b,c);
parameter N=10;
input [N:0] a,b;
output [N:0] c;
assign c = a - b;
endmodule

/////////////////////////
module a_add_N_in (a,b,c);
parameter N=10;
input [N:0] a,b;
output [N:0] c;
assign c = a + b;
endmodule

/////////////////////////
module a_add_sub_N (op,a,b,c);
parameter N=10;
input op;
input [N-1:0] a,b;
output [N:0] c;
wire [N:0] c_add, c_sub;

a_add_N #(.N(N)) a11 (a,b,c_add);
a_sub_N #(.N(N)) s11 (a,b,c_sub);
assign c = op ? c_add : c_sub;
endmodule

/////////////////////////
module a_abs_regime (rc, regime, regime_N);
parameter N = 10;
input rc;
input [N-1:0] regime;
output [N:0] regime_N;

assign regime_N = rc ? {1'b0,regime} : -{1'b0,regime};
endmodule

/////////////////////////
module a_reg_exp_op (exp_o, e_o, r_o);
parameter ES=3;
parameter Bs=5;
input [ES+Bs:0] exp_o;
output [ES-1:0] e_o;
output [Bs-1:0] r_o;

assign e_o = exp_o[ES-1:0];

wire [ES+Bs:0] exp_oN_tmp;
conv_2c #(.N(ES+Bs)) uut_conv_2c1 (~exp_o[ES+Bs:0],exp_oN_tmp);
wire [ES+Bs:0] exp_oN = exp_o[ES+Bs] ? exp_oN_tmp[ES+Bs:0] : exp_o[ES+Bs:0];
assign r_o = (~exp_o[ES+Bs] || |(exp_oN[ES-1:0])) ? exp_oN[ES+Bs-1:ES] + 1 : exp_oN[ES+Bs-1:ES];
endmodule


///////////////////////////////////
// Multiplier auxiliary modules //
/////////////////////////////////
module m_add_N (a,b,c);
parameter N=10;
input [N-1:0] a,b;
output [N:0] c;
assign c = {1'b0,a} + {1'b0,b};
endmodule

/////////////////////////
module m_add_N_Cin (a,b,cin,c);
parameter N=10;
input [N:0] a,b;
input cin;
output [N:0] c;
assign c = a + b + cin;
endmodule

/////////////////////////
module m_reg_exp_op (exp_o, e_o, r_o);
parameter ES=3;
parameter Bs=5;
input [ES+Bs+1:0] exp_o;
output [ES-1:0] e_o;
output [Bs:0] r_o;

assign e_o = exp_o[ES-1:0];

wire [ES+Bs:0] exp_oN_tmp;
conv_2c #(.N(ES+Bs)) uut_conv_2c1 (~exp_o[ES+Bs:0],exp_oN_tmp);
wire [ES+Bs:0] exp_oN = exp_o[ES+Bs+1] ? exp_oN_tmp[ES+Bs:0] : exp_o[ES+Bs:0];

assign r_o = (~exp_o[ES+Bs+1] || |(exp_oN[ES-1:0])) ? exp_oN[ES+Bs:ES] + 1 : exp_oN[ES+Bs:ES];
endmodule

//////////////////////
// General modules //
////////////////////
module data_extract_v1(in, rc, regime, exp, mant);
function [31:0] log2;
input reg [31:0] value;
	begin
	value = value-1;
	for (log2=0; value>0; log2=log2+1)
        	value = value>>1;
      	end
endfunction

parameter N=16;
parameter Bs=log2(N);
parameter ES = 2;

input [N-1:0] in;
output rc;
output [Bs-1:0] regime;
output [ES-1:0] exp;
output [N-ES-1:0] mant;

wire [N-1:0] xin = in;
assign rc = xin[N-2];

wire [N-1:0] xin_r = rc ? ~xin : xin;

wire [Bs-1:0] k;
LOD_N #(.N(N)) xinst_k(.in({xin_r[N-2:0],rc^1'b0}), .out(k));

assign regime = rc ? k-1 : k;

wire [N-1:0] xin_tmp;
DSR_left_N_S #(.N(N), .S(Bs)) ls (.a({xin[N-3:0],2'b0}),.b(k),.c(xin_tmp));

assign exp= xin_tmp[N-1:N-ES];
assign mant= xin_tmp[N-ES-1:0];

endmodule

/////////////////////////
module add_1 (a,mant_ovf,c);
parameter N=10;
input [N:0] a;
input mant_ovf;
output [N:0] c;
assign c = a + mant_ovf;
endmodule

/////////////////////////
module conv_2c (a,c);
parameter N=10;
input [N:0] a;
output [N:0] c;
assign c = a + 1'b1;
endmodule

/////////////////////////
module DSR_left_N_S(a,b,c);
        parameter N=16;
        parameter S=4;
        input [N-1:0] a;
        input [S-1:0] b;
        output [N-1:0] c;

wire [N-1:0] tmp [S-1:0];
assign tmp[0]  = b[0] ? a << 7'd1  : a; 
genvar i;
generate
	for (i=1; i<S; i=i+1)begin:loop_blk
		assign tmp[i] = b[i] ? tmp[i-1] << 2**i : tmp[i-1];
	end
endgenerate
assign c = tmp[S-1];

endmodule

/////////////////////////
module DSR_right_N_S(a,b,c);
        parameter N=16;
        parameter S=4;
        input [N-1:0] a;
        input [S-1:0] b;
        output [N-1:0] c;

wire [N-1:0] tmp [S-1:0];
assign tmp[0]  = b[0] ? a >> 7'd1  : a; 
genvar i;
generate
	for (i=1; i<S; i=i+1)begin:loop_blk
		assign tmp[i] = b[i] ? tmp[i-1] >> 2**i : tmp[i-1];
	end
endgenerate
assign c = tmp[S-1];

endmodule

/////////////////////////
module LOD_N (in, out);

  function [31:0] log2;
    input reg [31:0] value;
    begin
      value = value-1;
      for (log2=0; value>0; log2=log2+1)
	value = value>>1;
    end
  endfunction

parameter N = 64;
parameter S = log2(N); 
input [N-1:0] in;
output [S-1:0] out;

wire vld;
LOD #(.N(N)) l1 (in, out, vld);
endmodule

/////////////////////////
module LOD (in, out, vld);

  function [31:0] log2;
    input reg [31:0] value;
    begin
      value = value-1;
      for (log2=0; value>0; log2=log2+1)
	value = value>>1;
    end
  endfunction


parameter N = 64;
parameter S = log2(N);

   input [N-1:0] in;
   output [S-1:0] out;
   output vld;

  generate
    if (N == 2)
      begin
	assign vld = |in;
	assign out = ~in[1] & in[0];
      end
    else if (N & (N-1))
      //LOD #(1<<S) LOD ({1<<S {1'b0}} | in,out,vld);
      LOD #(1<<S) LOD ({in,{((1<<S) - N) {1'b0}}},out,vld);
    else
      begin
	wire [S-2:0] out_l, out_h;
	wire out_vl, out_vh;
	LOD #(N>>1) l(in[(N>>1)-1:0],out_l,out_vl);
	LOD #(N>>1) h(in[N-1:N>>1],out_h,out_vh);
	assign vld = out_vl | out_vh;
	assign out = out_vh ? {1'b0,out_h} : {out_vl,out_l};
      end
  endgenerate
endmodule

