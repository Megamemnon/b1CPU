# b1CPU
The purpose of this project is to design a CPU in Verilog around high level functions to manage communications with peripherals (UART, SPI, etc) and flow control in addition to essential memory management.

## Peripherals
* UART - well documented uart.v developed by Timothy Goddard and Aaron Dahlen
* Arithmetic Unit - memory mapped Adder OR ALU (unselected)
* SPI (unselected)
* I2C (unselected)

## Memory Management
* RAM only - no ROM; memory contents typically stored in ROM will be embedded in lower onboard RAM when the FPGA boots
* Memory mapped registers and peripheral buffers - contained within the FPGA low RAM
* External Address and Data buses - accomodating additional external RAM

## Flow Control
* Conditional Jumps
* Iterators
* Flow Control Stack in onboard RAM

# Make Instructions
* ```make clean``` to clean
* ```make``` to build
* ```make flash``` to flash FPGA ram

# Status
* tested on iCE40 HX8K
* includes ram, using block ram on the FPGA
* includes a UART with 256 bytes of buffer space in ram
