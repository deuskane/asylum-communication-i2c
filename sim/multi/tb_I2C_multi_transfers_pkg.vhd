-------------------------------------------------------------------------------
-- Title      : tb_I2C_multi_transfers_pkg
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_multi_transfers_pkg.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: Scenarios of tb_I2C_multi, each one from reset, after the
--              configuration of every instance :
--              * write      : the master writes to each slave (only the
--                             addressed slave receives the bytes)
--              * read       : the master reads from each slave
--              * write_read : write to a slave + repeated START + read from
--                             an other slave
--              * stretch    : read from a slave with an empty TX FIFO :
--                             clock stretching by the slave until the
--                             software writes the bytes
--              * nack       : write to an absent address : NACK, no slave
--                             addressed
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
use     asylum.I2C_csr_pkg.all;

library work;
use     work.tb_I2C_multi_bfm_pkg.all;

package tb_I2C_multi_transfers_pkg is

  -- The master writes to each slave : only the addressed slave receives the
  -- bytes
  procedure test_write
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- The master reads from each slave
  procedure test_read
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Write to I2C1 + repeated START + read from I2C<nb_slave>
  procedure test_write_read
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Read from I2C<nb_slave> with an empty TX FIFO : SCL held low by the slave
  -- until the software writes the bytes
  procedure test_stretch
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   scl        : in    std_logic
    ;signal   scl_oe     : in    std_logic_vector
    );

  -- Write to an absent address : NACK, no slave addressed
  procedure test_nack
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

end package tb_I2C_multi_transfers_pkg;

package body tb_I2C_multi_transfers_pkg is

  procedure test_write
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    configure_all(nb_slave, clk, sbi_if);
    for k in 1 to nb_slave loop
      master_write(slave_addr(k), t_byte_array'(pattern(k, 0), pattern(k, 1)), true, "Write to I2C" & to_string(k), clk, sbi_if);
      wait_status(0, x"07", x"00", "Write to I2C" & to_string(k) & " : not busy, ACK, bus free", clk, sbi_if);
      check_rx(k, t_byte_array'(pattern(k, 0), pattern(k, 1)), "Write to I2C" & to_string(k), clk, sbi_if);
      for j in 1 to nb_slave loop
        wait_status(j, x"2C", x"20", "Write to I2C" & to_string(k) & " : bus free, not addressed, RX FIFO empty", clk, sbi_if);
      end loop;
    end loop;
  end procedure;

  procedure test_read
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    configure_all(nb_slave, clk, sbi_if);
    for k in 1 to nb_slave loop
      for i in 0 to 2 loop
        write_reg(k, I2C_DATA, pattern(k+10, i), "Read from I2C" & to_string(k) & " : TX byte " & to_string(i), clk, sbi_if);
      end loop;
      master_read(slave_addr(k), 3, "Read from I2C" & to_string(k), clk, sbi_if);
      check_rx(0, t_byte_array'(pattern(k+10, 0), pattern(k+10, 1), pattern(k+10, 2)), "Read from I2C" & to_string(k), clk, sbi_if);
      wait_status(0, x"07", x"00", "Read from I2C" & to_string(k) & " : not busy, ACK, bus free", clk, sbi_if);
      wait_status(k, x"3C", x"30", "Read from I2C" & to_string(k) & " : bus free, not addressed, last direction read, RX FIFO empty", clk, sbi_if);
    end loop;
  end procedure;

  procedure test_write_read
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    configure_all(nb_slave, clk, sbi_if);
    write_reg(nb_slave, I2C_DATA, x"C3", "Register read : TX byte", clk, sbi_if);
    master_write(slave_addr(1), t_byte_array'(0 => x"5A"), false, "Register read : write I2C1", clk, sbi_if);
    wait_status(0, x"07", x"04", "Register read : write done, ACK, bus kept by the master", clk, sbi_if);
    wait_status(1, x"18", x"08", "Register read : addressed, master writes", clk, sbi_if);
    if nb_slave > 1
    then
      wait_status(nb_slave, x"08", x"00", "Register read : not addressed", clk, sbi_if);
    end if;
    master_read(slave_addr(nb_slave), 1, "Register read : repeated START, read I2C" & to_string(nb_slave), clk, sbi_if);
    check_rx(0, t_byte_array'(0 => x"C3"), "Register read", clk, sbi_if);
    wait_status(0, x"07", x"00", "Register read : not busy, ACK, bus free", clk, sbi_if);
    check_rx(1, t_byte_array'(0 => x"5A"), "Register read", clk, sbi_if);
    wait_status(1, x"08", x"00", "Register read : not addressed after the repeated START", clk, sbi_if);
    wait_status(nb_slave, x"18", x"10", "Register read : not addressed after the STOP, last direction read", clk, sbi_if);
  end procedure;

  procedure test_stretch
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ;signal   scl        : in    std_logic
    ;signal   scl_oe     : in    std_logic_vector
    ) is
  begin
    configure_all(nb_slave, clk, sbi_if);
    master_read(slave_addr(nb_slave), 2, "Slave stretching", clk, sbi_if);
    wait_status(nb_slave, x"18", x"18", "Slave stretching : addressed, master reads", clk, sbi_if);
    wait for 20 us;
    check_value(scl             , '0', MATCH_STD, ERROR, "Slave stretching : SCL held low", C_TB_SCOPE);
    check_value(scl_oe(nb_slave), '1', ERROR, "Slave stretching : I2C" & to_string(nb_slave) & " pulls SCL low", C_TB_SCOPE);
    check_value(scl_oe(0)       , '0', ERROR, "Slave stretching : the master releases SCL", C_TB_SCOPE);
    wait_status(0, x"01", x"01", "Slave stretching : master busy", clk, sbi_if);
    write_reg(nb_slave, I2C_DATA, x"9A", "Slave stretching : TX byte 0", clk, sbi_if);
    write_reg(nb_slave, I2C_DATA, x"BC", "Slave stretching : TX byte 1", clk, sbi_if);
    check_rx(0, t_byte_array'(x"9A", x"BC"), "Slave stretching", clk, sbi_if);
    wait_status(0, x"07", x"00", "Slave stretching : not busy, ACK, bus free", clk, sbi_if);
  end procedure;

  procedure test_nack
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    configure_all(nb_slave, clk, sbi_if);
    master_write(C_ADDR_NONE, t_byte_array'(0 => x"55"), true, "Absent address", clk, sbi_if);
    wait_status(0, x"05", x"00", "Absent address : not busy, bus free", clk, sbi_if);
    check_reg(0, I2C_STATUS, x"22", "Absent address : nack = 1, RX FIFO empty", clk, sbi_if);
    for k in 1 to nb_slave loop
      wait_status(k, x"2C", x"20", "Absent address : not addressed, RX FIFO empty", clk, sbi_if);
    end loop;
  end procedure;

end package body tb_I2C_multi_transfers_pkg;
