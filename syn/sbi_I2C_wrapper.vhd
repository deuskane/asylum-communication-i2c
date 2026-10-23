-------------------------------------------------------------------------------
-- Title      : sbi_I2C_wrapper
-- Project    : Asylum
-------------------------------------------------------------------------------
-- File       : sbi_I2C_wrapper.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description:
-- Synthesis check top (lint_ghdl, lint_ghdl_synth) : sbi_I2C (and so
-- i2c_core, i2c_master and i2c_slave) with flat and constrained SBI ports
-- (sbi_I2C has unconstrained SBI ports and cannot be a synthesis top). SBI
-- address / data width : SBI_ADDR_WIDTH / SBI_DATA_WIDTH. The synthesizable
-- generics are forwarded with the defaults of sbi_I2C.
-- NAME and FILENAME_* are simulation only, not connected.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-22  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
library asylum;
use     asylum.sbi_pkg.all;

entity sbi_I2C_wrapper is
  generic (
    USER_DEFINE_PRESCALER : boolean                        := true;
    PRESCALER_RATIO       : std_logic_vector(8-1 downto 0) := x"7C";
    MASTER_ENABLE         : boolean := true;
    SLAVE_ENABLE          : boolean := true;
    DEPTH_CMD             : natural := 0;
    DEPTH_TX              : natural := 0;
    DEPTH_RX              : natural := 0
  );
  port (
    clk_i         : in  std_logic;
    arst_b_i      : in  std_logic;

    -- Bus (SBI)
    cs_i          : in  std_logic;
    re_i          : in  std_logic;
    we_i          : in  std_logic;
    addr_i        : in  std_logic_vector(SBI_ADDR_WIDTH-1 downto 0);
    wdata_i       : in  std_logic_vector(SBI_DATA_WIDTH-1 downto 0);
    ready_o       : out std_logic;
    rdata_o       : out std_logic_vector(SBI_DATA_WIDTH-1 downto 0);

    -- I2C Interface (open drain)
    scl_i         : in  std_logic;
    scl_o         : out std_logic;
    scl_oe_o      : out std_logic;
    sda_i         : in  std_logic;
    sda_o         : out std_logic;
    sda_oe_o      : out std_logic
  );
end entity sbi_I2C_wrapper;

architecture rtl of sbi_I2C_wrapper is

  signal sbi_ini       : sbi_ini_t(addr (SBI_ADDR_WIDTH-1 downto 0),
                                   wdata(SBI_DATA_WIDTH-1 downto 0));
  signal sbi_tgt       : sbi_tgt_t(rdata(SBI_DATA_WIDTH-1 downto 0));

begin

  sbi_ini.cs        <= cs_i;
  sbi_ini.re        <= re_i;
  sbi_ini.we        <= we_i;
  sbi_ini.addr      <= addr_i;
  sbi_ini.wdata     <= wdata_i;
  ready_o           <= sbi_tgt.ready;
  rdata_o           <= sbi_tgt.rdata;

  ins_sbi_I2C : entity asylum.sbi_I2C
    generic map (
      USER_DEFINE_PRESCALER => USER_DEFINE_PRESCALER,
      PRESCALER_RATIO       => PRESCALER_RATIO,
      MASTER_ENABLE         => MASTER_ENABLE,
      SLAVE_ENABLE          => SLAVE_ENABLE,
      DEPTH_CMD             => DEPTH_CMD,
      DEPTH_TX              => DEPTH_TX,
      DEPTH_RX              => DEPTH_RX
    )
    port map (
      clk_i                 => clk_i,
      arst_b_i              => arst_b_i,
      sbi_ini_i             => sbi_ini,
      sbi_tgt_o             => sbi_tgt,
      scl_i                 => scl_i,
      scl_o                 => scl_o,
      scl_oe_o              => scl_oe_o,
      sda_i                 => sda_i,
      sda_o                 => sda_o,
      sda_oe_o              => sda_oe_o
    );

end architecture rtl;
