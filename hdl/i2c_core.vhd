-------------------------------------------------------------------------------
-- Title      : i2c_core
-- Project    : Asylum
-------------------------------------------------------------------------------
-- File       : i2c_core.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-22
-- Last update: 2026-10-22
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description:
-- I2C master / slave core, independent of the CSR and of the bus interface :
-- data and commands are AXI Stream like channels (valid / ready), the
-- configuration and the status are plain signals.
-- * Bus monitor : synchronization of SCL and SDA, edges of SCL, START and
--   STOP conditions, bus busy (START detected and no STOP since)
-- * i2c_master  : executes the commands (MASTER_ENABLE = true)
-- * i2c_slave   : answers to cfg_slave_addr_i (SLAVE_ENABLE = true and
--                 cfg_slave_addr_i /= 0)
-- The TX and RX channels are shared by the master and the slave : only one
-- of them transfers bytes at a time (the master has the priority). The
-- master must not address the slave of the same core.
-- Open drain pads : scl_o and sda_o are always 0, scl_oe_o / sda_oe_o = 1
-- pulls the line low (pad = xx_o when xx_oe_o = 1 else Z, with a pull-up).
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-22  1.0      mrosiere Created
-------------------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.numeric_std.ALL;
library asylum;
use     asylum.i2c_pkg.all;
use     asylum.techmap_pkg.all;

entity i2c_core is
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
end entity i2c_core;

architecture rtl of i2c_core is

  -- Bus monitor
  signal   scl_b                  : std_logic;
  signal   sda_b                  : std_logic;
  signal   scl_sync_b             : std_logic;
  signal   sda_sync_b             : std_logic;
  signal   scl                    : std_logic;
  signal   sda                    : std_logic;
  signal   scl_r                  : std_logic;
  signal   sda_r                  : std_logic;
  signal   scl_rise               : std_logic;
  signal   scl_fall               : std_logic;
  signal   bus_start              : std_logic;
  signal   bus_stop               : std_logic;
  signal   bus_busy_r             : std_logic;

  -- Master
  signal   master_tx_tready       : std_logic;
  signal   master_rx_tvalid       : std_logic;
  signal   master_rx_tdata        : std_logic_vector(8-1 downto 0);
  signal   master_scl_oe          : std_logic;
  signal   master_sda_oe          : std_logic;

  -- Slave
  signal   slave_tx_tvalid        : std_logic;
  signal   slave_tx_tready        : std_logic;
  signal   slave_rx_tvalid        : std_logic;
  signal   slave_rx_tready        : std_logic;
  signal   slave_rx_tdata         : std_logic_vector(8-1 downto 0);
  signal   slave_scl_oe           : std_logic;
  signal   slave_sda_oe           : std_logic;

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Bus monitor
  -----------------------------------------------------------------------------
  -- The synchronizers reset to 0 : the inverted lines are synchronized to
  -- get an idle bus (SCL and SDA high) during the reset.
  scl_b                <= not scl_i;
  sda_b                <= not sda_i;

  ins_scl_sync : sync2dffrn
    port map
    (clk_i    => clk_i
    ,arst_b_i => arst_b_i
    ,d_i      => scl_b
    ,q_o      => scl_sync_b
    );

  ins_sda_sync : sync2dffrn
    port map
    (clk_i    => clk_i
    ,arst_b_i => arst_b_i
    ,d_i      => sda_b
    ,q_o      => sda_sync_b
    );

  scl                  <= not scl_sync_b;
  sda                  <= not sda_sync_b;

  -- START : SDA falls while SCL is high
  -- STOP  : SDA rises while SCL is high
  -- SCL must be high on 2 consecutive samples, to ignore SDA changing on the
  -- same sample as SCL
  scl_rise             <=     scl and not scl_r;
  scl_fall             <= not scl and     scl_r;
  bus_start            <= scl and scl_r and     sda_r and not sda;
  bus_stop             <= scl and scl_r and not sda_r and     sda;

  process(clk_i,arst_b_i)
  begin
    if arst_b_i = '0'
    then
      scl_r      <= '1';
      sda_r      <= '1';
      bus_busy_r <= '0';
    elsif rising_edge(clk_i)
    then
      scl_r      <= scl;
      sda_r      <= sda;

      if bus_start = '1'
      then
        bus_busy_r <= '1';
      elsif bus_stop = '1'
      then
        bus_busy_r <= '0';
      end if;
    end if;
  end process;

  sts_bus_busy_o       <= bus_busy_r;

  -----------------------------------------------------------------------------
  -- Master
  -----------------------------------------------------------------------------
  gen_master: if MASTER_ENABLE = true
  generate
    ins_i2c_master : i2c_master
      generic map
      (PRESCALER_WIDTH       => PRESCALER_WIDTH
      )
      port map
      (clk_i                 => clk_i
      ,arst_b_i              => arst_b_i
      ,tx_tvalid_i           => tx_tvalid_i
      ,tx_tready_o           => master_tx_tready
      ,tx_tdata_i            => tx_tdata_i
      ,rx_tvalid_o           => master_rx_tvalid
      ,rx_tready_i           => rx_tready_i
      ,rx_tdata_o            => master_rx_tdata
      ,cmd_tvalid_i          => cmd_tvalid_i
      ,cmd_tready_o          => cmd_tready_o
      ,cmd_start_i           => cmd_start_i
      ,cmd_stop_i            => cmd_stop_i
      ,cmd_op_i              => cmd_op_i
      ,cfg_prescaler_ratio_i => cfg_prescaler_ratio_i
      ,sts_busy_o            => sts_busy_o
      ,sts_nack_o            => sts_nack_o
      ,bus_busy_i            => bus_busy_r
      ,scl_i                 => scl
      ,sda_i                 => sda
      ,scl_oe_o              => master_scl_oe
      ,sda_oe_o              => master_sda_oe
      );
  end generate gen_master;

  gen_master_b: if MASTER_ENABLE = false
  generate
    master_tx_tready     <= '0';
    master_rx_tvalid     <= '0';
    master_rx_tdata      <= (others => '0');
    cmd_tready_o         <= '0';
    sts_busy_o           <= '0';
    sts_nack_o           <= '0';
    master_scl_oe        <= '0';
    master_sda_oe        <= '0';
  end generate gen_master_b;

  -----------------------------------------------------------------------------
  -- Slave
  -----------------------------------------------------------------------------
  gen_slave: if SLAVE_ENABLE = true
  generate
    signal slave_active   : std_logic;
  begin
    -- Address 0 (general call) disables the slave
    slave_active         <= '0' when cfg_slave_addr_i = "0000000" else
                            '1';

    -- The master has the priority on the TX and RX channels
    slave_tx_tvalid      <= tx_tvalid_i and not master_tx_tready;
    slave_rx_tready      <= rx_tready_i and not master_rx_tvalid;

    ins_i2c_slave : i2c_slave
      generic map
      (PRESCALER_WIDTH       => PRESCALER_WIDTH
      )
      port map
      (clk_i                 => clk_i
      ,arst_b_i              => arst_b_i
      ,tx_tvalid_i           => slave_tx_tvalid
      ,tx_tready_o           => slave_tx_tready
      ,tx_tdata_i            => tx_tdata_i
      ,rx_tvalid_o           => slave_rx_tvalid
      ,rx_tready_i           => slave_rx_tready
      ,rx_tdata_o            => slave_rx_tdata
      ,cfg_enable_i          => slave_active
      ,cfg_slave_addr_i      => cfg_slave_addr_i
      ,cfg_prescaler_ratio_i => cfg_prescaler_ratio_i
      ,sts_addressed_o       => sts_slave_addressed_o
      ,sts_read_o            => sts_slave_read_o
      ,sda_i                 => sda
      ,scl_rise_i            => scl_rise
      ,scl_fall_i            => scl_fall
      ,bus_start_i           => bus_start
      ,bus_stop_i            => bus_stop
      ,scl_oe_o              => slave_scl_oe
      ,sda_oe_o              => slave_sda_oe
      );
  end generate gen_slave;

  gen_slave_b: if SLAVE_ENABLE = false
  generate
    slave_tx_tvalid       <= '0';
    slave_tx_tready       <= '0';
    slave_rx_tvalid       <= '0';
    slave_rx_tready       <= '0';
    slave_rx_tdata        <= (others => '0');
    sts_slave_addressed_o <= '0';
    sts_slave_read_o      <= '0';
    slave_scl_oe          <= '0';
    slave_sda_oe          <= '0';
  end generate gen_slave_b;

  -----------------------------------------------------------------------------
  -- TX / RX channels shared by the master and the slave
  -----------------------------------------------------------------------------
  tx_tready_o          <= master_tx_tready or slave_tx_tready;

  rx_tvalid_o          <= master_rx_tvalid or slave_rx_tvalid;
  rx_tdata_o           <= master_rx_tdata when master_rx_tvalid = '1' else
                          slave_rx_tdata;

  -----------------------------------------------------------------------------
  -- Open drain pads : wired AND of the master and of the slave
  -----------------------------------------------------------------------------
  scl_o                <= '0';
  sda_o                <= '0';
  scl_oe_o             <= master_scl_oe or slave_scl_oe;
  sda_oe_o             <= master_sda_oe or slave_sda_oe;

end architecture rtl;
