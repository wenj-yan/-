module ad_driver(
    input DATA,
    input reset_n, 
    input fpga_gclk,
    input SCKI,
    output LRCK,
    output BCK,
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
    output LRCK_detcet,
    output reg pos_edge,
    output reg neg_edge
);

/************************************��оƬ���ŵ�һЩ����*******************************************/
assign OSR0 = 1'b1;// Dual rate
assign OSR1 = 1'b0;
assign OSR2 = 1'b0;
assign BYPAS = 1'b0;
assign FMT0 = 1'b0;
assign FMT1 = 1'b1;
assign SM = 1'b1;
reg [8:0] cnt_reset;
reg RST_n_reg;
assign RST_n = 1'b1;
/********************************************************************************************************/


/*************************��Ƶ***********************************/
reg [6:0] cnt_div256;
reg [5:0] cnt_div128;
reg  cnt_div4;
reg LRCK_reg;
reg BCK_reg;
reg LRCK_double_reg;
always @(posedge SCKI ) begin       //分频1
	if (cnt_div256 == 7'd127) begin
		LRCK_reg <= ~LRCK_reg;
        cnt_div256 <= 1'b0;
	end
	else begin
            LRCK_reg <= LRCK_reg;
            cnt_div256 <= cnt_div256 + 1'b1;
    end	
end

always @(posedge SCKI ) begin       //分频2
	if (cnt_div128 == 6'd63) begin
		LRCK_double_reg <= ~LRCK_double_reg;
        cnt_div128 <= 1'b0;
	end
	else begin
            LRCK_double_reg <= LRCK_double_reg;
            cnt_div128 <= cnt_div128 + 1'b1;	
    end
end

always @(posedge SCKI) begin       //分频3
	if (cnt_div4 == 1'b1) begin
		BCK_reg <= ~BCK_reg;
        cnt_div4 <= 1'b0;
	end
	else begin
        BCK_reg <= BCK_reg;
        cnt_div4 <= cnt_div4 + 1'b1;
    end				
end


assign LRCK = LRCK_reg;
assign BCK = BCK_reg;
assign LRCK_double = LRCK_double_reg;
/********************************************************************/


/*************���ݴ�ת���������������źŽ��мĴ�****************/
reg [23:0] data_parellel_tmp;
always @(posedge BCK or negedge reset_n) begin
	if (~reset_n) begin
		data_parellel_tmp <= 0;
	end
	else
		data_parellel_tmp <= {data_parellel_tmp[22:0],DATA};// ע��LSB��MSB
end

// �������غ��½��ض������ݼĴ�
always @(posedge fpga_gclk)
begin
	if (LRCK_detcet)
	// data_parellel <= {{8{data_parellel_tmp[23]}},data_parellel_tmp};
	data_parellel <= {data_parellel_tmp[22:0],9'h0};
	// data_parellel <= {data_parellel_tmp,8'h0};
	// data_parellel <= {data_parellel_tmp[19:0],12'd4095};
end

/*****************************************************************************/


/*************************���ؼ���***********************************/
reg LRCK_detcet_reg;
always @(posedge fpga_gclk or negedge reset_n) begin
    if (~reset_n) begin
        LRCK_detcet_reg <= 0;
    end
    else begin
       LRCK_detcet_reg <= LRCK;
    end
end

/*
assign LRCK_detcet = LRCK_detcet_reg ^ LRCK;
assign  pos_edge = ~LRCK_detcet_reg & LRCK;
assign  neg_edge = LRCK_detcet_reg & ~LRCK;
*/
always @(posedge fpga_gclk)	pos_edge <= ~LRCK_detcet_reg & LRCK;
always @(posedge fpga_gclk)	neg_edge <= LRCK_detcet_reg & ~LRCK;
assign LRCK_detcet = pos_edge | neg_edge;

/********************************************************************/


endmodule