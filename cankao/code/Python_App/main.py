import pdb
import sys
import os
import socket
import numpy as np
from scipy.fft import fft, fftfreq
from PyQt5.QtWidgets import QApplication, QWidget,QHBoxLayout, QVBoxLayout , QLabel, QPushButton, QCheckBox, QSlider, QTableWidget, QComboBox,QTableWidgetItem, QFileDialog,QProgressBar
from PyQt5.QtCore import QThread, pyqtSignal, Qt
import matplotlib.pyplot as plt
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
import mysql.connector
from datetime import datetime
from matplotlib.figure import Figure
from PyQt5.QtCore import QTimer
from mw11 import Ui_Form
import pdb
# from scipy import make_interp_spline
# 数据处理和分析的函数保持不变（twos_complement, calculate_snr, calculate_thd）

# UDP数据处理线程
class DataThread(QThread):
    data_signal = pyqtSignal(np.ndarray, np.ndarray, np.ndarray, np.ndarray, float, float,float,float, np.ndarray,float,float)  # 添加THD和SNR的信号
    paused_signal = pyqtSignal(bool)

    def __init__(self):
        super().__init__()
        self.is_paused = False  # 新增标志


    def run(self):
        global is_running

        while True:
            if not is_running:
                self.paused_signal.emit(True)
                self.msleep(100)  # 将线程暂停一小段时间，减小 CPU 使用率
                continue
            try:
                if not self.is_paused:
                    print("接收到数据！")
                    data, _ = udp_socket.recvfrom(8192)

                    hex_data = data.hex()

                    integers = []
                    for i in range(0, len(data), 4):  # 每4个字节代表一个32位整数
                        # 假设数据是小端字节序
                        integer = int.from_bytes(data[i:i + 4], byteorder='little', signed=True)
                        integers.append(integer)
                    audio_data = np.array(integers)
                    audio_datal = audio_data[::2]  # 偶数索引
                    audio_datar = audio_data[1::2]  # 奇数索引
                      # 定义电压范围和位数
                    voltage_range = 2.1 # 电压范围（单位：伏特）
                    bit_depth = 32 # 位深度

                     # 将整数数据转换为电压
                    audio_datal = audio_datal / (2 ** (bit_depth - 1)) * voltage_range
                    audio_datar = audio_datar / (2 ** (bit_depth - 1)) * voltage_range
                    # 计算THD和SNR
                    fs=95980



                    fft_R = fft(audio_datar,n=8192)
                    fft_L = fft(audio_datal,n=8192)
                    freq = fftfreq(8192, 1.0 / 97080)  # 修改采样率为1kHz
                    snr_l = calculate_snr(fft_L,fs)
                    snr_r = calculate_snr(fft_R,fs)
                    thd_l,freq_r = calculate_thd(fft_L,97080)
                    thd_r,freq_l = calculate_thd(fft_R,97080)
                    # 通过信号发射数据
                    self.data_signal.emit(audio_datar, audio_datal, abs(fft_R), abs(fft_L), thd_r,thd_l,snr_r, snr_l, freq, freq_r,freq_l)

            except Exception as e:
                print(f"错误: {e}")

    def pause(self):
        self.is_paused = True
        self.paused_signal.emit(True)

    def resume(self):
        self.is_paused = False
        self.paused_signal.emit(False)

# 函数用于将数据存储到MySQL数据库
def store_data_in_database(time, thd_l, thd_r, snr_r, snr_l, time_picture, fre_picture):
    try:
        # Replace NaN values with a default value (e.g., 0)
        thd_l = 0 if np.isnan(thd_l) else thd_l
        thd_r = 0 if np.isnan(thd_r) else thd_r
        snr_r = 0 if np.isnan(snr_r) else snr_r
        snr_l = 0 if np.isnan(snr_l) else snr_l

        with db_connection.cursor() as cursor:
            sql = '''
                INSERT INTO omg (time, thd_l, thd_r, snr_r, snr_l, time_picture, fre_picture)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            '''
            values = (time, thd_l, thd_r, snr_r, snr_l, time_picture, fre_picture)
            cursor.execute(sql, values)
            db_connection.commit()
    except Exception as e:
        print(f"在数据库中存储数据时出错: {e}")


# 函数用于从数据库中获取数据
def get_data_from_database():
    try:
        with db_connection.cursor() as cursor:
            sql = "SELECT time, thd_l, thd_r, snr_r, snr_l, time_picture, fre_picture FROM omg"
            cursor.execute(sql)
            result = cursor.fetchall()
        return result
    except Exception as e:
        print(f"从数据库中获取数据时出错: {e}")
        return []


# 主窗口类
class AudioAnalyzer(QWidget , Ui_Form):
    def __init__(self):
        super().__init__()
        self.initUI()

    def initUI(self):
        self.setupUi(self)
        self.add_figure(self)
        self.retranslateUi(self)
        self.setWindowTitle("音频数据分析")
        self.horzion_scale = 200
        self.freq_r =0
        self.freq_l =0
        
        #layout = QVBoxLayout()
        plt.ion()


        self.data_thread = DataThread()
        self.data_thread.data_signal.connect(self.update_plots)  # 连接信号
        self.data_thread.start()
        palette = self.palette()
        palette.setColor(self.backgroundRole(), Qt.white)
        self.setPalette(palette)

        # 设置无边框圆角
        #self.setWindowFlags(Qt.FramelessWindowHint)
        #self.setAttribute(Qt.white)


        # 创建时域图和频域图
        # self.time_figure = plt.Figure(figsize=(5, 4), dpi=100)
        # self.freq_figure = plt.Figure(figsize=(5, 4), dpi=100)
        # self.time_canvas = FigureCanvas(self.time_figure)
        # self.freq_canvas = FigureCanvas(self.freq_figure)
        # self.ax_time = self.time_figure.add_subplot(111)  # 创建时域子图
        # self.ax_freq = self.freq_figure.add_subplot(111)  # 创建频域子图

        self.show_database_window = DatabaseWindow(self)
        self.show_database_window.set_previous_ui(self)
        self.show_database_window.hide()

        # self.r_check = QCheckBox("L_PLOT")
        # self.l_check = QCheckBox("R_PLOT")
        self.r_check.clicked.connect(self.update_plots_ui)
        self.l_check.clicked.connect(self.update_plots_ui)
        # self.slider = QSlider()
        self.slider.setMinimum(10)  # 设置最小点数
        self.slider.setMaximum(1024)  # 设置最大点数
        self.slider.setValue(self.horzion_scale)  # 设置初始点数
        self.slider.valueChanged.connect(self.update_horizon_scale)  # 连接槽函数
        # self.save_button = QPushButton("保存数据")
        self.save_button.clicked.connect(self.save)  # 连接保存槽函数

        # self.channel_operation_label = QLabel("双通道操作:")
        # self.channel_operation_combo = QComboBox()
        # self.channel_operation_combo.addItem("加法运算")
        # self.channel_operation_combo.addItem("减法运算")
        # self.channel_operation_combo.addItem("不做运算")
        # layout.addWidget(self.channel_operation_label)
        # layout.addWidget(self.channel_operation_combo)

        # self.pause_button = QPushButton("暂停")
        #
        # layout.addWidget(self.pause_button)
        self.pause_button.clicked.connect(self.toggle_pause)

        self.channel_operation = 0
        # 添加按钮来触发运算
        # self.perform_operation_button = QPushButton("执行操作")
        self.perform_operation_button.clicked.connect(self.update_channel_operation)
        # layout.addWidget(self.perform_operation_button)

        # 添加用于指示线程状态和收到包情况的 QLabel
        # self.thread_status_label = QLabel("线程状态: 否")
        # self.packet_received_label = QLabel("收到包: 无")

        # 添加到布局
        # layout.addWidget(self.thread_status_label)
        # layout.addWidget(self.packet_received_label)

        self.blink_timer = QTimer()
        self.blink_timer.timeout.connect(self.reset_packet_received_label)

        # 添加“数据库”按钮
        # self.db_button = QPushButton("数据库")
        self.db_button.clicked.connect(self.show_database_data)
        self.data_thread.paused_signal.connect(self.handle_pause_signal)

        self.time_data_r = []
        self.time_data_l = []
        self.freq_data_r = []
        self.freq_data_l = []
        self.freq= []


        # 创建THD和SNR标签
        # self.thd_label = QLabel("THD: N/A")
        # self.snr_label = QLabel("SNR: N/A")
        self.thd_l = 0
        self.thd_r = 0
        self.snr_l = 0
        self.snr_r = 0
        self.time = ""

        # # 添加组件到布局
        # layout.addWidget(self.time_canvas)
        # layout.addWidget(self.freq_canvas)
        # layout.addWidget(self.thd_label)
        # layout.addWidget(self.snr_label)
        # layout.addWidget(self.l_check)
        # layout.addWidget(self.r_check)
        # layout.addWidget(self.slider)
        # layout.addWidget(self.save_button)
        # layout.addWidget(self.db_button)  # 将“数据库”按钮添加到布局

        #self.setLayout(layout)
        #self.progressbar = QProgressBar()


    def reset_packet_received_label(self):
        self.packet_received_label.clear()
        self.blink_timer.stop()

    def update_horizon_scale(self):
        self.horzion_scale = self.slider.value()  # 更新点数
        self.update_plots_ui()

    # self.update_plots(self,data_thread.data_signal)
    def update_channel_operation(self):
        operation_index = self.channel_operation_combo.currentIndex()
        self.channel_operation = operation_index
        self.update_plots_ui()
        '''0 = 加法 1 =减法 2 =不改变'''

    def handle_pause_signal(self, is_paused):
        if is_paused:
            self.thread_status_label.setText("运行状态:"+"<font color = #ff0000>"+"暂停")
        else:
            self.thread_status_label.setText("运行状态：是")


    




    def update_plots(self, time_data1, time_data2, freq_data1, freq_data2, thd_r,thd_l, snr_r,snr_l, freq,freq_l,freq_r):
        # 把数据送入窗口的缓冲区
        self.time_data_r = time_data1
        self.time_data_l =time_data2
        self.freq_data_r =freq_data1
        self.freq_data_l =freq_data2
        self.freq_r =freq_r
        self.freq_l =freq_l
        self.freq =freq

        self.ax_time.clear()


        if self.channel_operation == 2:
            pass
        elif self.channel_operation == 0:
            sum_time_data = time_data1 + time_data2
            #self.ax_time.legend(['Left', 'right', 'math'])
            #x=np.linspace(0,self.horzion_scale-1)
            self.ax_time.plot(sum_time_data[:self.horzion_scale],linewidth=2.0,label="math")
        elif self.channel_operation == 1:
            sub_time_data = time_data1 - time_data2
            #self.ax_time.legend(['Left', 'right', 'math'])
            self.ax_time.plot(sub_time_data[:self.horzion_scale],linewidth=2.0,label="math")

        if self.r_check.isChecked():
            #self.ax_time.legend(['Left', 'right', 'math'])
            self.ax_time.plot(time_data1[:self.horzion_scale],linewidth=2.0,label="right")
            #max_r = np.argmax(time_data1[:self.horzion_scale])
            '''
            self.ax_time.annotate(f"max: {max_r:.2f} Hz", xy=(max_r, max(freq_data1)),
                                  xytext=(max_r, max(freq_data1) * 1.1),
                                  arrowprops=dict(facecolor='black', arrowstyle='->'), ha='center')
            '''
        if self.l_check.isChecked():
            #self.ax_time.legend(['Left', 'right', 'math'])
            self.ax_time.plot(time_data2[:self.horzion_scale],linewidth=2.0,label="left")
        self.ax_time.set_title("TIME")
        self.ax_time.text(0.5, 0.9, f"freq_r: {freq_r:.2f} Hz", transform=self.ax_time.transAxes, ha='center')
        self.ax_time.text(0.5, 0.85, f"freq_l: {freq_l:.2f} Hz", transform=self.ax_time.transAxes, ha='center')
        self.ax_time.grid(True)  # 显示网格
        self.ax_time.legend(bbox_to_anchor=(0., 1.02, 1., .102), loc='lower left',
                              ncols=2, mode="expand", borderaxespad=0.)
        
        self.time_canvas.draw()



        # 更新频域图
        self.ax_freq.clear()
        if self.r_check.isChecked():
            self.ax_freq.plot(freq, freq_data1)
            self.ax_freq.annotate(f"freq_r: {freq_r:.2f} Hz", xy=(freq_r, max(freq_data1)), xytext=(freq_r, max(freq_data1) * 1.1),
                                  arrowprops=dict(facecolor='black', arrowstyle='->'), ha='center')
        if self.l_check.isChecked():
            self.ax_freq.plot(freq, freq_data2)
            self.ax_freq.annotate(f"freq_l: {freq_l:.2f} Hz", xy=(freq_l, max(freq_data2)), xytext=(freq_l, max(freq_data2) * 1.1),
                                  arrowprops=dict(facecolor='black', arrowstyle='->'), ha='center')
        self.ax_freq.set_title("FRE")
        self.ax_freq.grid(True)  # 显示网格
        self.freq_canvas.draw()
        self.thread_status_label.setText("线程状态:"+"<font color = #00ff00>"+ "运行中")
        #self.thread_status_label.setFont(Qt.green)

        # 更新收到包情况标签，实现闪烁效果
        self.packet_received_label.setText("收到包: 是")
        self.blink_timer.start(500)  # 500 毫秒后重置


        # 更新THD和SNR标签
        self.thd_label.setText(f"THD: L:{thd_l:.2f}% R:{thd_l:.2f}% FREQ_L: {freq_l: .2f} hz")
        self.snr_label.setText(f"SNR: L:{snr_l:.2f}dB R:{snr_r:.2f}dB FREQ_R:{freq_r:.2f} hz")
        self.thd_l = thd_l
        self.thd_r = thd_r
        self.snr_l = snr_l
        self.snr_r = snr_r

    def update_plots_ui(self):
        # 把数据送入窗口的缓冲区
        time_data1 = self.time_data_r
        time_data2 = self.time_data_l
        freq_data1 = self.freq_data_r
        freq_data2 = self.freq_data_l
        freq = self.freq
        freq_r = self.freq_r
        freq_l = self.freq_l

        self.ax_time.clear()

        if self.channel_operation == 2:
            pass
        elif self.channel_operation == 0:
            sum_time_data = np.add(time_data1, time_data2)
            self.ax_time.plot(sum_time_data[:self.horzion_scale],linewidth=2.0)
        elif self.channel_operation == 1:
            sub_time_data = np.subtract(time_data1, time_data2)
            self.ax_time.plot(sub_time_data[:self.horzion_scale],linewidth=2.0)

        if self.r_check.isChecked():
            self.ax_time.plot(time_data1[:self.horzion_scale],linewidth=2.0)
            max_r =max(time_data1)
            max_r_x = np.argmax(time_data1)
            self.ax_time.annotate(f"Rmax_voltage {max_r:.2f}v",xy=(max_r_x,max_r),xytext=(max_r_x,max_r*1.1),
                                    arrowprops=dict(facecolor='blue',arrowstyle='->'),ha='center')
        if self.l_check.isChecked():
            self.ax_time.plot(time_data2[:self.horzion_scale],linewidth=2.0)
            max_l = max(time_data2)
            max_l_x = np.argmax(time_data2)
            self.ax_time.annotate(f"Lmax_voltage {max_l:.2f}v", xy=(max_l_x, max_l), xytext=(max_l_x, max_l * 1.1),
                                  arrowprops = dict(facecolor='blue', arrowstyle='->'), ha = 'center')
        self.ax_time.set_title("TIME")
        self.ax_time.text(0.5, 0.9, f"freq_r: {freq_r:.2f} Hz", transform=self.ax_time.transAxes, ha='center')
        self.ax_time.text(0.5, 0.85, f"freq_l: {freq_l:.2f} Hz", transform=self.ax_time.transAxes, ha='center')
        self.ax_time.grid(True)  # 显示网格
        self.time_canvas.draw()

        # 更新频域图
        self.ax_freq.clear()
        if self.r_check.isChecked():
            self.ax_freq.plot(freq, freq_data1)
            self.ax_freq.annotate(f"freq_r: {freq_r:.2f} Hz", xy=(freq_r, max(freq_data1)), xytext=(freq_r, max(freq_data1) * 1.1),
                                  arrowprops=dict(facecolor='black', arrowstyle='->'), ha='center')
        if self.l_check.isChecked():
            self.ax_freq.plot(freq, freq_data2)
            self.ax_freq.annotate(f"freq_l: {freq_l:.2f} Hz", xy=(freq_l, max(freq_data2)), xytext=(freq_l, max(freq_data2) * 1.1),
                                  arrowprops=dict(facecolor='black', arrowstyle='->'), ha='center')
        self.ax_freq.set_title("FRE")
        self.ax_freq.grid(True)  # 显示网格
        self.freq_canvas.draw()


    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Q:
            # Save data to the database when 'Q' key is pressed
            self.save()

    def save(self):
        # 按钮点击时执行保存数据到数据库的操作
        self.time = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")  # 修改日期时间格式
        time_picture_path = f'E:/UDP/plot/{self.time}_time_plot.png'
        fre_picture_path = f'E:/UDP/plot/{self.time}_freq_plot.png'

        store_data_in_database(self.time, self.thd_l, self.thd_r, self.snr_r, self.snr_l, time_picture_path,
                               fre_picture_path)

        # 检查并创建plot文件夹
        if not os.path.exists('./plot'):
            os.makedirs('./plot')

        # 保存图形到./plot文件夹
        self.time_figure.savefig(time_picture_path)
        self.freq_figure.savefig(fre_picture_path)

    def show_database_data(self):
        # 创建数据库窗口
        global is_running
        self.show_database_window.refresh_data()
        is_running = False
        self.hide()
        self.show_database_window.show()

    def toggle_pause(self):
        global is_running
        is_running = not is_running
        if not is_running:
            self.data_thread.pause()
            #self.thread_status_label.setText("运行状态：暂停")
        else:
            self.data_thread.resume()
            #self.thread_status_label.setText("运行状态：是")


    # def start_data_thread(self):
    #     if not self.data_thread.isRunning():
    #         self.data_thread.start()
    #
    # def stop_data_thread(self):
    #     if self.data_thread.isRunning():
    #         self.data_thread.quit()
    #         self.data_thread.wait()


# 添加THD和SNR的计算函数
def calculate_thd(spectrum, fs):
    # 计算FFT得到频谱数据


    # 找到基波的频率索引和幅值
    fundamental_index = np.argmax(np.abs(spectrum[:len(spectrum) // 2]))
    fundamental_frequency = fundamental_index * fs / len(spectrum)
    fundamental_amplitude = np.abs(spectrum[fundamental_index])

    # 找到基波的三次谐波频率索引和幅值
    second_harmonic_index = fundamental_index * 2
    second_harmonic_frequency = second_harmonic_index * fs / len(spectrum)
    second_harmonic_amplitude = np.abs(spectrum[second_harmonic_index])
    # 找到基波的三次谐波频率索引和幅值
    third_harmonic_index = fundamental_index * 3
    third_harmonic_frequency = third_harmonic_index * fs / len(spectrum)
    third_harmonic_amplitude = np.abs(spectrum[third_harmonic_index])

    # 计算THD
    thd = 100*(np.sqrt(third_harmonic_amplitude**2 +second_harmonic_amplitude**2)/fundamental_amplitude)

    return thd, fundamental_frequency


def calculate_snr(audio_data, fs):
    # n = len(audio_data)
    # fundamental_index = np.argmax(np.abs(audio_data[:n // 2]))  # 寻找正频率部分中最大幅值的位置
    # fundamental = np.abs(audio_data[fundamental_index])
    #
    # # 除去基频信号之外的其他频率成分
    # noise_spectrum = np.delete(np.abs(audio_data[:n // 2]), fundamental_index)
    #
    # # 计算噪声的均方根值
    # noise = (noise_spectrum ** 2)
    #
    # snr = 10 * np.log10(fundamental**2 / noise**2)

    # signal = max(np.abs(audio_data))**2
    # total = sum(np.abs(audio_data)**2)
    # noise = total - 2* signal
    # snr =  10 * np.log10(2*signal / noise)

    P_spectrum = np.abs(audio_data)**2
    P_Signal = (max(P_spectrum)**2)
    P_noise =9
    snr =10*np.log10(sum(P_spectrum)/P_noise)


    #pdb.set_trace()
    return snr


# 数据库窗口类
class DatabaseWindow(QWidget):
    def __init__(self, main_window):
        super().__init__()
        self.main_window = main_window
        self.initUI()

    def initUI(self):
        self.setWindowTitle("数据库内容")
        self.setFixedSize(1500, 800)     # Set fixed size to 1200x800

        layout = QVBoxLayout()     # Use QVBoxLayout for vertical layout

         # Create a widget to hold the table and the figures
        widget = QWidget(self)
        widget.setLayout(layout)

         # Create a horizontal layout for the figures
        figures_layout = QHBoxLayout()

         # Create the table widget
        self.table_widget = QTableWidget(self)
        self.table_widget.setColumnHidden(5, True)     # Hide Time Picture column
        self.table_widget.setColumnHidden(6, True)     # Hide Frequency Picture column
        layout.addWidget(self.table_widget)

         # Create the figure canvases
        self.time_figure = plt.Figure(figsize=(5, 4), dpi=100)
        self.freq_figure = plt.Figure(figsize=(5, 4), dpi=100)
        self.time_canvas = FigureCanvas(self.time_figure)
        self.freq_canvas = FigureCanvas(self.freq_figure)
        self.ax_time = self.time_figure.add_subplot(111)  # 创建时域子图
        self.ax_freq = self.freq_figure.add_subplot(111)  # 创建频域子图

         # Add the figure canvases to the figures layout
        figures_layout.addWidget(self.time_canvas)
        figures_layout.addWidget(self.freq_canvas)

         # Add the figures layout to the main layout
        layout.addLayout(figures_layout)

         # Add the return button
        self.return_button = QPushButton("返回")
        self.return_button.clicked.connect(self.return_ui)
        layout.addWidget(self.return_button)
        
        button_style = '''
            QPushButton {
                background-color: #093f73;
                color: white;
                border: none;
                padding: 10px 20px;
                text-align: center;
                text-decoration: none;
                display: inline-block;
                font-size: 16px;
                margin: 4px 2px;
                cursor: pointer;
                border-radius: 8px;
            }
            QPushButton:hover {
                background-color: #45a049;
            }
            QPushButton:pressed {
                background-color: #3e8e41;
            }
        '''
        self.return_button.setStyleSheet(button_style)
        
        
        
        
        
        
        

        self.table_widget.itemSelectionChanged.connect(self.view_plot)

        self.setLayout(layout)

    def refresh_data(self):
        # 获取数据库数据并填充表格
        data = get_data_from_database()
        self.fill_table(data)

    def fill_table(self, data):
        # 设置表格列数和行数
        self.table_widget.setColumnCount(7)
        self.table_widget.setRowCount(len(data))
        # 设置表头
        headers = ["Time", "THD_L", "THD_R", "SNR_R", "SNR_L", "Time Picture", "Frequency Picture"]
        self.table_widget.setHorizontalHeaderLabels(headers)

        # 填充表格数据
        for row, row_data in enumerate(data):
            for col, value in enumerate(row_data):
                item = QTableWidgetItem(str(value))
                self.table_widget.setItem(row, col, item)
        self.table_widget.setColumnHidden(5, True)  # 隐藏 Time Picture 列
        self.table_widget.setColumnHidden(6, True)  # 隐藏 Frequency Picture 列

    def view_plot(self):
        # 查看时域图按钮点击事件
        current_row = self.table_widget.currentRow()
        if current_row >= 0:
            time_picture_path = self.table_widget.item(current_row, 5).text()
            freq_picture_path = self.table_widget.item(current_row,6).text()
            self.show_plot_image(time_picture_path,freq_picture_path)

    # def view_freq_plot(self):
    #     # 查看频域图按钮点击事件
    #     current_row = self.table_widget.currentRow()
    #     if current_row >= 0:
    #         freq_picture_path = self.table_widget.item(current_row, 6).text()
    #         self.show_plot_image(freq_picture_path, "频域图")

    def show_plot_image(self, t_image_path,f_image_path):
        # 显示图像
        title_t = os.path.basename(t_image_path)  # 获取文件名（不包括路径和文件扩展名）
        title_t = os.path.splitext(title_t)[0]  # 去除文件扩展名
        t_image = plt.imread(t_image_path)
        self.ax_time.imshow(t_image)
        self.ax_time.set_title(title_t)
        self.time_canvas.draw()

        title_f = os.path.basename(f_image_path)  # 获取文件名（不包括路径和文件扩展名）
        title_f = os.path.splitext(title_f)[0]  # 去除文件扩展名

        f_image = plt.imread(f_image_path)
        self.ax_freq.set_title(title_f)
        self.ax_freq.imshow(f_image)
        self.freq_canvas.draw()
        #self.ax_time.show()
        #plt.title(title)
        #plt.show()

    def return_ui(self):
        try:
            global is_running
            self.hide()
            self.previous_ui.show()
            is_running =True
        except Exception as e:
            print(f"错误: {e}")

    def set_previous_ui(self, previous_ui):
        self.previous_ui = previous_ui

if __name__ == "__main__":
    # 设置UDP套接字
    udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    host = '192.168.0.3'  # 替换为您的IP地址
    port = 8080  # 替换为您的端口
    udp_socket.bind((host, port))

    # 连接到MySQL数据库
    db_connection = mysql.connector.connect(
        host="localhost",
        user="root",
        password="123456",
        database="udpdata",
        port="3306"
    )

    # 创建数据表（如果不存在）
    with db_connection.cursor() as cursor:
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS omg (
                id INT AUTO_INCREMENT PRIMARY KEY,
                time DATETIME,
                thd_r FLOAT,
                thd_l FLOAT,
                snr_r FLOAT,
                snr_l FLOAT,
                time_picture VARCHAR(255),
                fre_picture VARCHAR(255)
            )
        ''')
        db_connection.commit()

    print(f"UDP服务器正在监听 {host}:{port}")
    global is_running
    is_running = True
    app = QApplication(sys.argv)
    analyzer = AudioAnalyzer()

    analyzer.show()


    # 运行应用
    sys.exit(app.exec_())

    # 程序结束时关闭套接字和线程
    is_running = False
    udp_socket.close()
    analyser.data_thread.quit()
    analyser.data_thread.wait()
