-------------------------------------------------------------------------------
-- Title      : tb_I2C_multi_tests_pkg
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_multi_tests_pkg.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: Scenarios of tb_I2C_multi : names (valid items of TESTS_LIST)
--              and dispatch (run_test) to tb_I2C_multi_transfers_pkg
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_I2C_multi)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_sbi;
use     bitvis_vip_sbi.sbi_bfm_pkg.all;

library asylum;
use     asylum.string_pkg.all;

library work;
use     work.tb_I2C_multi_bfm_pkg.all;
use     work.tb_I2C_multi_transfers_pkg.all;

package tb_I2C_multi_tests_pkg is

  -- Names of the scenarios (valid items of TESTS_LIST)
  constant C_TESTS : string := "write,read,write_read,stretch,nack";

  -- Run the scenario name
  procedure run_test
    (constant name       : in    string
    ;constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   scl        : in    std_logic
    ;signal   scl_oe     : in    std_logic_vector
    );

end package tb_I2C_multi_tests_pkg;

package body tb_I2C_multi_tests_pkg is

  procedure run_test
    (constant name       : in    string
    ;constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   scl        : in    std_logic
    ;signal   scl_oe     : in    std_logic_vector
    ) is
  begin
    if    string_eq(name, "write")
    then
      test_write     (nb_slave, clk, sbi_if);
    elsif string_eq(name, "read")
    then
      test_read      (nb_slave, clk, sbi_if);
    elsif string_eq(name, "write_read")
    then
      test_write_read(nb_slave, clk, sbi_if);
    elsif string_eq(name, "stretch")
    then
      test_stretch   (nb_slave, clk, sbi_if, scl, scl_oe);
    elsif string_eq(name, "nack")
    then
      test_nack      (nb_slave, clk, sbi_if);
    else
      alert(TB_ERROR, "Unknown test " & name, C_TB_SCOPE);
    end if;
  end procedure;

end package body tb_I2C_multi_tests_pkg;
