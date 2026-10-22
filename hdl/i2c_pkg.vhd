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

-- [COMPONENT_INSERT][END]

end i2c_pkg;
