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
  
	//cpu
	reg 		reset_n = 1'b0;
	wire [15:0]	addr;
	wire [7:0]	cpu_data_in;
	wire [7:0]	cpu_data_out;

	//ram
	localparam RAM_SIZE = (1 << RAM_ADDR_WIDTH);

	wire		ram_cs_n;
	wire		ram_rd_n;
	wire		ram_wr_n;
	
	//uart
	localparam UART_BUFFER_START = 16'h0;
	localparam UART_BUFFER_SIZE = 16'hFF;
	localparam UART_STATE_0 = 4'b0000;	//ready to receive external byte
	localparam UART_STATE_1 = 4'b0001;	//echo rcvd byte and go to State 2
	localparam UART_STATE_2 = 4'b0010;	//clean up and return to State 0
	localparam UART_STATE_3 = 4'b0011;	//echo CR and go to State 4
	localparam UART_STATE_4 = 4'b0100;	//clean up and go to State 5
	localparam UART_STATE_5 = 4'b0101;	//echo LF and go to State 2
	localparam UART_STATE_6 = 4'b0110;	//load byte from UART buffer
	localparam UART_STATE_7 = 4'b0111;	//transmit UART buffer byte
	localparam UART_STATE_8 = 4'b1000;  //
	localparam UART_STATE_9 = 4'b1001;  //


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
	reg [3:0]	uart_state = UART_STATE_0;
	
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
	assign addr = uart_state == UART_STATE_1 ? uart_nxtptr 
		: uart_state == UART_STATE_6 || uart_state == UART_STATE_7 ? uart_ptr 
		: 16'bz;
	assign cpu_data_out = uart_state == UART_STATE_1 ? rx_byte : 8'bz;
	assign ram_cs_n = uart_state == UART_STATE_1 || uart_state == UART_STATE_6? 1'b0 
		: 1'b1;
	assign ram_wr_n = uart_state == UART_STATE_1 ? 1'b0 
		: 1'b1;
	assign ram_rd_n = uart_state == UART_STATE_6 ? 1'b0 
		: 1'b1;


	always @(posedge CLK) begin
		if (reset_n == 1'b0) begin
			reset_n <= 1'b1;
			uart_reset <= 1'b0;
		end
		if (received && uart_state == UART_STATE_0) begin 
			if (rx_byte == 8'h0D) begin
				uart_state <= UART_STATE_3;
			end
			else if (rx_byte == 8'h60 && uart_ptr < uart_nxtptr) begin
				uart_state <= UART_STATE_6;
			end
			else begin
				uart_state <= UART_STATE_1;
			end
		end 
		if (uart_state == UART_STATE_1 && ~is_receiving && ~is_transmitting) begin
			// echo byte
			tx_byte <= rx_byte;
			transmit <= 1'b1;
			uart_state <= UART_STATE_2;
		end
		if (uart_state == UART_STATE_2 && ~is_receiving && ~is_transmitting) begin
			// clean up UART
			transmit <= 1'b0;
			uart_state <= UART_STATE_0;
			// increment UART write ptr
			if (uart_nxtptr == (UART_BUFFER_SIZE + UART_BUFFER_START)) begin
				uart_nxtptr <= UART_BUFFER_START;
			end
			else begin
				uart_nxtptr <= uart_nxtptr + 1'b1;
			end
		end
		if (uart_state == UART_STATE_3 && ~is_receiving && ~is_transmitting) begin
				tx_byte <= 8'h0D;
				transmit <= 1'b1;
				uart_state <= UART_STATE_4;
		end
		if (uart_state == UART_STATE_4) begin
				transmit <= 1'b0;
				uart_state <= UART_STATE_5;
		end
		if (uart_state == UART_STATE_5 && ~is_receiving && ~is_transmitting) begin
				tx_byte <= 8'h0A;
				transmit <= 1'b1;
				uart_state <= UART_STATE_2;
		end
		if (uart_state == UART_STATE_6) begin
			uart_state <= UART_STATE_7;
		end
		if (uart_state == UART_STATE_7 && ~is_receiving && ~is_transmitting) begin
			// transmit UART buffer byte
			tx_byte <= cpu_data_in;
			transmit <= 1'b1;
			if (cpu_data_in == 8'b00000000) begin
				uart_state <= UART_STATE_9;
			end
			else begin
				uart_state <= UART_STATE_8;
			end
		end
		if (uart_state == UART_STATE_8) begin
			// clean up UART
			transmit <= 1'b0;
			// increment UART read ptr
			if (uart_ptr == (UART_BUFFER_SIZE + UART_BUFFER_START)) begin
				uart_ptr <= UART_BUFFER_START;
			end
			else begin
				uart_ptr <= uart_ptr + 1'b1;
			end
			uart_state <= UART_STATE_6;
		end
		if (uart_state == UART_STATE_9) begin
			// clean up UART
			transmit <= 1'b0;
			// increment UART read ptr
			if (uart_ptr == (UART_BUFFER_SIZE + UART_BUFFER_START)) begin
				uart_ptr <= UART_BUFFER_START;
			end
			else begin
				uart_ptr <= uart_ptr + 1'b1;
			end
			uart_state <= UART_STATE_0;
		end
	end
 
endmodule // b1
