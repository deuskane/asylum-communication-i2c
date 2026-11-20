-------------------------------------------------------------------------------
-- Title      : tb_I2C_bfm_pkg
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_bfm_pkg.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: Helpers of the tb_I2C scenarios : constants of the bench,
--              register accesses (SBI BFM), DUT configuration and master
--              transfers, requests to the bench processes (I2C BFM, SCL
--              stretching, SCL monitor), reset pulse.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (helpers of the tb_I2C sequencer)
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

package tb_I2C_bfm_pkg is

  constant C_TB_SCOPE         : string  := "TB_I2C";
  constant C_CLK_PERIOD       : time    := 20 ns;
  constant C_PRESCALER_RST    : std_logic_vector(7 downto 0) := x"7C";

  constant C_ADDR_BFM         : natural := 16#50#;  -- Address of the BFM slave
  constant C_ADDR_NONE        : natural := 16#51#;  -- Address without slave
  constant C_ADDR_DUT         : natural := 16#3A#;  -- Address of the DUT slave
  constant C_BIT_TIME_MASTER  : time    := 1 us;    -- SCL period of the BFM master

  constant C_NONE             : t_byte_array(0 to -1) := (others => (others => '0'));

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

  -- Operation of the I2C BFM process
  type bfm_op_t is (BFM_SLAVE_CHECK,              -- BFM slave receives wdata
                    BFM_SLAVE_TRANSMIT,           -- BFM slave transmits rdata
                    BFM_SLAVE_CHECK_TRANSMIT,     -- both, with a repeated START between
                    BFM_MASTER_TRANSMIT,          -- BFM master writes wdata
                    BFM_MASTER_CHECK,             -- BFM master reads and checks rdata
                    BFM_MASTER_TRANSMIT_CHECK,    -- both, with a repeated START between
                    BFM_MASTER_QUICK_NACK);       -- BFM master sends the address, expects a NACK

  -- Requests of the sequencer to the bench processes
  type tb_req_t is record
    bfm_op        : bfm_op_t;
    bfm_addr      : natural;
    bfm_bit_time  : time;
    bfm_wdata     : t_byte_array(0 to 7);
    bfm_wlen      : natural;
    bfm_rdata     : t_byte_array(0 to 7);
    bfm_rlen      : natural;
    bfm_req       : natural;                      -- One more per BFM operation
    stretch_fall  : natural;                      -- Falling edges of SCL to wait
    stretch_time  : time;                         -- Duration of the stretching
    stretch_req   : natural;                      -- One more per stretching
    scl_mon_clear : boolean;                      -- Toggled : clear the SCL monitor
  end record;

  constant C_TB_REQ_INIT      : tb_req_t := (
    bfm_op        => BFM_SLAVE_CHECK,
    bfm_addr      => 0,
    bfm_bit_time  => 1 us,
    bfm_wdata     => (others => (others => '0')),
    bfm_wlen      => 0,
    bfm_rdata     => (others => (others => '0')),
    bfm_rlen      => 0,
    bfm_req       => 0,
    stretch_fall  => 1,
    stretch_time  => 0 ns,
    stretch_req   => 0,
    scl_mon_clear => false
  );

  -- Answers of the bench processes (one process drives each element)
  type tb_rsp_t is record
    bfm_done       : natural;                     -- I2C BFM process
    stretch_done   : natural;                     -- Stretching process
    scl_period_min : time;                        -- SCL monitor : minimum SCL period
    scl_high_min   : time;                        -- and high phase since the last clear
  end record;

  -- Register write
  procedure write_reg
    (constant addr       : in    unsigned
    ;constant data       : in    std_logic_vector
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Register read and check
  procedure check_reg
    (constant addr       : in    unsigned
    ;constant data       : in    std_logic_vector
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Poll the status register until (status and mask) = value
  procedure wait_status
    (constant mask       : in    std_logic_vector(7 downto 0)
    ;constant value      : in    std_logic_vector(7 downto 0)
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Configuration of the DUT : prescaler ratio and cfg (enable, slave address)
  procedure configure
    (constant ratio      : in    natural
    ;constant slave_addr : in    natural
    ;constant enable     : in    std_logic
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- DUT master : START, address + W, bytes, STOP (if stop)
  procedure master_write
    (constant addr       : in    natural
    ;constant data       : in    t_byte_array
    ;constant stop       : in    boolean
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- DUT master : (repeated) START, address + R, nb bytes (ACK except the
  -- last one), STOP
  procedure master_read
    (constant addr       : in    natural
    ;constant nb         : in    natural
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Check the bytes of the RX FIFO
  procedure check_rx
    (constant data       : in    t_byte_array
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    );

  -- Request an operation to the I2C BFM process
  procedure bfm_start
    (constant op         : in    bfm_op_t
    ;constant addr       : in    natural
    ;constant bit_time   : in    time
    ;constant wdata      : in    t_byte_array
    ;constant rdata      : in    t_byte_array
    ;signal   tb_req     : inout tb_req_t
    );

  -- Wait the end of the operation of the I2C BFM process
  procedure bfm_wait
    (constant msg        : in    string
    ;signal   tb_req     : in    tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- Request a stretching of SCL by the bench : SCL held low during duration
  -- after the falling edge number fall
  procedure stretch_start
    (constant fall       : in    natural
    ;constant duration   : in    time
    ;signal   tb_req     : inout tb_req_t
    );

  -- Clear the minimum values of the SCL monitor
  procedure scl_mon_clear
    (signal   tb_req     : inout tb_req_t
    );

  -- Check the SCL period and high phase of the DUT master since the last clear
  procedure check_scl
    (constant ratio      : in    natural
    ;constant msg        : in    string
    ;signal   tb_rsp     : in    tb_rsp_t
    );

  -- Bit time of the DUT master for the BFM slave (without the synchronization
  -- of SCL)
  function bit_time_dut
    (constant ratio      : in    natural
    ) return time;

  -- Reset pulse, released on a falling edge
  procedure do_reset
    (signal   clk        : in    std_logic
    ;signal   arst_b     : out   std_logic
    );

end package tb_I2C_bfm_pkg;

package body tb_I2C_bfm_pkg is

  -- Message panel of the status polling : BFM messages disabled
  function poll_panel return t_msg_id_panel is
    variable v_panel : t_msg_id_panel := C_MSG_ID_PANEL_DEFAULT;
  begin
    v_panel(ID_BFM) := DISABLED;
    return v_panel;
  end function;

  constant C_POLL_PANEL       : t_msg_id_panel := poll_panel;

  procedure write_reg
    (constant addr       : in    unsigned
    ;constant data       : in    std_logic_vector
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    sbi_write(addr_value => addr
             ,data_value => data
             ,msg        => msg
             ,clk        => clk
             ,sbi_if     => sbi_if
             ,scope      => C_TB_SCOPE
             ,config     => C_SBI_CFG
             );
  end procedure;

  procedure check_reg
    (constant addr       : in    unsigned
    ;constant data       : in    std_logic_vector
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    sbi_check(addr_value  => addr
             ,data_exp    => data
             ,msg         => msg
             ,clk         => clk
             ,sbi_if      => sbi_if
             ,alert_level => error
             ,scope       => C_TB_SCOPE
             ,config      => C_SBI_CFG
             );
  end procedure;

  procedure wait_status
    (constant mask       : in    std_logic_vector(7 downto 0)
    ;constant value      : in    std_logic_vector(7 downto 0)
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
    variable v_status : std_logic_vector(7 downto 0);
  begin
    for i in 1 to 100000 loop
      sbi_read(addr_value   => I2C_STATUS
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
    check_value(v_status and mask, value, ERROR, msg & " : status and 0x" & to_hstring(mask), C_TB_SCOPE);
  end procedure;

  procedure configure
    (constant ratio      : in    natural
    ;constant slave_addr : in    natural
    ;constant enable     : in    std_logic
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
    variable v_cfg : std_logic_vector(7 downto 0);
  begin
    v_cfg := std_logic_vector(to_unsigned(slave_addr, 7)) & enable;
    write_reg(I2C_CFG      , x"00", msg & " : disable I2C (i2c_core reset)", clk, sbi_if);
    write_reg(I2C_PRESCALER, std_logic_vector(to_unsigned(ratio, 8)), msg & " : prescaler " & to_string(ratio), clk, sbi_if);
    write_reg(I2C_CFG      , v_cfg, msg & " : cfg 0x" & to_hstring(v_cfg), clk, sbi_if);
    check_reg(I2C_PRESCALER, std_logic_vector(to_unsigned(ratio, 8)), msg & " : read back prescaler", clk, sbi_if);
    check_reg(I2C_CFG      , v_cfg, msg & " : read back cfg", clk, sbi_if);
  end procedure;

  -- Master command : op & stop & start
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
    write_reg(I2C_CMD, "0000" & op & v_stop & v_start, msg, clk, sbi_if);
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
    write_reg(I2C_DATA, std_logic_vector(to_unsigned(addr, 7)) & '0', msg & " : TX address + W", clk, sbi_if);
    command(true, false, I2C_CMD_OP_WRITE, msg & " : command START + WRITE", clk, sbi_if);
    for i in data'range loop
      write_reg(I2C_DATA, data(i), msg & " : TX byte " & to_string(i), clk, sbi_if);
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
    write_reg(I2C_DATA, std_logic_vector(to_unsigned(addr, 7)) & '1', msg & " : TX address + R", clk, sbi_if);
    command(true, false, I2C_CMD_OP_WRITE, msg & " : command START + WRITE", clk, sbi_if);
    for i in 0 to nb-2 loop
      command(false, false, I2C_CMD_OP_READ_ACK, msg & " : command READ_ACK", clk, sbi_if);
    end loop;
    command(false, true, I2C_CMD_OP_READ_NACK, msg & " : command READ_NACK + STOP", clk, sbi_if);
  end procedure;

  procedure check_rx
    (constant data       : in    t_byte_array
    ;constant msg        : in    string
    ;signal   clk        : in    std_logic
    ;signal   sbi_if     : inout t_sbi_if
    ) is
  begin
    for i in data'range loop
      check_reg(I2C_DATA, data(i), msg & " : RX byte " & to_string(i), clk, sbi_if);
    end loop;
  end procedure;

  procedure bfm_start
    (constant op         : in    bfm_op_t
    ;constant addr       : in    natural
    ;constant bit_time   : in    time
    ;constant wdata      : in    t_byte_array
    ;constant rdata      : in    t_byte_array
    ;signal   tb_req     : inout tb_req_t
    ) is
  begin
    tb_req.bfm_op       <= op;
    tb_req.bfm_addr     <= addr;
    tb_req.bfm_bit_time <= bit_time;
    tb_req.bfm_wlen     <= wdata'length;
    tb_req.bfm_rlen     <= rdata'length;
    for i in 0 to wdata'length-1 loop
      tb_req.bfm_wdata(i) <= wdata(wdata'low+i);
    end loop;
    for i in 0 to rdata'length-1 loop
      tb_req.bfm_rdata(i) <= rdata(rdata'low+i);
    end loop;
    tb_req.bfm_req      <= tb_req.bfm_req + 1;
    wait for 0 ns;
  end procedure;

  procedure bfm_wait
    (constant msg        : in    string
    ;signal   tb_req     : in    tb_req_t
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
  begin
    if tb_rsp.bfm_done /= tb_req.bfm_req
    then
      wait until tb_rsp.bfm_done = tb_req.bfm_req for 2 ms;
    end if;
    check_value(tb_rsp.bfm_done, tb_req.bfm_req, ERROR, msg & " : end of the I2C BFM operation", C_TB_SCOPE);
  end procedure;

  procedure stretch_start
    (constant fall       : in    natural
    ;constant duration   : in    time
    ;signal   tb_req     : inout tb_req_t
    ) is
  begin
    tb_req.stretch_fall <= fall;
    tb_req.stretch_time <= duration;
    tb_req.stretch_req  <= tb_req.stretch_req + 1;
    wait for 0 ns;
  end procedure;

  procedure scl_mon_clear
    (signal   tb_req     : inout tb_req_t
    ) is
  begin
    tb_req.scl_mon_clear <= not tb_req.scl_mon_clear;
  end procedure;

  procedure check_scl
    (constant ratio      : in    natural
    ;constant msg        : in    string
    ;signal   tb_rsp     : in    tb_rsp_t
    ) is
  begin
    check_value(tb_rsp.scl_period_min, (4*(ratio+1)+2)*C_CLK_PERIOD, ERROR, msg & " : SCL period = 4*(ratio+1)+2 clock cycles", C_TB_SCOPE);
    check_value(tb_rsp.scl_high_min  , (2*(ratio+1)+2)*C_CLK_PERIOD, ERROR, msg & " : SCL high phase >= 2*(ratio+1)+2 clock cycles", C_TB_SCOPE);
  end procedure;

  function bit_time_dut
    (constant ratio      : in    natural
    ) return time is
  begin
    return 4*(ratio+1)*C_CLK_PERIOD;
  end function;

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

end package body tb_I2C_bfm_pkg;
