-------------------------------------------------------------------------------
-- Title      : tb_I2C_master_pkg
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_master_pkg.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: Scenarios of tb_I2C with the DUT master and the BFM slave,
--              each one from reset :
--              * master_write      : DUT master writes to the BFM slave,
--                                    SCL period and high phase (ratio 4)
--              * master_read       : DUT master reads from the BFM slave
--              * master_write_read : write + repeated START + read
--              * master_nack       : write to an absent slave (NACK), NACK
--                                    status cleared by a new transfer
--              * master_stretch    : SCL stretched by the bench
--              * master_prescaler  : SCL period and high phase (ratio 9)
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

package tb_I2C_master_pkg is

  -- DUT master writes 3 bytes to the BFM slave, SCL period and high phase
  -- (ratio 4)
  procedure test_master_write
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- DUT master reads 3 bytes from the BFM slave
  procedure test_master_read
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- DUT master write + repeated START + read (register read)
  procedure test_master_write_read
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- DUT master writes to an absent slave (NACK), the NACK status is cleared
  -- by the next transfer
  procedure test_master_nack
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- DUT master write with SCL stretched 3 us by the bench
  procedure test_master_stretch
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- SCL period and high phase with ratio 9
  procedure test_master_prescaler
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

end package tb_I2C_master_pkg;

package body tb_I2C_master_pkg is

  procedure test_master_write
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
    constant C_RATIO : natural := 4;
  begin
    configure(C_RATIO, 0, '1', "Master", clk, sbi_if);
    scl_mon_clear(tb_req);
    bfm_start(BFM_SLAVE_CHECK, C_ADDR_BFM, bit_time_dut(C_RATIO), t_byte_array'(x"A5", x"3C", x"0F"), C_NONE, tb_req);
    master_write(C_ADDR_BFM, t_byte_array'(x"A5", x"3C", x"0F"), true, "Master write", clk, sbi_if);
    bfm_wait("Master write", tb_req, tb_rsp);
    wait_status(x"07", x"00", "Master write : not busy, ACK, bus free", clk, sbi_if);
    check_scl(C_RATIO, "Master write", tb_rsp);
  end procedure;

  procedure test_master_read
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
    constant C_RATIO : natural := 4;
  begin
    configure(C_RATIO, 0, '1', "Master", clk, sbi_if);
    bfm_start(BFM_SLAVE_TRANSMIT, C_ADDR_BFM, bit_time_dut(C_RATIO), C_NONE, t_byte_array'(x"11", x"22", x"33"), tb_req);
    master_read(C_ADDR_BFM, 3, "Master read", clk, sbi_if);
    check_rx(t_byte_array'(x"11", x"22", x"33"), "Master read", clk, sbi_if);
    bfm_wait("Master read", tb_req, tb_rsp);
    wait_status(x"27", x"20", "Master read : not busy, ACK, bus free, RX FIFO empty", clk, sbi_if);
  end procedure;

  procedure test_master_write_read
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
    constant C_RATIO : natural := 4;
  begin
    configure(C_RATIO, 0, '1', "Master", clk, sbi_if);
    bfm_start(BFM_SLAVE_CHECK_TRANSMIT, C_ADDR_BFM, bit_time_dut(C_RATIO), t_byte_array'(0 => x"07"), t_byte_array'(x"5A", x"C3"), tb_req);
    master_write(C_ADDR_BFM, t_byte_array'(0 => x"07"), false, "Register read : write register address", clk, sbi_if);
    master_read (C_ADDR_BFM, 2, "Register read : repeated START, read", clk, sbi_if);
    check_rx(t_byte_array'(x"5A", x"C3"), "Register read", clk, sbi_if);
    bfm_wait("Register read", tb_req, tb_rsp);
    wait_status(x"07", x"00", "Register read : not busy, ACK, bus free", clk, sbi_if);
  end procedure;

  procedure test_master_nack
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
    constant C_RATIO : natural := 4;
  begin
    configure(C_RATIO, 0, '1', "Master", clk, sbi_if);
    master_write(C_ADDR_NONE, t_byte_array'(0 => x"55"), true, "Absent slave", clk, sbi_if);
    wait_status(x"05", x"00", "Absent slave : not busy, bus free", clk, sbi_if);
    check_reg(I2C_STATUS, x"22", "Absent slave : status nack = 1", clk, sbi_if);

    -- A new transfer clears the NACK status
    bfm_start(BFM_SLAVE_CHECK, C_ADDR_BFM, bit_time_dut(C_RATIO), t_byte_array'(0 => x"66"), C_NONE, tb_req);
    master_write(C_ADDR_BFM, t_byte_array'(0 => x"66"), true, "Write after NACK", clk, sbi_if);
    bfm_wait("Write after NACK", tb_req, tb_rsp);
    wait_status(x"07", x"00", "Write after NACK : NACK status cleared by the START", clk, sbi_if);
  end procedure;

  procedure test_master_stretch
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
    constant C_RATIO : natural := 4;
  begin
    configure(C_RATIO, 0, '1', "Master", clk, sbi_if);
    scl_mon_clear(tb_req);
    stretch_start(5, 3 us, tb_req);
    bfm_start(BFM_SLAVE_CHECK, C_ADDR_BFM, bit_time_dut(C_RATIO), t_byte_array'(x"C0", x"DE"), C_NONE, tb_req);
    master_write(C_ADDR_BFM, t_byte_array'(x"C0", x"DE"), true, "Stretched write", clk, sbi_if);
    bfm_wait("Stretched write", tb_req, tb_rsp);
    wait_status(x"07", x"00", "Stretched write : not busy, ACK, bus free", clk, sbi_if);
    check_value(tb_rsp.stretch_done, tb_req.stretch_req, ERROR, "Stretched write : SCL stretched by the bench", C_TB_SCOPE);
    check_scl(C_RATIO, "Stretched write : the high phase restarts after the stretching", tb_rsp);
  end procedure;

  procedure test_master_prescaler
    (signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   tb_req     : inout tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
    constant C_RATIO : natural := 9;
  begin
    configure(C_RATIO, 0, '1', "Prescaler 9", clk, sbi_if);
    scl_mon_clear(tb_req);
    bfm_start(BFM_SLAVE_CHECK, C_ADDR_BFM, bit_time_dut(C_RATIO), t_byte_array'(x"81", x"7E"), C_NONE, tb_req);
    master_write(C_ADDR_BFM, t_byte_array'(x"81", x"7E"), true, "Prescaler 9", clk, sbi_if);
    bfm_wait("Prescaler 9", tb_req, tb_rsp);
    wait_status(x"07", x"00", "Prescaler 9 : not busy, ACK, bus free", clk, sbi_if);
    check_scl(C_RATIO, "Prescaler 9", tb_rsp);
  end procedure;

end package body tb_I2C_master_pkg;
