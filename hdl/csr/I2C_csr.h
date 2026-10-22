#ifndef I2C_REGISTERS_H
#define I2C_REGISTERS_H

#include <stdint.h>

// Module      : I2C
// Description : CSR for I2C
// Width       : 8

//==================================
// Register    : data
// Description : Write : byte to transmit (master write or slave read), Read : byte received (master read or slave write)
// Address     : 0x0
//==================================
#define I2C_DATA 0x0

// Field       : data.value
// Description : Data TX or Data RX
// Range       : [7:0]
#define I2C_DATA_VALUE      0
#define I2C_DATA_VALUE_MASK 255

//==================================
// Register    : cmd
// Description : Master Command FIFO. Each command is executed in this order : START (if start), byte (if op), STOP (if stop)
// Address     : 0x1
//==================================
#define I2C_CMD 0x1

// Field       : cmd.start
// Description : Generate a START condition (a repeated START if the master already owns the bus) before the byte. A START is always generated if the master does not own the bus and op is not NONE
// Range       : [0]
#define I2C_CMD_START      0
#define I2C_CMD_START_MASK 1

// Enum        : cmd.start.DISABLE
// Description : no START
#define I2C_CMD_START_DISABLE     0
#define I2C_CMD_START_DISABLE_RAW (0<<0)

// Enum        : cmd.start.ENABLE
// Description : START or repeated START before the byte
#define I2C_CMD_START_ENABLE     1
#define I2C_CMD_START_ENABLE_RAW (1<<0)

// Field       : cmd.stop
// Description : Generate a STOP condition after the byte (ignored if the master does not own the bus)
// Range       : [1]
#define I2C_CMD_STOP      1
#define I2C_CMD_STOP_MASK 1

// Enum        : cmd.stop.DISABLE
// Description : no STOP, the master keeps the bus
#define I2C_CMD_STOP_DISABLE     0
#define I2C_CMD_STOP_DISABLE_RAW (0<<1)

// Enum        : cmd.stop.ENABLE
// Description : STOP after the byte, the bus is released
#define I2C_CMD_STOP_ENABLE     1
#define I2C_CMD_STOP_ENABLE_RAW (1<<1)

// Field       : cmd.op
// Description : Byte operation
// Range       : [3:2]
#define I2C_CMD_OP      2
#define I2C_CMD_OP_MASK 3

// Enum        : cmd.op.NONE
// Description : no byte (START and/or STOP only)
#define I2C_CMD_OP_NONE     0
#define I2C_CMD_OP_NONE_RAW (0<<2)

// Enum        : cmd.op.WRITE
// Description : write a byte popped from the TX FIFO, the acknowledge of the slave updates status.nack
#define I2C_CMD_OP_WRITE     1
#define I2C_CMD_OP_WRITE_RAW (1<<2)

// Enum        : cmd.op.READ_ACK
// Description : read a byte pushed into the RX FIFO, answer ACK (more bytes to read)
#define I2C_CMD_OP_READ_ACK     2
#define I2C_CMD_OP_READ_ACK_RAW (2<<2)

// Enum        : cmd.op.READ_NACK
// Description : read a byte pushed into the RX FIFO, answer NACK (last byte to read)
#define I2C_CMD_OP_READ_NACK     3
#define I2C_CMD_OP_READ_NACK_RAW (3<<2)

//==================================
// Register    : cfg
// Description : I2C Configuration Register
// Address     : 0x2
//==================================
#define I2C_CFG 0x2

// Field       : cfg.enable
// Description : 0 : I2C is disabled (held in reset, SCL and SDA released), 1 : I2C is enabled
// Range       : [0]
#define I2C_CFG_ENABLE      0
#define I2C_CFG_ENABLE_MASK 1

// Field       : cfg.slave_addr
// Description : 7-bit address of the slave. 0 : slave disabled (0 is the general call address)
// Range       : [7:1]
#define I2C_CFG_SLAVE_ADDR      1
#define I2C_CFG_SLAVE_ADDR_MASK 127

//==================================
// Register    : prescaler
// Description : I2C Clock Prescaler. SCL Frequency is CLK / (4*(prescaler+1)). In slave mode, the data setup time after a clock stretching is (prescaler+1) CLK cycles
// Address     : 0x3
//==================================
#define I2C_PRESCALER 0x3

// Field       : prescaler.ratio
// Description : Number of CLK cycles minus one of a quarter of SCL period
// Range       : [7:0]
#define I2C_PRESCALER_RATIO      0
#define I2C_PRESCALER_RATIO_MASK 255

//==================================
// Register    : status
// Description : I2C Status Register
// Address     : 0x4
//==================================
#define I2C_STATUS 0x4

// Field       : status.busy
// Description : Master : 0 : no command in progress or pending, 1 : command in progress or pending
// Range       : [0]
#define I2C_STATUS_BUSY      0
#define I2C_STATUS_BUSY_MASK 1

// Field       : status.nack
// Description : Master : 1 : a NACK was received on a written byte since the last START generated from a released bus
// Range       : [1]
#define I2C_STATUS_NACK      1
#define I2C_STATUS_NACK_MASK 1

// Field       : status.bus_busy
// Description : 0 : bus free, 1 : START detected and no STOP since
// Range       : [2]
#define I2C_STATUS_BUS_BUSY      2
#define I2C_STATUS_BUS_BUSY_MASK 1

// Field       : status.slave_addressed
// Description : Slave : 1 : the slave address was acknowledged, until the next STOP or START
// Range       : [3]
#define I2C_STATUS_SLAVE_ADDRESSED      3
#define I2C_STATUS_SLAVE_ADDRESSED_MASK 1

// Field       : status.slave_read
// Description : Slave : direction of the last acknowledged address. 0 : the master writes, 1 : the master reads
// Range       : [4]
#define I2C_STATUS_SLAVE_READ      4
#define I2C_STATUS_SLAVE_READ_MASK 1

// Field       : status.rx_empty
// Description : 0 : at least one byte can be read in data, 1 : RX FIFO empty (a read of data waits for a byte)
// Range       : [5]
#define I2C_STATUS_RX_EMPTY      5
#define I2C_STATUS_RX_EMPTY_MASK 1

//----------------------------------
// Structure I2C_t
//----------------------------------
typedef struct {
  uint8_t data; // 0x0
  uint8_t cmd; // 0x1
  uint8_t cfg; // 0x2
  uint8_t prescaler; // 0x3
  uint8_t status; // 0x4
} I2C_t;

#endif // I2C_REGISTERS_H
