# tcp-proxy
A tcp-tunnel proxy with monitor functionalities. The project is created as a tool to monitor the data traffic between main machine with peripherals (MCU boards) connected via UART.

For example, when MCU board is connected to your computer as `/dev/ttyUSB0`, the following command allows my program to read/write the char device likes a TCP connection:

```bash
socat -d -d tcp-l:9000,reuseaddr,fork file:/dev/ttyUSB1,b38400,nonblock,raw,echo=0
```

Then, run TCP-Proxy with following command in another terminal:

```bash
node ./app.js -r 127.0.0.1:9000 -l 8000 -m 8010
```

Now, you can use `telnet` utility to transmit data with `ttyUSB0` by connecting to `localhost:8000`, and monitor the data packet (in human readable format) by connecting to `localhost:8010`.


### Examples to Launch

Connect to localhost:10034, and listen to default ports to serve:

- `8000`, for data transmission
- `8010`, for data monitoring (line protocol is simply parsed)

```bash
./app.ls -r 10034 -p
```

