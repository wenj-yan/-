module Ethernet(
					input reset_n,                      //复位信号  
					input  fpga_gclk,                   //FPGA全局时钟
					output e_reset,							//以太网复位信号

               output e_mdc,								//以太网MDC信号     总线时钟信号   MAC -> PHY
					inout  e_mdio,								//以太网MDIO信号	 数据线			MAC <-> PHY
		
					input	 e_rxc,                 //千兆以太网GMII接收时钟，频率为125MHz，用于同步接收数据。//125Mhz ethernet gmii rx clock
					input	 e_rxdv,						//以太网GMII数据有效信号，表示接收到的数据有效。
					input	 e_rxer,						//以太网GMII接收错误信号，用于指示接收过程中是否发生错误。
					input  [7:0] e_rxd,        		//以太网GMII接收数据线，包含8位数据。

					input	 e_txc,                  //以太网MII发送时钟，频率为25MHz，用于同步发送数据。  //25Mhz ethernet mii tx clock         
					output e_gtxc,                //以太网GMII发送时钟，与接收时钟相同，频率为125MHz。     //25Mhz ethernet gmii tx clock  
					output e_txen, 					//以太网发送使能信号，表示发送数据的使能状态。
					output e_txer, 					//以太网发送错误信号，用于指示发送过程中是否发生错误。
					output [7:0] e_txd				//以太网MII发送数据线，包含8位数据。
  
    );
                

wire [31:0] ram_wr_data;				//RAM写数据
wire [31:0] ram_rd_data;				//RAM读数据
wire [8:0] ram_wr_addr;					//RAM写地址
wire [8:0] ram_rd_addr;					//RAM读地址

assign e_gtxc=e_rxc;	 					//以太网GMII TX时钟与以太网GMII RX时钟连接
assign e_reset = 1'b1; 					//并将以太网复位信号置为高电平。

wire [31:0] datain_reg;					//声明一个32位宽的寄存器。
         
wire [3:0] tx_state;  //发送状态
wire [3:0] rx_state;  //接收状态
wire [15:0] rx_total_length;          //rx 的IP包的长度
wire [15:0] tx_total_length;          //tx 的IP包的长度
wire [15:0] rx_data_length;           //rx 的UDP的数据包长度
wire [15:0] tx_data_length;           //rx 的UDP的数据包长度

wire data_receive;						 //数据接收是否成功
reg ram_wr_finish;                   //RAM是否写完

reg [31:0] udp_data [6:0];           //声明了一个二维数组 udp_data，每个元素是一个32位宽的寄存器，共有7个元素，用于存储发送字符。             //存储发送字符
reg ram_wren_i;			//可能用于指示是否允许对RAM进行写操作
reg [8:0] ram_addr_i;	// 用于存储RAM的地址信息，地址宽度为9位。
reg [31:0] ram_data_i;	// 用于存储RAM的数据信息，数据宽度为32位。
reg [4:0] i=0;			//可能用于循环计数或者其他用途。

wire data_o_valid;
wire wea;			//可能用于控制RAM的写使能信号
wire [8:0] addra; //用于传输RAM的地址信息，地址宽度为9位。
wire [31:0] dina; //用于传输RAM的数据信息，数据宽度为32位。


wire [15:0] fsin_o;
wire [15:0] fcos_o;
reg[6:0] phi_inc_i;  //频率控制字

assign wea=ram_wren_i;
assign addra=ram_addr_i;   //RAM传输的等于存储的
assign dina=ram_data_i;


assign tx_data_length=16'd1032;
assign tx_total_length=16'd1052;

////////udp发送和接收程序/////////////////// 
udp u1(
	.reset_n(reset_n),    //将外部的复位信号 reset_n 连接到UDP模块的复位端口。
	.e_rxc(e_rxc),			///将外部的以太网接收时钟信号 e_rxc 连接到UDP模块的接收时钟端口。
	.e_rxd(e_rxd),			//将外部的以太网接收数据信号 e_rxd 连接到UDP模块的接收数据端口。
   .e_rxdv(e_rxdv),		 //将外部的以太网接收数据有效信号 e_rxdv 连接到UDP模块的接收数据有效端口。
	.data_o_valid(data_o_valid),                   //将UDP模块的数据接收有效信号连接到外部信号 data_o_valid，用于指示数据接收并写入RAM。  //数据接收有效信号,写入RAM/
	.ram_wr_data(ram_wr_data),                      //将UDP模块接收到的32位数据连接到RAM的写数据端口       //接收到的32bit数据写入RAM/	
	.rx_total_length(rx_total_length),              //将接收到的IP包的总长度连接到UDP模块的总长度端口。//接收IP包的总长度/
	.mydata_num(mydata_num),                        //for  test用于测试的数据端口
	.rx_state(rx_state),                            //for  test用于测试的接收状态端口
	.rx_data_length(rx_data_length),                //接收IP包的数据长度/	
	.ram_wr_addr(ram_wr_addr),								 //将RAM的写地址端口连接到UDP模块的RAM写地址端口。
	.data_receive(data_receive),							//将数据接收端口连接到外部信号 data_receive
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
	.data			({fcos_o,fsin_o}),/////////////////////////
	.inclock		(fpga_gclk),///将fpaga时钟连接到RAM模块的输入时钟端口。。//////////////
	.outclock	(e_rxc),  //将以太网接收时钟信号连接到RAM模块的输出时钟端口。
	.rdaddress	(ram_rd_addr),//将RAM模块的读地址端口连接到外部信号 ram_rd_addr
	.wraddress	(addra),   //将RAM模块的写地址端口连接到外部信号 addra，可能是根据条件选择的RAM写地址。
	.wren			(1'b1), //将RAM模块的写使能端口连接到外部信号 wea，可能是根据条件选择的RAM写使能信号。
	.q				(ram_rd_data)// 将RAM模块的输出数据端口连接到外部信号 ram_rd_data，用于传输RAM读出的数据信息。
);
nco_ip_st	inst(
		.phi_inc_i(phi_inc_i),
		.clk(fpga_gclk),
		.reset_n(1'd1),       // 开始复位信号位1
		.clken(1'd1),
		.fsin_o(fsin_o),
		.fcos_o(fcos_o),
		.out_valid()
);	


reg [19:0] count;   // 20位

always @(posedge fpga_gclk)    //FPGA时钟的上升沿
begin 
		if (count == 20'hffff7)
			count <= 20'h0;
		else 
			count <= count + 1'b1;
end

reg tx_trig;

always @(posedge fpga_gclk)	
begin 
	if (count == 20'hffff7)    //1,048,567
		tx_trig <= 1'b1;      
	else if(count == 20'h7)   //7
		tx_trig <= 1'b0;
end 


always @(posedge fpga_gclk)	begin
	if (count == 20'h80000)	   // 524,288
		ram_addr_i <= 0;       // 用于存储RAM的地址信息，地址宽度为9位。
	else if (&ram_addr_i)    // &位缩减运算符，从第一位开始与第二位相与，结果再与第三位相与，最后输出0或1
		ram_addr_i <= ram_addr_i;
	else 
		ram_addr_i <= ram_addr_i + 1'b1;
end 


always @(posedge fpga_gclk)	begin 

phi_inc_i=7'd82;     // 频率控制字为82
end


endmodule
