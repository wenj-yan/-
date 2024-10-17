module ad_driver_zsj(
    input DATA,
    input reset_n, 
    input fpga_gclk,
    input SCKI,// 24.572650Mhz,256fs
    output reg LRCK,
    output reg BCK,
    output LRCK_double,
    output OSR0,	 
    output OSR1,	 
    output OSR2,
    output FMT0,
    output FMT1,
    output SM,
    output BYPAS,
    output RST_n,
    output reg [31:0] data_parellel,
    output reg LRCK_detcet,
    output reg pos_edge,
    output reg neg_edge,
	 output reg ad_sysclk
);

/********************************************************************************************************/
assign OSR0 = 1'b1;// Dual rate
assign OSR1 = 1'b0;
assign OSR2 = 1'b0;
assign BYPAS = 1'b0;
assign FMT0 = 1'b0;
assign FMT1 = 1'b1;
assign SM = 1'b1;
assign RST_n = 1'b1;
/********************************************************************************************************/

/********************************************************************/
reg [7:0] cnt_div256;
always @(posedge SCKI)          cnt_div256 <= cnt_div256 + 1'b1;

always @(posedge SCKI)	
begin
	if (&cnt_div256)
		LRCK <= ~LRCK;
end 


always @(posedge SCKI)
begin 
	if (&cnt_div256[1:0])
        BCK <= ~BCK;
end 

always @(posedge SCKI)
begin 
	if (cnt_div256[0])
		ad_sysclk <= ~ad_sysclk;
end 
/********************************************************************/
reg [23:0] data_parellel_tmp;
always @(posedge BCK)		data_parellel_tmp <= {data_parellel_tmp[22:0],DATA};


always @(posedge fpga_gclk)
begin
	if (LRCK_detcet)
		data_parellel <= {data_parellel_tmp[19:0],12'h0};
end

/*****************************************************************************/
reg LRCK_detcet_reg;
always @(posedge fpga_gclk)       LRCK_detcet_reg <= LRCK;

/*
assign  LRCK_detcet = LRCK_detcet_reg ^ LRCK;
assign  pos_edge = ~LRCK_detcet_reg & LRCK;
assign  neg_edge = LRCK_detcet_reg & ~LRCK;
*/
always @(posedge fpga_gclk)
begin 
  LRCK_detcet <= LRCK_detcet_reg ^ LRCK;
  pos_edge <= ~LRCK_detcet_reg & LRCK;
  neg_edge <= LRCK_detcet_reg & ~LRCK;
end 

/********************************************************************/


endmodule