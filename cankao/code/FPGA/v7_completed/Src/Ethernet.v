module Ethernet(
					input reset_n,                           
					input  fpga_gclk,                   
					output e_reset,

               output e_mdc,
					inout  e_mdio,
		
            
					input	 e_rxc,                       //125Mhz ethernet gmii rx clock
					input	 e_rxdv,	
					input	 e_rxer,						
					input  [7:0] e_rxd,        

					input	 e_txc,                     //25Mhz ethernet mii tx clock         
					output e_gtxc,                    //25Mhz ethernet gmii tx clock  
					output e_txen, 
					output e_txer, 					
					output [7:0] e_txd,

				// 与ad模块交互的端口：
					input DATA,
					output SCKI,	
					output OSR0,	 
 					output OSR1,	 
					output OSR2,
					output FMT0,
					output FMT1,
					output SM,
					output LRCK,
					output BCK,
					output BYPAS,
					output RST_n

 
);
                

wire [31:0] ram_wr_data;
wire [31:0] ram_rd_data;
wire [10:0] ram_wr_addr;
wire [10:0] ram_rd_addr;

assign e_gtxc=~tx_clk;	 
assign e_reset = 1'b1; 

wire [31:0] datain_reg;
         
wire [3:0] tx_state;
wire [3:0] rx_state;
wire [15:0] rx_total_length;          //rx 的IP包的长度
wire [15:0] tx_total_length;          //tx 的IP包的长度
wire [15:0] rx_data_length;           //rx 的UDP的数据包长度
wire [15:0] tx_data_length;           //rx 的UDP的数据包长度

wire data_receive;
reg ram_wr_finish;
reg ram_wren_i;
reg [10:0] ram_addr_i;
reg [31:0] ;

wire data_o_valid;
wire wea;
wire [10:0] addra;
wire [31:0] dina;

assign wea=ram_wr_finish?data_o_valid:ram_wren_i;
assign addra=ram_wr_finish?ram_wr_addr:ram_addr_i;
assign dina=ram_wr_finish?ram_wr_data:ram_data_i;


assign tx_data_length=16'd8200;//data_receive?rx_data_length:16'd36;
assign tx_total_length=16'd8220;//data_receive?rx_total_length:16'd56;

wire pll_clk,tx_clk;
pll_zsj pll1(
	.areset(1'b0),
	.inclk0(fpga_gclk),
	.c0(pll_clk),
	.c1(tx_clk),
	.locked());


/*************************系统时钟************************/

SCKI	SCKI_inst (
	.inclk0 ( fpga_gclk ),
	.c0 ( SCKI )// 24.572650Mhz,256fs
	);
	
	
	
/*********************************************************/

/*************************ad驱动模块实例化************************/
wire [31:0] data_parellel;
wire LRCK_detcet;
wire pos_edge;
wire neg_edge;
wire LRCK_double;// 将LRCK倍频后的信号
 ad_driver ad_driver_inst(
	.DATA(DATA),
	.reset_n(reset_n), 
	.BCK(BCK),
	.fpga_gclk(fpga_gclk),
	.LRCK_double(LRCK_double),
    .SCKI(SCKI),
    .OSR0(OSR0),	 
    .OSR1(OSR1),	 
    .OSR2(OSR2),
    .FMT0(FMT0),
    .FMT1(FMT1),
    .SM(SM),
    .LRCK(LRCK),
    .BYPAS(BYPAS),
    .RST_n(RST_n),
	._parellel(data_parellel),
	.LRCK_detcet(LRCK_detcet),
	.pos_edge(pos_edge),
	.neg_edge(neg_edge)
);
/************************************************************/

/*******************控制udp发送的时间*************************/
// reg [27:0] count;
// always @(posedge e_rxc)
// begin	
// 	if (count == 28'd12500000)
// 		count <= 28'd0;
// 	else 
// 		count <= count + 1'b1;
// end 

// wire send_trigger = (count == 28'd12500000);

// //控制何时向ram里面写入数据（在每个100ms的中点（即50ms处）向ram中写入数据，且写完停止）;
// // 这里要注意能不能对上存入时钟的上升沿(将wr_start延迟为1ms来确定ram写入端的时钟一定采到了wr_start)
// // wire wr_start = ((count > 28'd6250000) & (count < 28'd6375000));
// wire wr_start = ((count > 28'd6250000) & (count < 28'd6375000)) & LRCK;

reg [27:0] count;
always @(posedge fpga_gclk)
begin	
	if (count == 28'd5000000)
		count <= 28'd0;
	else 
		count <= count + 1'b1;
end 

wire send_trigger = (count == 28'd5000000);

//控制何时向ram里面写入数据（在每个100ms的中点（即50ms处）向ram中写入数据，且写完停止）;
// 这里要注意能不能对上存入时钟的上升沿(将wr_start延迟为1ms来确定ram写入端的时钟一定采到了wr_start)
// wire wr_start = (count == 2500000);
wire wr_start = (count == 1000000);

/************************************************************/



/*******************ram地址的改变—— method 1 *************************/
// 使用倍频后的时钟来推进，同时检测LRCK的高电平将地址归零，所以ram中每次第一个存的一定是右通道的值，ram地址依旧一直递增，直到存满为止
// reg [10:0] wr_addr_test;
// always @(posedge LRCK_double)
// // always @(posedge fpga_gclk)		
// begin 
// 	// if (wr_start & LRCK)
// 	if (wr_start)
// 		wr_addr_test <= 11'h0;
// 	else if (&wr_addr_test)
// 		wr_addr_test <= wr_addr_test;
// 	else 
// 		wr_addr_test <= wr_addr_test + 1'b1;
// end 
// wire [31:0] dat_tmp = data_parellel;
/************************************************************/

/*******************ram地址的改变—— method 2 *************************/
// 使用50Mhz的系统时钟来作为地址改变的时钟，检测的边沿作为地址改变的使能
// reg [10:0] wr_addr_test;
// always @(posedge fpga_gclk)	
// begin 
// 	if (wr_start & LRCK)
// 		wr_addr_test <= 11'h0;
// 		else if (&wr_addr_test)
// 			wr_addr_test <= wr_addr_test;
// 		else if (LRCK_detcet) begin
// 			wr_addr_test <= wr_addr_test + 1'b1;
// 		end
// 		else
// 			wr_addr_test <= wr_addr_test + 1'b1;
// end 
// wire [31:0] dat_tmp = data_parellel;




// 使用50Mhz的系统时钟来作为地址改变的时钟，检测的边沿作为地址改变的使能
// reg [10:0] wr_addr_test;
// always @(posedge fpga_gclk)	
// begin 
// 	if (wr_start)
// 		wr_addr_test <= 11'h0;
// 	else if (&wr_addr_test)
// 		wr_addr_test <= wr_addr_test;
// 	else if (LRCK_detcet) begin
// 		wr_addr_test <= wr_addr_test + 1'b1;
// 	end
// 	else
// 		wr_addr_test <= wr_addr_test;
// end 
// wire [31:0] dat_tmp = data_parellel;



/************************************************************/

/*******************ram地址的改变—— method 3 *************************/
// 使用50Mhz的系统时钟来作为地址改变的时钟，检测的边沿作为地址改变的使能,奇_ws.col.info == "8080 → 8080 [BAD UDP LENGTH 8200 > IP PAYLOAD LENGTH] Len=8192"偶地址的开始用lrck来判断

/*
reg [10:0] wr_addr_test;
always @(posedge fpga_gclk)	
begin 
	if (wr_start & LRCK)// 0地址存储的是左通道的值
		wr_addr_test <= 11'h0;
	else if (wr_start & (~LRCK)) begin
		wr_addr_test <= 11'h1;
	end
	else if (&wr_addr_test)
		wr_addr_test <= wr_addr_test;
	else if (LRCK_detcet) begin
		wr_addr_test <= wr_addr_test + 1'b1;
	end
end 
*/



reg [10:0] wr_addr_test;
always @(posedge fpga_gclk)	
begin 
//	if (wr_start)
//		wr_addr_test <= 11'h0;
	if (wr_start & LRCK)// 0地址存储的是左通道的值
		wr_addr_test <= 11'h0;
	else if (wr_start & (~LRCK)) begin
		wr_addr_test <= 11'h1;
		end
	else if (LRCK_detcet)
		wr_addr_test <= wr_addr_test + 1'b1;
end 

wire [31:0] dat_tmp = data_parellel;

/************************************************************/

//////////ram用于存储以太网接收到的数据或测试数据///////////////////
ram ram_inst
(
	.data			(dat_tmp),
	.inclock		(fpga_gclk),
	.outclock	(pll_clk),
	.rdaddress	(ram_rd_addr),
	.wraddress	(wr_addr_test),
	// .wren			(wr_en),
	.wren       (LRCK_detcet),
	.q				(ram_rd_data)
);

////////udp发送和接收程序/////////////////// 
udp u1(
	.reset_n(reset_n),
	.e_rxc(pll_clk),
	.e_rxd(e_rxd),
   .e_rxdv(e_rxdv),
	.data_o_valid(data_o_valid),                    //数据接收有效信号,写入RAM/
	.ram_wr_data(ram_wr_data),                      //接收到的32bit数据写入RAM/	
	.rx_total_length(rx_total_length),              //接收IP包的总长度/
	.mydata_num(mydata_num),                        //for  test
	.rx_state(rx_state),                            //for  test
	.rx_data_length(rx_data_length),                //接收IP包的数据长度/	
	.ram_wr_addr(ram_wr_addr),
	.data_receive(data_receive),
	
	.e_txen(e_txen),
	.e_txd(e_txd),
	.e_txer(e_txer),	
	.ram_rd_data(ram_rd_data),                      //RAM读出的32bit数据/
	.tx_state(tx_state),                            //for test
	.datain_reg(datain_reg),                        //for test
	.send_trigger(send_trigger),
	.tx_data_length(tx_data_length),                //发送IP包的数据长度/	
	.tx_total_length(tx_total_length),              //接发送IP包的总长度/
	.ram_rd_addr(ram_rd_addr)

	);


endmodule
