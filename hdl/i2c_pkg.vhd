-------------------------------------------------------------------------------
-- Title      : i2c_pkg
-- Project    : Asylum
-------------------------------------------------------------------------------
-- File       : i2c_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: I2C constants and components
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-22  1.0      mrosiere Created
-------------------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;
library asylum;
use     asylum.sbi_pkg.all;

package i2c_pkg is

  -----------------------------------------------------------------------------
  -- Byte operation of a master command (cmd_op_i)
  -- Same encoding as the field op of the cmd register (I2C_CMD_OP_*)
  -----------------------------------------------------------------------------
  constant I2C_OP_NONE      : std_logic_vector(2-1 downto 0) := "00"; -- No byte (START and/or STOP only)
  constant I2C_OP_WRITE     : std_logic_vector(2-1 downto 0) := "01"; -- Write a byte, sample the acknowledge of the slave
  constant I2C_OP_READ_ACK  : std_logic_vector(2-1 downto 0) := "10"; -- Read a byte, answer ACK
  constant I2C_OP_READ_NACK : std_logic_vector(2-1 downto 0) := "11"; -- Read a byte, answer NACK (last byte)

-- [COMPONENT_INSERT][BEGIN]
component sbi_I2C is
  generic(
    NAME                  : string  := "";
    USER_DEFINE_PRESCALER : boolean := true;                         -- Prescaler register writable by software
    PRESCALER_RATIO       : std_logic_vector(8-1 downto 0) := x"7C"; -- Default value for prescaler ratio (100 kHz with a 50 MHz clock)
    MASTER_ENABLE         : boolean := true;                         -- Implement the master (and the cmd register)
    SLAVE_ENABLE          : boolean := true;                         -- Implement the slave
    DEPTH_CMD             : natural := 0;
    DEPTH_TX              : natural := 0;
    DEPTH_RX              : natural := 0;

    FILENAME_CMD          : string  := "dump_i2c_cmd.txt";
    FILENAME_TX           : string  := "dump_i2c_tx.txt";
    FILENAME_RX           : string  := "dump_i2c_rx.txt"
    );
  port   (
    clk_i            : in  std_logic;
    arst_b_i         : in  std_logic; -- asynchronous reset

    -- Bus
    sbi_ini_i        : in  sbi_ini_t;
    sbi_tgt_o        : out sbi_tgt_t;

    -- I2C Interface (open drain : xx_o is always 0, xx_oe_o = 1 pulls the line low)
    scl_i            : in  std_logic;
    scl_o            : out std_logic;
    scl_oe_o         : out std_logic;
    sda_i            : in  std_logic;
    sda_o            : out std_logic;
    sda_oe_o         : out std_logic
    );

end component sbi_I2C;

component i2c_core is
  generic (
    PRESCALER_WIDTH      : natural := 8;
    MASTER_ENABLE        : boolean := true;                   -- Implement the master
    SLAVE_ENABLE         : boolean := true                    -- Implement the slave
    );
  port (
    -- Clock & Reset
    clk_i                : in  std_logic;
    arst_b_i             : in  std_logic;

    -- Data From AXI Stream To I2C
    -- (master : bytes of the WRITE commands, slave : bytes read by the master)
    tx_tvalid_i          : in  std_logic;
    tx_tready_o          : out std_logic;
    tx_tdata_i           : in  std_logic_vector(8-1 downto 0);

    -- Data From I2C To AXI Stream
    -- (master : bytes of the READ commands, slave : bytes written by the master)
    rx_tvalid_o          : out std_logic;
    rx_tready_i          : in  std_logic;
    rx_tdata_o           : out std_logic_vector(8-1 downto 0);

    -- Master Command
    cmd_tvalid_i         : in  std_logic;
    cmd_tready_o         : out std_logic;
    cmd_start_i          : in  std_logic;                     -- START (or repeated START) before the byte
    cmd_stop_i           : in  std_logic;                     -- STOP after the byte
    cmd_op_i             : in  std_logic_vector(2-1 downto 0);-- Byte operation (I2C_OP_*)

    -- Configuration
    cfg_prescaler_ratio_i: in  std_logic_vector(PRESCALER_WIDTH-1 downto 0); -- Quarter of SCL period minus one, in clock cycles
    cfg_slave_addr_i     : in  std_logic_vector(7-1 downto 0);-- 7-bit address of the slave, 0 : slave disabled

    -- Status
    sts_busy_o           : out std_logic;                     -- Master : command in progress or pending
    sts_nack_o           : out std_logic;                     -- Master : NACK received since the last START on a released bus
    sts_bus_busy_o       : out std_logic;                     -- START detected and no STOP since
    sts_slave_addressed_o: out std_logic;                     -- Slave  : address acknowledged, until the next STOP or START
    sts_slave_read_o     : out std_logic;                     -- Slave  : R/W bit of the last acknowledged address

    -- I2C Interface (open drain)
    scl_i                : in  std_logic;
    scl_o                : out std_logic;
    scl_oe_o             : out std_logic;
    sda_i                : in  std_logic;
    sda_o                : out std_logic;
    sda_oe_o             : out std_logic
    );
end component i2c_core;

component i2c_master is
  generic (
    PRESCALER_WIDTH      : natural := 8
    );
  port (
    -- Clock & Reset
    clk_i                : in  std_logic;
    arst_b_i             : in  std_logic;

    -- Data From AXI Stream To I2C (bytes written)
    tx_tvalid_i          : in  std_logic;
    tx_tready_o          : out std_logic;
    tx_tdata_i           : in  std_logic_vector(8-1 downto 0);

    -- Data From I2C To AXI Stream (bytes read)
    rx_tvalid_o          : out std_logic;
    rx_tready_i          : in  std_logic;
    rx_tdata_o           : out std_logic_vector(8-1 downto 0);

    -- Command
    cmd_tvalid_i         : in  std_logic;
    cmd_tready_o         : out std_logic;
    cmd_start_i          : in  std_logic;                     -- START (or repeated START) before the byte
    cmd_stop_i           : in  std_logic;                     -- STOP after the byte
    cmd_op_i             : in  std_logic_vector(2-1 downto 0);-- Byte operation (I2C_OP_*)

    -- Configuration
    cfg_prescaler_ratio_i: in  std_logic_vector(PRESCALER_WIDTH-1 downto 0); -- Quarter of SCL period minus one, in clock cycles

    -- Status
    sts_busy_o           : out std_logic;                     -- Command in progress or pending
    sts_nack_o           : out std_logic;                     -- NACK received since the last START on a released bus

    -- I2C Bus (synchronized inputs, open drain outputs)
    bus_busy_i           : in  std_logic;                     -- START detected and no STOP since
    scl_i                : in  std_logic;                     -- SCL level (synchronized)
    sda_i                : in  std_logic;                     -- SDA level (synchronized)
    scl_oe_o             : out std_logic;                     -- 1 : SCL pulled low
    sda_oe_o             : out std_logic                      -- 1 : SDA pulled low
    );
end component i2c_master;

component i2c_slave is
  generic (
    PRESCALER_WIDTH      : natural := 8
    );
  port (
    -- Clock & Reset
    clk_i                : in  std_logic;
    arst_b_i             : in  std_logic;

    -- Data From AXI Stream To I2C (bytes read by the master)
    tx_tvalid_i          : in  std_logic;
    tx_tready_o          : out std_logic;
    tx_tdata_i           : in  std_logic_vector(8-1 downto 0);

    -- Data From I2C To AXI Stream (bytes written by the master)
    rx_tvalid_o          : out std_logic;
    rx_tready_i          : in  std_logic;
    rx_tdata_o           : out std_logic_vector(8-1 downto 0);

    -- Configuration
    cfg_enable_i         : in  std_logic;                     -- 0 : slave inactive, SCL and SDA released
    cfg_slave_addr_i     : in  std_logic_vector(7-1 downto 0);-- 7-bit address of the slave
    cfg_prescaler_ratio_i: in  std_logic_vector(PRESCALER_WIDTH-1 downto 0); -- Data setup time after a clock stretching minus one, in clock cycles

    -- Status
    sts_addressed_o      : out std_logic;                     -- Address acknowledged, until the next STOP or START
    sts_read_o           : out std_logic;                     -- R/W bit of the last acknowledged address

    -- I2C Bus (synchronized inputs and events, open drain outputs)
    sda_i                : in  std_logic;                     -- SDA level (synchronized)
    scl_rise_i           : in  std_logic;                     -- Rising  edge of SCL
    scl_fall_i           : in  std_logic;                     -- Falling edge of SCL
    bus_start_i          : in  std_logic;                     -- START condition
    bus_stop_i           : in  std_logic;                     -- STOP  condition
    scl_oe_o             : out std_logic;                     -- 1 : SCL pulled low
    sda_oe_o             : out std_logic                      -- 1 : SDA pulled low
    );
end component i2c_slave;

-- [COMPONENT_INSERT][END]

end i2c_pkg;
