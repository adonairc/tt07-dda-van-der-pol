from pyftdi.spi import SpiController
from posit import from_bits, from_double

spi_ctrl = SpiController()
spi_ctrl.configure('ftdi://ftdi:232h:1/1')
spi_ctrl.flush()

# spi = spi_ctrl.get_port(0)
# spi.set_frequency(1e5) # SCLK 
spi = spi_ctrl.get_port(cs=0, freq=1E5, mode=0)

mus = [ 0.0, 2.0, 5.0]
N = 10000

f_out = open("fpga.dat","w")
for mu in mus:
    p_mu = from_double(x=mu, size=16, es=1)
    print("mu = ",p_mu.bit_repr().to_bytes(4,byteorder='big'))
    for _ in range(N):
        read_buf = spi.exchange(p_mu.bit_repr().to_bytes(4,byteorder='big'), duplex=True)
        p_x = from_bits(int.from_bytes(read_buf[0:2],byteorder='big'),16,1)
        p_y = from_bits(int.from_bytes(read_buf[2:4],byteorder='big'),16,1)
        print("x = ",p_x.eval(),", y = ", p_y.eval())
        f_out.write(f"{p_x.eval()}, {p_y.eval()}\n")
        # spi.write(p_mu.bit_repr().to_bytes(2,byteorder='big'),True,False)
        # recv_byte = spi.read(4,start=False,stop=True)
        # print(recv_byte)
        # p_x = from_bits(int.from_bytes(recv_byte,byteorder='big'),N,ES)
        # print("x = ",p_x.eval())
f_out.close()