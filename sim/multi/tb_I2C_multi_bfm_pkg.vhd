-------------------------------------------------------------------------------
-- Title      : tb_I2C_multi_bfm_pkg
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_multi_bfm_pkg.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: Helpers of the tb_I2C_multi scenarios : constants of the
--              bench, register accesses of an instance (one SBI BFM, the 2
--              MSB of the address select the instance), configuration of the
--              instances, transfers of the master I2C0, reset pulse.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (helpers of the tb_I2C_multi
--                               sequencer)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_sbi;
use     bitvis_vip_sbi.sbi_bfm_pkg.all;

library asylum;
use     asylum.I2C_csr_pkg.all;

package tb_I2C_multi_bfm_pkg is

  constant C_TB_SCOPE         : string   := "TB_I2C_MULTI";
  constant C_CLK_PERIOD       : time     := 20 ns;
  constant C_RATIO            : natural  := 4;        -- Prescaler of all the instances
  constant C_SEL_WIDTH        : natural  := 2;        -- SBI address bits selecting the instance
  constant C_ADDR_SLAVE_BASE  : natural  := 16#10#;   -- Address of the slave I2Ck : 0x10 + k
  constant C_ADDR_NONE        : natural  := 16#20#;   -- Address without slave

  -- Blocking FIFO registers : an access may wait for the I2C transfer
  constant C_SBI_CFG          : t_sbi_bfm_config := (
    max_wait_cycles            => 100000,
    max_wait_cycles_severity   => failure,
    use_fixed_wait_cycles_read => false,
    fixed_wait_cycles_read     => 0,
    clock_period               => -1 ns,
    clock_period_margin        => 0 ns,
    clock_margin_severity      => TB_ERROR,
    setup_time                 => -1 ns,
    hold_time                  => -1 ns,
    bfm_sync                   => SYNC_ON_CLOCK_ONLY,
    match_strictness           => MATCH_EXACT,
    id_for_bfm                 => ID_BFM,
    id_for_bfm_wait            => ID_BFM_WAIT,
    id_for_bfm_poll            => ID_BFM_POLL,
    use_ready_signal           => true
  );

  -- Data patterns
  function pattern
    (constant seed       : in    natural
    ;constant i          : in    natural
    ) return std_logic_vector;

  -- 7-bit address of the slave I2Ck
  function slave_addr
    (constant k          : in    natural
    ) return natural;

  -- Register write of the instance inst
  procedure write_reg
    (constant inst       : in    natural
    ;constant addr       : in    unsigned
    ;constant data       : in    std_logic_vector
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Register read and check of the instance inst
  procedure check_reg
    (constant inst       : in    natural
    ;constant addr       : in    unsigned
    ;constant data       : in    std_logic_vector
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Poll the status register of the instance inst until
  -- (status and mask) = value
  procedure wait_status
    (constant inst       : in    natural
    ;constant mask       : in    std_logic_vector(7 downto 0)
    ;constant value      : in    std_logic_vector(7 downto 0)
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Prescaler and cfg (enable, slave address) of the master I2C0 and of the
  -- slaves I2C1 to I2C<nb_slave>
  procedure configure_all
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Master (I2C0) : START, address + W, bytes, STOP (if stop)
  procedure master_write
    (constant addr       : in    natural
    ;constant data       : in    t_byte_array
    ;constant stop       : in    boolean
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Master (I2C0) : (repeated) START, address + R, nb bytes (ACK except the
  -- last one), STOP
  procedure master_read
    (constant addr       : in    natural
    ;constant nb         : in    natural
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Check the bytes of the RX FIFO of the instance inst
  procedure check_rx
    (constant inst       : in    natural
    ;constant data       : in    t_byte_array
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Reset pulse, released on a falling edge
  procedure do_reset
    (signal   clk        : in    std_logic
    ;signal   arst_b     : out   std_logic
    );

end package tb_I2C_multi_bfm_pkg;

package body tb_I2C_multi_bfm_pkg is

  -- Message panel of the status polling : BFM messages disabled
  function poll_panel return t_msg_id_panel is
    variable v_panel : t_msg_id_panel := C_MSG_ID_PANEL_DEFAULT;
  begin
    v_panel(ID_BFM) := DISABLED;
    return v_panel;
  end function;

  constant C_POLL_PANEL       : t_msg_id_panel := poll_panel;

  -- SBI address of the register addr of the instance inst
  function inst_addr
    (constant inst       : in    natural
    ;constant addr       : in    unsigned
    ) return unsigned is
  begin
    return to_unsigned(inst, C_SEL_WIDTH) & addr;
  end function;

  function pattern
    (constant seed       : in    natural
    ;constant i          : in    natural
    ) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned((seed*37 + i*53 + 16#5A#) mod 256, 8));
  end function;

  function slave_addr
    (constant k          : in    natural
    ) return natural is
  begin
    return C_ADDR_SLAVE_BASE + k;
  end function;

  procedure write_reg
    (constant inst       : in    natural
    ;constant addr       : in    unsigned
    ;constant data       : in    std_logic_vector
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    sbi_write(addr_value => inst_addr(inst, addr)
             ,data_value => data
             ,msg        => "I2C" & to_string(inst) & " : " & msg
             ,clk        => clk
             ,sbi_if     => sbi_if
             ,scope      => C_TB_SCOPE
             ,config     => C_SBI_CFG
             );
  end procedure;

  procedure check_reg
    (constant inst       : in    natural
    ;constant addr       : in    unsigned
    ;constant data       : in    std_logic_vector
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    sbi_check(addr_value  => inst_addr(inst, addr)
             ,data_exp    => data
             ,msg         => "I2C" & to_string(inst) & " : " & msg
             ,clk         => clk
             ,sbi_if      => sbi_if
             ,alert_level => error
             ,scope       => C_TB_SCOPE
             ,config      => C_SBI_CFG
             );
  end procedure;

  procedure wait_status
    (constant inst       : in    natural
    ;constant mask       : in    std_logic_vector(7 downto 0)
    ;constant value      : in    std_logic_vector(7 downto 0)
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
    variable v_status : std_logic_vector(7 downto 0);
  begin
    for i in 1 to 100000 loop
      sbi_read(addr_value   => inst_addr(inst, I2C_STATUS)
              ,data_value   => v_status
              ,msg          => msg & " : poll status"
              ,clk          => clk
              ,sbi_if       => sbi_if
              ,scope        => C_TB_SCOPE
              ,msg_id_panel => C_POLL_PANEL
              ,config       => C_SBI_CFG
              );
      exit when (v_status and mask) = value;
    end loop;
    check_value(v_status and mask, value, ERROR, "I2C" & to_string(inst) & " : " & msg & " : status and 0x" & to_hstring(mask), C_TB_SCOPE);
  end procedure;

  -- Prescaler and cfg (enable, slave address) of the instance inst
  procedure configure
    (constant inst       : in    natural
    ;constant addr       : in    natural
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
    variable v_cfg : std_logic_vector(7 downto 0);
  begin
    v_cfg := std_logic_vector(to_unsigned(addr, 7)) & '1';
    write_reg(inst, I2C_PRESCALER, std_logic_vector(to_unsigned(C_RATIO, 8)), "prescaler " & to_string(C_RATIO), clk, sbi_if);
    write_reg(inst, I2C_CFG      , v_cfg, "cfg 0x" & to_hstring(v_cfg), clk, sbi_if);
    check_reg(inst, I2C_CFG      , v_cfg, "read back cfg", clk, sbi_if);
  end procedure;

  procedure configure_all
    (constant nb_slave   : in    positive
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    log(ID_SEQUENCER, "Configuration : I2C0 master, I2C1 to I2C" & to_string(nb_slave) & " slaves", C_TB_SCOPE);
    configure(0, 0, clk, sbi_if);
    for k in 1 to nb_slave loop
      configure(k, slave_addr(k), clk, sbi_if);
    end loop;
  end procedure;

  -- Master command (I2C0) : op & stop & start
  procedure command
    (constant start      : in    boolean
    ;constant stop       : in    boolean
    ;constant op         : in    std_logic_vector(1 downto 0)
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
    variable v_start : std_logic_vector(0 downto 0) := I2C_CMD_START_DISABLE;
    variable v_stop  : std_logic_vector(0 downto 0) := I2C_CMD_STOP_DISABLE;
  begin
    if start then v_start := I2C_CMD_START_ENABLE; end if;
    if stop  then v_stop  := I2C_CMD_STOP_ENABLE;  end if;
    write_reg(0, I2C_CMD, "0000" & op & v_stop & v_start, msg, clk, sbi_if);
  end procedure;

  procedure master_write
    (constant addr       : in    natural
    ;constant data       : in    t_byte_array
    ;constant stop       : in    boolean
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    write_reg(0, I2C_DATA, std_logic_vector(to_unsigned(addr, 7)) & '0', msg & " : TX address + W", clk, sbi_if);
    command(true, false, I2C_CMD_OP_WRITE, msg & " : command START + WRITE", clk, sbi_if);
    for i in data'range loop
      write_reg(0, I2C_DATA, data(i), msg & " : TX byte " & to_string(i), clk, sbi_if);
      command(false, stop and i = data'high, I2C_CMD_OP_WRITE, msg & " : command WRITE", clk, sbi_if);
    end loop;
  end procedure;

  procedure master_read
    (constant addr       : in    natural
    ;constant nb         : in    natural
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    write_reg(0, I2C_DATA, std_logic_vector(to_unsigned(addr, 7)) & '1', msg & " : TX address + R", clk, sbi_if);
    command(true, false, I2C_CMD_OP_WRITE, msg & " : command START + WRITE", clk, sbi_if);
    for i in 0 to nb-2 loop
      command(false, false, I2C_CMD_OP_READ_ACK, msg & " : command READ_ACK", clk, sbi_if);
    end loop;
    command(false, true, I2C_CMD_OP_READ_NACK, msg & " : command READ_NACK + STOP", clk, sbi_if);
  end procedure;

  procedure check_rx
    (constant inst       : in    natural
    ;constant data       : in    t_byte_array
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    for i in data'range loop
      check_reg(inst, I2C_DATA, data(i), msg & " : RX byte " & to_string(i), clk, sbi_if);
    end loop;
  end procedure;

  procedure do_reset
    (signal   clk        : in    std_logic
    ;signal   arst_b     : out   std_logic
    ) is
  begin
    arst_b <= '0';
    wait for 100 ns;
    wait until falling_edge(clk);
    arst_b <= '1';
    wait until rising_edge(clk);
  end procedure;

end package body tb_I2C_multi_bfm_pkg;
