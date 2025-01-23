from PyQt6.QtGui import *
from PyQt6.QtWidgets import *
from PyQt6.QtCore import *

from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.backends.backend_qt5agg import NavigationToolbar2QT as NavigationToolbar
from matplotlib.figure import Figure
import matplotlib

from pyftdi.spi import SpiController
from pyftdi.usbtools import UsbToolsError

from posit import from_bits, from_double

matplotlib.use('QtAgg')

class SpiSignals(QObject):
    new_data = pyqtSignal(object)

class SpiWorker(QRunnable):
    '''
    SPI interface thread
    '''
    def __init__(self,spi,mu,n):
        super(SpiWorker,self).__init__()
        self.signals = SpiSignals()
        self.spi = spi
        self.mu = mu # Van der Pol parameter
        self.n = n # number of points to calculate

        # Posit (16,1)
        self.N = 16
        self.ES = 1
        
        self.p_mu = from_double(x=self.mu, size=self.N, es=self.ES)
        print(self.mu)

    @pyqtSlot()
    def run(self):
        x = []
        y = []
        for _ in range(self.n):
            read_buf = self.spi.exchange(self.p_mu.bit_repr().to_bytes(4,byteorder='big'), duplex=True)
            p_x = from_bits(int.from_bytes(read_buf[0:2],byteorder='big'),self.N,self.ES)
            p_y = from_bits(int.from_bytes(read_buf[2:4],byteorder='big'),self.N,self.ES)
            x.append(p_x.eval())
            y.append(p_y.eval())
            # print(data)
        print([x,y])
        self.signals.new_data.emit([x,y])
            # time.sleep(0.03)


class MplCanvas(FigureCanvas):

    def __init__(self, parent=None, width=5, height=4, dpi=100):
        fig = Figure(figsize=(width, height), dpi=dpi)
        self.axes = fig.add_subplot(111)
        self.axes.set_ylim([-3,3])
        self.axes.set_xlim([-3,3])
        super(MplCanvas, self).__init__(fig)


class MainWindow(QMainWindow):

    def __init__(self, *args, **kwargs):
        super(MainWindow, self).__init__(*args, **kwargs)
        self.setWindowTitle("DDA Van Der Pol")
        self.canvas = MplCanvas(self,width=5, height=4, dpi=100)

        # Create toolbar, passing canvas as first parament, parent (self, the MainWindow) as second.
        self.toolbar = NavigationToolbar(self.canvas, self)

        layout = QVBoxLayout()

        b = QPushButton("Run")
        b.pressed.connect(self.run)

        s = QSlider(Qt.Orientation.Horizontal)
        s.setMinimum(0)
        s.setMaximum(100)
        s.setSingleStep(1)
        s.valueChanged.connect(self.parameter_changed)

        self.muLabel = QLabel()
        layout.addWidget(self.toolbar)
        layout.addWidget(self.canvas)
        layout.addWidget(self.muLabel)
        layout.addWidget(s)
        layout.addWidget(b)

        w = QWidget()
        w.setLayout(layout)

        self.setCentralWidget(w)

        self.xdata = []
        self.ydata = []
        self.mu = 0.1
        self.n = 10000
        # self.xdata = [random.randint(0, 10) for i in range(n_data)]
        # self.ydata = [random.randint(0, 10) for i in range(n_data)]
        # self.update_plot()

        self.spi_ctrl = SpiController()
        try:
            self.spi_ctrl.configure('ftdi://ftdi:232h:1/1')
            self.spi_ctrl.flush()
            self.spi = self.spi_ctrl.get_port(cs=0, freq=1E6, mode=0)
        except UsbToolsError as err :
            print("Error:",err)
            exit(1)

        self.show()
        self.threadpool = QThreadPool()

    def parameter_changed(self,n):
        self.mu = (float) (n/10)
        self.muLabel.setText(f"mu: {self.mu}")
    
    def run(self):
        worker = SpiWorker(self.spi,self.mu,self.n)
        worker.signals.new_data.connect(self.update_plot)
        self.threadpool.start(worker)
    
    def update_plot(self,data):
        # Drop off the first y element, append a new one.
        # self.ydata = self.ydata[1:] + [data[0]]
        # self.xdata = self.xdata[1:] + [data[1]]
        self.xdata = data[0]
        self.ydata = data[1]
        self.canvas.axes.cla()  # Clear the canvas.
        self.canvas.axes.plot(self.xdata, self.ydata, 'k')
        self.canvas.axes.set_xlabel("X")
        self.canvas.axes.set_ylabel("Y")
        self.canvas.axes.set_title(r"DDA Van Der Pol $\mu = {}$".format(self.mu))
        # self.canvas.axes.set_aspect('equal')
        # self.canvas.axes.set_xlim([-3,3])
        # self.canvas.axes.set_ylim([-3,3])
        # Trigger the canvas to update and redraw.
        self.canvas.draw()
        
app = QApplication([])
window = MainWindow()
app.exec()