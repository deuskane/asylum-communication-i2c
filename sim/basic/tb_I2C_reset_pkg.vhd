-------------------------------------------------------------------------------
-- Title      : tb_I2C_reset_pkg
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_reset_pkg.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: Scenarios reset_values and disabled of tb_I2C, from reset :
--              * reset_values : reset values of the registers, pads released
--              * disabled     : NACK and pads released if cfg.enable = 0
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_I2C)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_sbi;
use     bitvis_vip_sbi.sbi_bfm_pkg.all;

library asylum;
use     asylum.I2C_csr_pkg.all;

library work;
use     work.tb_I2C_bfm_pkg.all;

package tb_I2C_reset_pkg is

  -- Reset values of cfg, prescaler and status, SCL and SDA released
  procedure test_reset_values
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   scl_oe     : in    std_logic
    ;signal   sda_oe     : in    std_logic
    );

  -- BFM master addresses a disabled I2C (cfg.enable = 0) : NACK, SCL and SDA
  -- released
  procedure test_disabled
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ;signal   scl_oe     : in    std_logic
    ;signal   sda_oe     : in    std_logic
    );

end package tb_I2C_reset_pkg;

package body tb_I2C_reset_pkg is

  procedure test_reset_values
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   scl_oe     : in    std_logic
    ;signal   sda_oe     : in    std_logic
    ) is
  begin
    check_reg(I2C_CFG      , x"00"          , "Reset value cfg"                        , clk, sbi_if);
    check_reg(I2C_PRESCALER, C_PRESCALER_RST, "Reset value prescaler (PRESCALER_RATIO)", clk, sbi_if);
    check_reg(I2C_STATUS   , x"20"          , "Reset value status (rx_empty)"          , clk, sbi_if);
    check_value(scl_oe, '0', ERROR, "I2C disabled : SCL released", C_TB_SCOPE);
    check_value(sda_oe, '0', ERROR, "I2C disabled : SDA released", C_TB_SCOPE);
  end procedure;

  procedure test_disabled
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ;signal   scl_oe     : in    std_logic
    ;signal   sda_oe     : in    std_logic
    ) is
  begin
    configure(4, C_ADDR_DUT, '0', "I2C disabled", clk, sbi_if);
    bfm_start(BFM_MASTER_QUICK_NACK, C_ADDR_DUT, C_BIT_TIME_MASTER, C_NONE, C_NONE, tb_req);
    bfm_wait("I2C disabled", tb_req, tb_rsp);
    check_reg(I2C_STATUS, x"20", "I2C disabled : not addressed, RX FIFO empty", clk, sbi_if);
    check_value(scl_oe, '0', ERROR, "I2C disabled : SCL released", C_TB_SCOPE);
    check_value(sda_oe, '0', ERROR, "I2C disabled : SDA released", C_TB_SCOPE);
  end procedure;

end package body tb_I2C_reset_pkg;
