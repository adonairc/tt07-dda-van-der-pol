# Copyright (c) 2024 Adonai Cruz
# SPDX-License-Identifier: MIT

import cocotb
import os
import random
from cocotb.clock import Clock
from cocotb.triggers import Timer
from cocotb.binary import BinaryValue
from posit import from_bits, from_double

# Posit parameters
N = 16
ES = 1

def resolve_GL_TEST():
    gl_test = False
    if 'GL_TEST' in os.environ:
        gl_test = True
    if 'GATES' in os.environ and os.environ['GATES'] == 'yes':
        gl_test = True
    return gl_test

    
# SPI
async def spiExchange(dut,data_to_send):
    assert len(data_to_send) == 4
    data_received = []
    v = BinaryValue()
    s = ''
    for byte in data_to_send:
        s += f'{byte:0>8b}'
    v.binstr = s
    
    # 32-bit word duplex
    for i in range(32):
        dut.uio_in[1].value = int(v.binstr[i])
        dut.uio_in[3].value = 0
        
        await Timer(100,'ns')
        dut.uio_in[0].value = 0
        dut.uio_in[3].value = 1

        await Timer(100,'ns')
        dut.uio_in[3].value = 0

        await Timer(100,'ns')
        data_received.append(dut.uio_out[2].value)

    dut.uio_in[0].value = 1
    return (data_received)

# Test Posit multiplication module
@cocotb.test()
async def posit_multiplication(dut):
    GL_TEST = resolve_GL_TEST()

    if not GL_TEST:
        dut._log.info("Testing Posit multiplication module")
        
        # Multiply x*x
        mult = dut.user_project.van_der_pol.mult1
        # mult = dut.user_project["\\van_der_pol.mult1"]
        assert mult.N.value == 16,"N"
        assert mult.ES.value == 1,"ES"

        for _ in range(25):
            a = random.uniform(-10,10)

            p_a = from_double(x=a, size=N, es=ES)
            p_mult = p_a*p_a

            ba = BinaryValue(bytes(p_a.bit_repr().to_bytes(2,"big")))

            mult.in1.value = ba
            mult.in2.value = ba

            await Timer(10,'ns')
            assert mult.out.value.integer == p_mult.bit_repr()


# Test van der Pol DDA solver
@cocotb.test()
async def dda(dut):
    GL_TEST = resolve_GL_TEST()

    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    f_out = open(f"output.dat","w")
    
    dut.uio_in[3].value = 0 # sclk = 0
    dut.uio_in[0].value = 1 # cs = 1
    dut.rst_n.value = 0
    
    # Clock the DDA by starting SPI communication
    # set initial coditions for X and Y and parameter MU
    dut._log.info("Resetting DDA")
   
    # Van-der-Pol oscillator parameter
    mu = 2.0

    # Encode mu in Posit (16,1) representation 
    p_mu = from_double(x=mu, size=N, es=ES)
    s = bytearray(p_mu.bit_repr().to_bytes(4,"big"))

    for _ in range(2):
        data = await spiExchange(dut,s)
    
    # Verify parameter mu
    
    if not GL_TEST:
        assert dut.user_project.mu.value.integer == p_mu.bit_repr(), "Testing parameter mu"

    # Run solver
    dut._log.info("Running DDA")
    dut.rst_n.value = 1

    data_x = []
    data_y = []
    for _ in range(64):
        data = await spiExchange(dut,s)
        x = data[0:16]
        y = data[16:32]
        data_x.append(x)
        data_y.append(y)
        x_bytes = [int("".join(map(str, x[i:i+8])), 2) for i in range(0, len(x), 8) ]
        y_bytes = [int("".join(map(str, y[i:i+8])), 2) for i in range(0, len(y), 8) ]

        p_x = from_bits(int.from_bytes(bytearray(x_bytes),byteorder='big'),N,ES)
        p_y = from_bits(int.from_bytes(bytearray(y_bytes),byteorder='big'),N,ES)
        
        f_out.write(f"{p_x.eval()}, {p_y.eval()}\n")

    #Test initial conditions
    icx = BinaryValue()
    icx.binstr = "".join(str(i) for i in data_x[0])
    assert icx.binstr ==  "0011000000000000", "Verify x initial condition"

    icy = BinaryValue()
    icy.binstr = "".join(str(i) for i in data_y[0])
    assert icy.binstr ==  "0011000000000000", "Verify y initial condition"

    f_out.close()