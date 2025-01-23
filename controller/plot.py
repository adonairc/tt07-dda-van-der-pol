import matplotlib.pyplot as plt
import numpy as np
import sys 
xy = np.genfromtxt(sys.argv[1],delimiter=",", dtype=float)
ax = plt.figure().add_subplot()

ax.plot(*xy.T, lw=1.5)
ax.set_xlabel("X")
ax.set_ylabel("Y")
ax.set_title("DDA Van Der Pol Oscillator")
plt.show()