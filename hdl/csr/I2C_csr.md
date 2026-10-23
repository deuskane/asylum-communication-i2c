# I2C
CSR for I2C

| Address | Registers |
|---------|-----------|
|0x0|data|
|0x1|cmd, status|
|0x2|cfg|
|0x3|prescaler|

## 0x0 data
Write : byte to transmit (master write or slave read), Read : byte received (master read or slave write)

### [7:0] value
Data TX or Data RX

## 0x1 cmd
Master Command FIFO, write only (a read returns status). Each command is executed in this order : START (if start), byte (if op), STOP (if stop)

### [0:0] start
Generate a START condition (a repeated START if the master already owns the bus) before the byte. A START is always generated if the master does not own the bus and op is not NONE

### [1:1] stop
Generate a STOP condition after the byte (ignored if the master does not own the bus)

### [3:2] op
Byte operation

## 0x1 status
I2C Status Register, read at the address of cmd (cmd is write only), without latency

### [0:0] busy
Master : 0 : no command in progress or pending, 1 : command in progress or pending

### [1:1] nack
Master : 1 : a NACK was received on a written byte since the last START generated from a released bus

### [2:2] bus_busy
0 : bus free, 1 : START detected and no STOP since

### [3:3] slave_addressed
Slave : 1 : the slave address was acknowledged, until the next STOP or START

### [4:4] slave_read
Slave : direction of the last acknowledged address. 0 : the master writes, 1 : the master reads

### [5:5] rx_empty
0 : at least one byte can be read in data, 1 : RX FIFO empty (a read of data waits for a byte)

## 0x2 cfg
I2C Configuration Register

### [0:0] enable
0 : I2C is disabled (held in reset, SCL and SDA released), 1 : I2C is enabled

### [7:1] slave_addr
7-bit address of the slave. 0 : slave disabled (0 is the general call address)

## 0x3 prescaler
I2C Clock Prescaler. Master : SCL period is 4*(prescaler+1)+2 CLK cycles (the 2 cycles of synchronization of SCL extend the high phase). Slave : the data setup time after a clock stretching is (prescaler+1) CLK cycles

### [7:0] ratio
Number of CLK cycles minus one of a quarter of SCL period

