-------------------------------------------------------------------------------
-- Title      : tb_I2C_slave_pkg
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_slave_pkg.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: Scenarios of tb_I2C with the BFM master and the DUT slave,
--              each one from reset :
--              * slave_write         : BFM master writes to the DUT slave
--              * slave_read          : BFM master reads from the DUT slave
--              * slave_stretch       : BFM master reads, TX FIFO empty :
--                                      clock stretching by the DUT
--              * slave_write_read    : write + repeated START + read
--              * slave_wrong_address : NACK on an other address
--              * slave_disabled      : NACK if slave address is 0
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

package tb_I2C_slave_pkg is

  -- BFM master writes 4 bytes to the DUT slave
  procedure test_slave_write
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- BFM master reads 3 bytes from the DUT slave
  procedure test_slave_read
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- BFM master reads from the DUT slave with an empty TX FIFO : SCL held low
  -- by the DUT until the bytes are written
  procedure test_slave_stretch
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ;signal   scl        : in    std_logic
    ;signal   scl_oe     : in    std_logic
    );

  -- BFM master write + repeated START + read from the DUT slave
  procedure test_slave_write_read
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- BFM master addresses an other slave : NACK
  procedure test_slave_wrong_address
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- BFM master addresses a disabled slave (cfg.slave_addr = 0) : NACK
  procedure test_slave_disabled
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

end package tb_I2C_slave_pkg;

package body tb_I2C_slave_pkg is

  procedure test_slave_write
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
  begin
    configure(4, C_ADDR_DUT, '1', "Slave", clk, sbi_if);
    bfm_start(BFM_MASTER_TRANSMIT, C_ADDR_DUT, C_BIT_TIME_MASTER, t_byte_array'(x"DE", x"AD", x"BE", x"EF"), C_NONE, tb_req);
    wait_status(x"18", x"08", "Slave write : addressed, master writes", clk, sbi_if);
    bfm_wait("Slave write", tb_req, tb_rsp);
    wait_status(x"3C", x"00", "Slave write : STOP, bus free, RX FIFO not empty", clk, sbi_if);
    check_rx(t_byte_array'(x"DE", x"AD", x"BE", x"EF"), "Slave write", clk, sbi_if);
    check_reg(I2C_STATUS, x"20", "Slave write : RX FIFO empty", clk, sbi_if);
  end procedure;

  procedure test_slave_read
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
  begin
    configure(4, C_ADDR_DUT, '1', "Slave", clk, sbi_if);
    write_reg(I2C_DATA, x"12", "Slave read : TX byte 0", clk, sbi_if);
    write_reg(I2C_DATA, x"34", "Slave read : TX byte 1", clk, sbi_if);
    write_reg(I2C_DATA, x"56", "Slave read : TX byte 2", clk, sbi_if);
    bfm_start(BFM_MASTER_CHECK, C_ADDR_DUT, C_BIT_TIME_MASTER, C_NONE, t_byte_array'(x"12", x"34", x"56"), tb_req);
    wait_status(x"18", x"18", "Slave read : addressed, master reads", clk, sbi_if);
    bfm_wait("Slave read", tb_req, tb_rsp);
    wait_status(x"3C", x"30", "Slave read : STOP, bus free, last direction read", clk, sbi_if);
  end procedure;

  procedure test_slave_stretch
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ;signal   scl        : in    std_logic
    ;signal   scl_oe     : in    std_logic
    ) is
  begin
    configure(4, C_ADDR_DUT, '1', "Slave", clk, sbi_if);
    bfm_start(BFM_MASTER_CHECK, C_ADDR_DUT, C_BIT_TIME_MASTER, C_NONE, t_byte_array'(x"9A", x"BC"), tb_req);
    wait_status(x"18", x"18", "Slave stretching : addressed, master reads", clk, sbi_if);
    wait for 10*C_BIT_TIME_MASTER;
    check_value(scl   , '0', MATCH_STD, ERROR, "Slave stretching : SCL held low by the DUT", C_TB_SCOPE);
    check_value(scl_oe, '1', ERROR, "Slave stretching : DUT pulls SCL low", C_TB_SCOPE);
    write_reg(I2C_DATA, x"9A", "Slave stretching : TX byte 0", clk, sbi_if);
    write_reg(I2C_DATA, x"BC", "Slave stretching : TX byte 1", clk, sbi_if);
    bfm_wait("Slave stretching", tb_req, tb_rsp);
    wait_status(x"3C", x"30", "Slave stretching : STOP, bus free", clk, sbi_if);
  end procedure;

  procedure test_slave_write_read
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
  begin
    configure(4, C_ADDR_DUT, '1', "Slave", clk, sbi_if);
    write_reg(I2C_DATA, x"77", "Slave register read : TX byte", clk, sbi_if);
    bfm_start(BFM_MASTER_TRANSMIT_CHECK, C_ADDR_DUT, C_BIT_TIME_MASTER, t_byte_array'(0 => x"07"), t_byte_array'(0 => x"77"), tb_req);
    bfm_wait("Slave register read", tb_req, tb_rsp);
    wait_status(x"3C", x"10", "Slave register read : STOP, bus free, RX FIFO not empty", clk, sbi_if);
    check_rx(t_byte_array'(0 => x"07"), "Slave register read", clk, sbi_if);
  end procedure;

  procedure test_slave_wrong_address
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
  begin
    configure(4, C_ADDR_DUT, '1', "Slave", clk, sbi_if);
    bfm_start(BFM_MASTER_QUICK_NACK, C_ADDR_DUT+1, C_BIT_TIME_MASTER, C_NONE, C_NONE, tb_req);
    bfm_wait("Wrong address", tb_req, tb_rsp);
    check_reg(I2C_STATUS, x"20", "Wrong address : not addressed, RX FIFO empty", clk, sbi_if);
  end procedure;

  procedure test_slave_disabled
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
  begin
    configure(4, 0, '1', "Slave disabled", clk, sbi_if);
    bfm_start(BFM_MASTER_QUICK_NACK, C_ADDR_DUT, C_BIT_TIME_MASTER, C_NONE, C_NONE, tb_req);
    bfm_wait("Slave disabled", tb_req, tb_rsp);
    check_reg(I2C_STATUS, x"20", "Slave disabled : not addressed, RX FIFO empty", clk, sbi_if);
  end procedure;

end package body tb_I2C_slave_pkg;
