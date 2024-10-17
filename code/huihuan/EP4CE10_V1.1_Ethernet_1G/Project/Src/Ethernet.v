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
					output [7:0] e_txd	 
  
    );
                

wire [31:0] ram_wr_data;
wire [31:0] ram_rd_data;
wire [8:0] ram_wr_addr;
wire [8:0] ram_rd_addr;

assign e_gtxc=e_rxc;	 
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

reg [31:0] udp_data [6:0];                        //存储发送字符
reg ram_wren_i;
reg [8:0] ram_addr_i;
reg [31:0] ram_data_i;
reg [4:0] i=0;

wire data_o_valid;
wire wea;
wire [8:0] addra;
wire [31:0] dina;


wire [15:0] fsin_o;
wire [15:0] fcos_o;
reg[6:0] phi_inc_i;

assign wea=ram_wren_i;//ram_wr_finish?data_o_valid:ram_wren_i;
assign addra=ram_addr_i;//ram_wr_finish?ram_wr_addr:ram_addr_i;
assign dina=ram_data_i;//ram_wr_finish?ram_wr_data:ram_data_i;


assign tx_data_length=16'd1032;//data_receive?rx_data_length:16'd36;
assign tx_total_length=16'd1052;//data_receive?rx_total_length:16'd56;

////////udp发送和接收程序/////////////////// 
udp u1(
	.reset_n(reset_n),
	.e_rxc(e_rxc),
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
	.tx_trig(tx_trig),
	.e_txen(e_txen),
	.e_txd(e_txd),
	.e_txer(e_txer),	
	.ram_rd_data(ram_rd_data),                      //RAM读出的32bit数据/
	.tx_state(tx_state),
	//.tx_trig(tx_trig),	//for test
	.datain_reg(datain_reg),                        //for test
	.tx_data_length(tx_data_length),                //发送IP包的数据长度/	
	.tx_total_length(tx_total_length),              //接发送IP包的总长度/
	.ram_rd_addr(ram_rd_addr)

	);


//////////ram用于存储以太网接收到的数据或测试数据///////////////////
ram ram_inst
(
	.data			({fcos_o,fsin_o}),
	.inclock		(fpga_gclk),
	.outclock	(e_rxc),
	.rdaddress	(ram_rd_addr),
	.wraddress	(addra),
	.wren			(1'b1),
	.q				(ram_rd_data)
);
nco_ip_st	inst(
		.phi_inc_i(phi_inc_i),
		.clk(fpga_gclk),
		.reset_n(1'd1),
		.clken(1'd1),
		.fsin_o(fsin_o),
		.fcos_o(fcos_o),
		.out_valid()
);	


reg [19:0] count;
always @(posedge fpga_gclk)
begin 
		if (count == 20'hffff7)
			count <= 20'h0;
		else 
			count <= count + 1'b1;
end

reg tx_trig;
always @(posedge fpga_gclk)	
begin 
	if (count == 20'hffff7)
		tx_trig <= 1'b1;
	else if(count == 20'h7)
		tx_trig <= 1'b0;
end 


always @(posedge fpga_gclk)	begin
	if (count == 20'h80000)	
		ram_addr_i <= 0;
	else if (&ram_addr_i)
		ram_addr_i <= ram_addr_i;
	else 
		ram_addr_i <= ram_addr_i + 1'b1;
end 


always @(posedge fpga_gclk)	begin 

phi_inc_i=7'd82;
end


endmodule
/********************************************/
//存储待发送的字符
/********************************************/
/*
always @(*)
begin     //定义发送的字符
	 udp_data[0]<={8'h45,8'h45,8'h4c,8'h4c};	//H		E		L		L 
	 udp_data[1]<={8'h4f,8'h20,8'h57,8'h4f};	//O		空格	W		O 
    udp_data[2]<={8'h52,8'h4c,8'h44,8'h0a};	//R		L		D		转行
	 udp_data[3]<={8'h77,8'h77,8'h77,8'h2e};	//w		w		w		. 	 
	 udp_data[4]<={8'h68,8'h73,8'h65,8'h64};	//h		s		e		d                           
	 udp_data[5]<={8'h61,8'h2e,8'h63,8'h6f};	//a		.		c		o	
	 udp_data[6]<={8'h6d,8'h20,8'h20,8'h0a};	//m		空格	空格	换行  
end 

*/
//////////写入默认发送的数据//////////////////
/*
always@(posedge e_rxc or negedge reset_n)
begin	
  if(!reset_n) 
  begin
     ram_wr_finish<=1'b0;
	  ram_addr_i<=0;
	  ram_data_i<=0;
	  i<=0;
  end
  else begin
     if(i==7) begin
        ram_wr_finish<=1'b1;
        ram_wren_i<=1'b0;		  
     end
     else begin
        ram_wren_i<=1'b1;
		  ram_addr_i<=ram_addr_i+1'b1;
		  ram_data_i<={fsin_o,fcos_o};
		  i<=i+1'b1;
	  end
  end 
end 


endmodule
*/