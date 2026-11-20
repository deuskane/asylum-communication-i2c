-------------------------------------------------------------------------------
-- Title      : tb_I2C_tests_pkg
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_tests_pkg.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: Scenarios of tb_I2C : names (valid items of TESTS_LIST) and
--              dispatch (run_test) to the packages of the scenarios
--              (tb_I2C_reset_pkg, tb_I2C_master_pkg, tb_I2C_slave_pkg)
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
use     asylum.string_pkg.all;

library work;
use     work.tb_I2C_bfm_pkg.all;
use     work.tb_I2C_reset_pkg.all;
use     work.tb_I2C_master_pkg.all;
use     work.tb_I2C_slave_pkg.all;

package tb_I2C_tests_pkg is

  -- Names of the scenarios (valid items of TESTS_LIST)
  constant C_TESTS : string := "reset_values,master_write,master_read,master_write_read,master_nack,master_stretch,master_prescaler,slave_write,slave_read,slave_stretch,slave_write_read,slave_wrong_address,slave_disabled,disabled";

  -- Run the scenario name
  procedure run_test
    (constant name       : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ;signal   scl        : in    std_logic
    ;signal   scl_oe     : in    std_logic
    ;signal   sda_oe     : in    std_logic
    );

end package tb_I2C_tests_pkg;

package body tb_I2C_tests_pkg is

  procedure run_test
    (constant name       : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ;signal   scl        : in    std_logic
    ;signal   scl_oe     : in    std_logic
    ;signal   sda_oe     : in    std_logic
    ) is
  begin
    if    string_eq(name, "reset_values")
    then
      test_reset_values       (clk, sbi_if, scl_oe, sda_oe);
    elsif string_eq(name, "master_write")
    then
      test_master_write       (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "master_read")
    then
      test_master_read        (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "master_write_read")
    then
      test_master_write_read  (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "master_nack")
    then
      test_master_nack        (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "master_stretch")
    then
      test_master_stretch     (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "master_prescaler")
    then
      test_master_prescaler   (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "slave_write")
    then
      test_slave_write        (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "slave_read")
    then
      test_slave_read         (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "slave_stretch")
    then
      test_slave_stretch      (clk, sbi_if, tb_req, tb_rsp, scl, scl_oe);
    elsif string_eq(name, "slave_write_read")
    then
      test_slave_write_read   (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "slave_wrong_address")
    then
      test_slave_wrong_address(clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "slave_disabled")
    then
      test_slave_disabled     (clk, sbi_if, tb_req, tb_rsp);
    elsif string_eq(name, "disabled")
    then
      test_disabled           (clk, sbi_if, tb_req, tb_rsp, scl_oe, sda_oe);
    else
      alert(TB_ERROR, "Unknown test " & name, C_TB_SCOPE);
    end if;
  end procedure;

end package body tb_I2C_tests_pkg;
