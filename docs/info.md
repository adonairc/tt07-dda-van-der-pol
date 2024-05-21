<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The DDA core expects to receive via SPI port the parameter for the van der Pol oscillator encoded in posit (16,1) padded with 2 bytes zero to compose a 32-bit word. When an SPI message is started by the master (SPI CS pin low) the integrators are clocked and solutions for both state variables, x and y, are transmitted back serially via SPI in a single 32-bit word for each time step. Simulation can be stopped by stopping communication via SPI. 


## How to test

In order to test chip reset the chip (RST_N low) and start a duplex SPI communication transmitting 32-bit word with the van der Pol parameter $\mu$ encoded in Posit (16,1) using the 16 bits LSB of the 32-bit word (padded with zeros). 

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
