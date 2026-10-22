-- Generated VHDL Package for I2C

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;

library asylum;
use     asylum.sbi_pkg.all;
--==================================
-- Module      : I2C
-- Description : CSR for I2C
-- Width       : 8
--==================================

package I2C_csr_pkg is

  ------------------------------------
  -- Global Constants
  ------------------------------------

  constant I2C_ADDR_WIDTH : natural := 2;
  constant I2C_DATA_WIDTH : natural := 8;

  --==================================
  -- Register    : data
  -- Description : Write : byte to transmit (master write or slave read), Read : byte received (master read or slave write)
  -- Address     : 0x0
  -- Width       : 8
  -- Sw Access   : rw
  -- Hw Access   : rw
  -- Hw Type     : fifo
  --==================================
  constant I2C_DATA : unsigned(I2C_ADDR_WIDTH-1 downto 0) := to_unsigned(0, I2C_ADDR_WIDTH);

  type I2C_data_sw2hw_t is record
    ready : std_logic;
    valid : std_logic;
  --==================================
  -- Field       : value
  -- Description : Data TX or Data RX
  -- Width       : 8
  --==================================
    value : std_logic_vector(8-1 downto 0);
    sw2hw_empty : std_logic;
    sw2hw_full  : std_logic;
    hw2sw_empty : std_logic;
    hw2sw_full  : std_logic;
  end record I2C_data_sw2hw_t;

  type I2C_data_hw2sw_t is record
    ready : std_logic;
    valid : std_logic;
  --==================================
  -- Field       : value
  -- Description : Data TX or Data RX
  -- Width       : 8
  --==================================
    value : std_logic_vector(8-1 downto 0);
  end record I2C_data_hw2sw_t;

  --==================================
  -- Register    : cmd
  -- Description : Master Command FIFO, write only (a read returns status). Each command is executed in this order : START (if start), byte (if op), STOP (if stop)
  -- Address     : 0x1
  -- Width       : 4
  -- Sw Access   : wo
  -- Hw Access   : ro
  -- Hw Type     : fifo
  --==================================
  constant I2C_CMD : unsigned(I2C_ADDR_WIDTH-1 downto 0) := to_unsigned(1, I2C_ADDR_WIDTH);

  type I2C_cmd_sw2hw_t is record
    valid : std_logic;
  --==================================
  -- Field       : start
  -- Description : Generate a START condition (a repeated START if the master already owns the bus) before the byte. A START is always generated if the master does not own the bus and op is not NONE
  -- Width       : 1
  --==================================
    start : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : stop
  -- Description : Generate a STOP condition after the byte (ignored if the master does not own the bus)
  -- Width       : 1
  --==================================
    stop : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : op
  -- Description : Byte operation
  -- Width       : 2
  --==================================
    op : std_logic_vector(2-1 downto 0);
    sw2hw_empty : std_logic;
    sw2hw_full  : std_logic;
  end record I2C_cmd_sw2hw_t;

  type I2C_cmd_hw2sw_t is record
    ready : std_logic;
  end record I2C_cmd_hw2sw_t;

-- Enum        : cmd.start.DISABLE
-- Description : no START
constant I2C_CMD_START_DISABLE     : std_logic_vector(1-1 downto 0) := "0";
constant I2C_CMD_START_DISABLE_RAW : std_logic_vector(4-1 downto 0) := "0000";

-- Enum        : cmd.start.ENABLE
-- Description : START or repeated START before the byte
constant I2C_CMD_START_ENABLE     : std_logic_vector(1-1 downto 0) := "1";
constant I2C_CMD_START_ENABLE_RAW : std_logic_vector(4-1 downto 0) := "0001";

-- Enum        : cmd.stop.DISABLE
-- Description : no STOP, the master keeps the bus
constant I2C_CMD_STOP_DISABLE     : std_logic_vector(1-1 downto 0) := "0";
constant I2C_CMD_STOP_DISABLE_RAW : std_logic_vector(4-1 downto 0) := "0000";

-- Enum        : cmd.stop.ENABLE
-- Description : STOP after the byte, the bus is released
constant I2C_CMD_STOP_ENABLE     : std_logic_vector(1-1 downto 0) := "1";
constant I2C_CMD_STOP_ENABLE_RAW : std_logic_vector(4-1 downto 0) := "0010";

-- Enum        : cmd.op.NONE
-- Description : no byte (START and/or STOP only)
constant I2C_CMD_OP_NONE     : std_logic_vector(2-1 downto 0) := "00";
constant I2C_CMD_OP_NONE_RAW : std_logic_vector(4-1 downto 0) := "0000";

-- Enum        : cmd.op.WRITE
-- Description : write a byte popped from the TX FIFO, the acknowledge of the slave updates status.nack
constant I2C_CMD_OP_WRITE     : std_logic_vector(2-1 downto 0) := "01";
constant I2C_CMD_OP_WRITE_RAW : std_logic_vector(4-1 downto 0) := "0100";

-- Enum        : cmd.op.READ_ACK
-- Description : read a byte pushed into the RX FIFO, answer ACK (more bytes to read)
constant I2C_CMD_OP_READ_ACK     : std_logic_vector(2-1 downto 0) := "10";
constant I2C_CMD_OP_READ_ACK_RAW : std_logic_vector(4-1 downto 0) := "1000";

-- Enum        : cmd.op.READ_NACK
-- Description : read a byte pushed into the RX FIFO, answer NACK (last byte to read)
constant I2C_CMD_OP_READ_NACK     : std_logic_vector(2-1 downto 0) := "11";
constant I2C_CMD_OP_READ_NACK_RAW : std_logic_vector(4-1 downto 0) := "1100";

  --==================================
  -- Register    : status
  -- Description : I2C Status Register, read at the address of cmd (cmd is write only), without latency
  -- Address     : 0x1
  -- Width       : 6
  -- Sw Access   : ro
  -- Hw Access   : wo
  -- Hw Type     : ext
  --==================================
  constant I2C_STATUS : unsigned(I2C_ADDR_WIDTH-1 downto 0) := to_unsigned(1, I2C_ADDR_WIDTH);

  type I2C_status_sw2hw_t is record
    re : std_logic;
  end record I2C_status_sw2hw_t;

  type I2C_status_hw2sw_t is record
    we : std_logic;
  --==================================
  -- Field       : busy
  -- Description : Master : 0 : no command in progress or pending, 1 : command in progress or pending
  -- Width       : 1
  --==================================
    busy : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : nack
  -- Description : Master : 1 : a NACK was received on a written byte since the last START generated from a released bus
  -- Width       : 1
  --==================================
    nack : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : bus_busy
  -- Description : 0 : bus free, 1 : START detected and no STOP since
  -- Width       : 1
  --==================================
    bus_busy : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : slave_addressed
  -- Description : Slave : 1 : the slave address was acknowledged, until the next STOP or START
  -- Width       : 1
  --==================================
    slave_addressed : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : slave_read
  -- Description : Slave : direction of the last acknowledged address. 0 : the master writes, 1 : the master reads
  -- Width       : 1
  --==================================
    slave_read : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : rx_empty
  -- Description : 0 : at least one byte can be read in data, 1 : RX FIFO empty (a read of data waits for a byte)
  -- Width       : 1
  --==================================
    rx_empty : std_logic_vector(1-1 downto 0);
  end record I2C_status_hw2sw_t;

  --==================================
  -- Register    : cfg
  -- Description : I2C Configuration Register
  -- Address     : 0x2
  -- Width       : 8
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : reg
  --==================================
  constant I2C_CFG : unsigned(I2C_ADDR_WIDTH-1 downto 0) := to_unsigned(2, I2C_ADDR_WIDTH);

  type I2C_cfg_sw2hw_t is record
    re : std_logic;
    we : std_logic;
  --==================================
  -- Field       : enable
  -- Description : 0 : I2C is disabled (held in reset, SCL and SDA released), 1 : I2C is enabled
  -- Width       : 1
  --==================================
    enable : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : slave_addr
  -- Description : 7-bit address of the slave. 0 : slave disabled (0 is the general call address)
  -- Width       : 7
  --==================================
    slave_addr : std_logic_vector(7-1 downto 0);
  end record I2C_cfg_sw2hw_t;

  --==================================
  -- Register    : prescaler
  -- Description : I2C Clock Prescaler. Master : SCL period is 4*(prescaler+1)+2 CLK cycles (the 2 cycles of synchronization of SCL extend the high phase). Slave : the data setup time after a clock stretching is (prescaler+1) CLK cycles
  -- Address     : 0x3
  -- Width       : 8
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : reg
  --==================================
  constant I2C_PRESCALER : unsigned(I2C_ADDR_WIDTH-1 downto 0) := to_unsigned(3, I2C_ADDR_WIDTH);

  type I2C_prescaler_sw2hw_t is record
    re : std_logic;
    we : std_logic;
  --==================================
  -- Field       : ratio
  -- Description : Number of CLK cycles minus one of a quarter of SCL period
  -- Width       : 8
  --==================================
    ratio : std_logic_vector(8-1 downto 0);
  end record I2C_prescaler_sw2hw_t;

  ------------------------------------
  -- Structure I2C_t
  ------------------------------------
  type I2C_sw2hw_t is record
    data : I2C_data_sw2hw_t;
    cmd : I2C_cmd_sw2hw_t;
    status : I2C_status_sw2hw_t;
    cfg : I2C_cfg_sw2hw_t;
    prescaler : I2C_prescaler_sw2hw_t;
  end record I2C_sw2hw_t;

  type I2C_hw2sw_t is record
    data : I2C_data_hw2sw_t;
    cmd : I2C_cmd_hw2sw_t;
    status : I2C_status_hw2sw_t;
  end record I2C_hw2sw_t;

  ------------------------------------
  -- Component
  ------------------------------------
component I2C_registers is
  generic (
    MODULE_NAME :  string := "" -- Name of the module
   ;USER_DEFINE_PRESCALER : boolean -- Parameters to enable the User define Prescaler
   ;PRESCALER_RATIO : std_logic_vector(7 downto 0) -- Default value for prescaler ratio
   ;MASTER_ENABLE : boolean -- Master implemented (command FIFO present)
   ;DEPTH_TX : natural -- Depth of FIFO TX (SW2HW)
   ;DEPTH_RX : natural -- Depth of FIFO RX (HW2SW)
   ;DEPTH_CMD : natural -- Depth of FIFO Command (SW2HW)
  );
  port (
    -- Clock and Reset
    clk_i      : in  std_logic
   ;arst_b_i   : in  std_logic
    -- Bus
   ;sbi_ini_i  : in  sbi_ini_t
   ;sbi_tgt_o  : out sbi_tgt_t
    -- CSR
   ;sw2hw_o    : out I2C_sw2hw_t
   ;hw2sw_i    : in  I2C_hw2sw_t
  );
end component I2C_registers;


end package I2C_csr_pkg;
