/*
 * Copyright 2020 Brian O'Dell
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

`include "cores/osdvu/uart.v"
`include "cores/megamemnon/bram.v"


module b1 #(
	parameter RAM_ADDR_WIDTH = 13
	) (
	input CLK,
	input RS232_Rx_TTL,
	output RS232_Tx_TTL,
	output LED0,
	output LED1,
	output LED2,
	output LED3,
	output LED4,
	output LED5,
	output LED6,
	output LED7
   );

	//States
	localparam B1_STATE_0 = 'd0;			//Ready to load opcode
	localparam B1_STATE_1 = 'd1;			//load opcode
	localparam B1_STATE_2 = 'd2;			//increment IP; decode
	localparam B1_STATE_3 = 'd3;			//
	localparam B1_STATE_4 = 'd4;			//
	localparam B1_STATE_5 = 'd5;			//
	localparam B1_STATE_200 = 'd200;		//ready to receive external byte
	localparam B1_STATE_201 = 'd201;		//echo rcvd byte and go to State 2
	localparam B1_STATE_202 = 'd202;		//clean up and return to State 0
	localparam B1_STATE_203 = 'd203;		//echo CR and go to State 4
	localparam B1_STATE_204 = 'd204;		//clean up and go to State 5
	localparam B1_STATE_205 = 'd205;		//echo LF and go to State 2
	localparam B1_STATE_206 = 'd206;		//load byte from UART buffer
	localparam B1_STATE_207 = 'd207;		//transmit UART buffer byte
	localparam B1_STATE_208 = 'd208;  	//prep to load next UART buffer byte
	localparam B1_STATE_209 = 'd209;  	//clean up and return to state 0

	reg [7:0]	b1_state = B1_STATE_200;


	//cpu
	localparam IP_START = 16'h200;

	reg 		reset_n = 1'b0;
	wire [15:0]	addr;
	wire [7:0]	cpu_data_in;
	wire [7:0]	cpu_data_out;
	reg  [15:0]	IP = IP_START;
	reg	 [7:0]	IR;
	reg  [7:0]	AH;
	reg  [7:0]	AL;
	reg  [7:0]  X;
	reg  [7:0]	I;

	//ram
	localparam RAM_SIZE = (1 << RAM_ADDR_WIDTH);


	wire		ram_cs_n;
	wire		ram_rd_n;
	wire		ram_wr_n;
	
	//uart
	localparam UART_BUFFER_START = 'h0;
	localparam UART_BUFFER_SIZE = 'hFF;
	localparam UART_STATE_0 = 3'b000;
	localparam UART_STATE_1 = 3'b001;
	localparam UART_STATE_2 = 3'b010;
	localparam UART_STATE_3 = 3'b011;
	localparam UART_STATE_4 = 3'b100;
	localparam UART_STATE_5 = 3'b101;
	localparam UART_STATE_6 = 3'b110;
	localparam UART_STATE_7 = 3'b111;


	reg 		transmit;
	reg 		[7:0] tx_byte;
	wire 		received;
	wire 		[7:0] rx_byte;
	wire 		is_receiving;
	wire 		is_transmitting;
	wire 		recv_error;
	reg 		uart_reset;
	reg [15:0] 	uart_nxtptr = UART_BUFFER_START;
	reg [15:0]	uart_ptr = UART_BUFFER_START;
	reg [7:0]	uart_buffer [0:UART_BUFFER_SIZE - 1];
	reg [3:0]	uart_state;
	
	bram #(
		.BRAM_ADDR_WIDTH(RAM_ADDR_WIDTH), 
		.BRAM_DATA_WIDTH(8)
	)
	ram(
		.clk			(CLK),
		.addr			(addr[RAM_ADDR_WIDTH - 1:0]),
		.cs_n			(ram_cs_n),
		.wr_n			(ram_wr_n),
		.rd_n			(ram_rd_n),
		.bram_data_in	(cpu_data_out),
		.bram_data_out	(cpu_data_in)
	);

	uart #(
		.baud_rate(9600),                 // The baud rate in kilobits/s
		.sys_clk_freq(12000000)           // The master clock frequency
	)
	uart0(
		.clk(CLK),                    // The master clock for this module
		.rst(uart_reset),                      // Synchronous reset
		.rx(RS232_Rx_TTL),                // Incoming serial line
		.tx(RS232_Tx_TTL),                // Outgoing serial line
		.transmit(transmit),              // Signal to transmit
		.tx_byte(tx_byte),                // Byte to transmit
		.received(received),              // Indicated that a byte has been received
		.rx_byte(rx_byte),                // Byte received
		.is_receiving(is_receiving),      // Low when receive line is idle
		.is_transmitting(is_transmitting),// Low when transmit line is idle
		.recv_error(recv_error)           // Indicates error in receiving packet.
	);

	assign {LED7, LED6, LED5, LED4, LED3, LED2, LED1, LED0} = rx_byte[7:0];
	// assign {LED7, LED6, LED5, LED4, LED3, LED2, LED1, LED0} = IP[15:8];

	assign addr = (b1_state == B1_STATE_0 || b1_state == B1_STATE_1) 
			? IP
		: 16'bz;
	assign cpu_data_out = b1_state == B1_STATE_201 ? rx_byte : 8'bz;
	assign ram_cs_n = b1_state == B1_STATE_201 ? 1'b0 
		: 1'b1;
	assign ram_wr_n = b1_state == B1_STATE_201 ? 1'b0 
		: 1'b1;
	assign ram_rd_n = b1_state == B1_STATE_206 ? 1'b0 
		: 1'b1;


	always @(posedge CLK) begin
		if (reset_n == 1'b0) begin
			reset_n <= 1'b1;
			uart_reset <= 1'b0;
		end 
		//Instruction States
		if (b1_state == B1_STATE_0) begin
			b1_state <= B1_STATE_1;
		end
		if (b1_state == B1_STATE_1) begin
			IR <= cpu_data_in;
			b1_state <= B1_STATE_2;
		end
		if (b1_state == B1_STATE_2) begin
		//decode IR
			if (IR & 8'b10000000) begin
				//Data Movement Opcodes
				
			end
			IP <= IP + 1;
			b1_state <= B1_STATE_3;
		end
		if (b1_state == B1_STATE_3) begin
			if (uart_nxtptr != uart_ptr && ~is_transmitting) begin
				tx_byte <= uart_buffer[uart_ptr];
				transmit <= 1'b1;
				b1_state <= B1_STATE_4;
			end
			else begin
				b1_state <= B1_STATE_0;
			end
		end
		if (b1_state == B1_STATE_4) begin
			transmit <= 1'b0;
			if (uart_ptr == (UART_BUFFER_START + UART_BUFFER_SIZE)) begin
				uart_ptr <= UART_BUFFER_START;
			end
			else begin
				uart_ptr <= uart_ptr + 1'b1;
			end
			b1_state <= B1_STATE_0;
		end




		//UART States
		if (received && uart_state == UART_STATE_0) begin 
			// echo byte
			tx_byte <= rx_byte;
			transmit <= 1'b1;
			uart_buffer[uart_nxtptr] <= rx_byte;
			uart_state <= UART_STATE_1;
		end
		if (uart_state == UART_STATE_1) begin
			// clean up UART
			transmit <= 1'b0;
			// increment UART write ptr
			if (uart_nxtptr == (UART_BUFFER_SIZE + UART_BUFFER_START)) begin
				uart_nxtptr <= UART_BUFFER_START;
			end
			else begin
				uart_nxtptr <= uart_nxtptr + 1'b1;
			end
			uart_state <= UART_STATE_0;
		end
	end
 
endmodule // b1
