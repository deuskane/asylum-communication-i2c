-------------------------------------------------------------------------------
-- Title      : tb_I2C
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: UVVM self-checking testbench of sbi_I2C. The CSR are accessed
--              with the SBI BFM, the I2C bus (open drain, pull-up) is driven
--              by the UVVM I2C BFM (bitvis_vip_i2c) in a dedicated process.
--              TESTS_LIST : scenarios run in sequence, separated by ','
--                           (tb_I2C_tests_pkg), each one after a reset
--                           pulse ; "" : build and elaboration only
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-22  1.0      mrosiere Created
-- 2026-10-22  1.1      mrosiere One scenario per simulation (generic TEST)
-- 2026-11-20  1.2      mrosiere TESTS_LIST, scenarios in tb_I2C_<group>_pkg,
--                               helpers in tb_I2C_bfm_pkg, reset pulse
--                               before each scenario
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_sbi;
use     bitvis_vip_sbi.sbi_bfm_pkg.all;

library bitvis_vip_i2c;
use     bitvis_vip_i2c.i2c_bfm_pkg.all;

library asylum;
use     asylum.sbi_pkg.all;
use     asylum.string_pkg.all;
use     asylum.i2c_pkg.all;
use     asylum.I2C_csr_pkg.all;

library work;
use     work.tb_I2C_bfm_pkg.all;
use     work.tb_I2C_tests_pkg.all;

entity tb_I2C is
  generic (
    TESTS_LIST : string := ""                         -- Scenarios, e.g. "master_write,slave_read"
    );
end tb_I2C;

architecture sim of tb_I2C is

  constant C_SCOPE            : string  := "TB_I2C";

  -- DUT
  signal   clk_i              : std_logic := '0';
  signal   clk_ena            : boolean   := true;
  signal   arst_b_i           : std_logic := '0';

  signal   sbi_ini            : sbi_ini_t(addr (I2C_ADDR_WIDTH-1 downto 0),
                                          wdata(I2C_DATA_WIDTH-1 downto 0));
  signal   sbi_tgt            : sbi_tgt_t(rdata(I2C_DATA_WIDTH-1 downto 0));
  signal   sbi_if             : t_sbi_if(addr (I2C_ADDR_WIDTH-1 downto 0),
                                         wdata(I2C_DATA_WIDTH-1 downto 0),
                                         rdata(I2C_DATA_WIDTH-1 downto 0));

  signal   scl_i              : std_logic;
  signal   scl_o              : std_logic;
  signal   scl_oe_o           : std_logic;
  signal   sda_i              : std_logic;
  signal   sda_o              : std_logic;
  signal   sda_oe_o           : std_logic;

  -- I2C bus (open drain with pull-up)
  signal   i2c_if             : t_i2c_if := (scl => 'Z', sda => 'Z');

  -- Requests of the sequencer to the bench processes, and their answers
  signal   tb_req             : tb_req_t := C_TB_REQ_INIT;
  signal   tb_rsp             : tb_rsp_t := (bfm_done       => 0,
                                             stretch_done   => 0,
                                             scl_period_min => 1 sec,
                                             scl_high_min   => 1 sec);

begin

  clock_generator(clk_i, clk_ena, C_CLK_PERIOD, "TB Clock");

  -----------------------------------------------------------------------------
  -- DUT
  -----------------------------------------------------------------------------
  dut : sbi_I2C
    generic map (
      NAME                  => "I2C"
     ,USER_DEFINE_PRESCALER => true
     ,PRESCALER_RATIO       => C_PRESCALER_RST
     ,MASTER_ENABLE         => true
     ,SLAVE_ENABLE          => true
     ,DEPTH_CMD             => 4
     ,DEPTH_TX              => 8
     ,DEPTH_RX              => 8
    )
    port map (
      clk_i      => clk_i
     ,arst_b_i   => arst_b_i
     ,sbi_ini_i  => sbi_ini
     ,sbi_tgt_o  => sbi_tgt
     ,scl_i      => scl_i
     ,scl_o      => scl_o
     ,scl_oe_o   => scl_oe_o
     ,sda_i      => sda_i
     ,sda_o      => sda_o
     ,sda_oe_o   => sda_oe_o
    );

  sbi_ini.cs                              <= sbi_if.cs;
  sbi_ini.addr                            <= std_logic_vector(sbi_if.addr(I2C_ADDR_WIDTH-1 downto 0));
  sbi_ini.re                              <= sbi_if.rena;
  sbi_ini.we                              <= sbi_if.wena;
  sbi_ini.wdata                           <= sbi_if.wdata(I2C_DATA_WIDTH-1 downto 0);
  sbi_if.ready                            <= sbi_tgt.ready;
  sbi_if.rdata(I2C_DATA_WIDTH-1 downto 0) <= sbi_tgt.rdata;

  -----------------------------------------------------------------------------
  -- I2C bus : open drain pads with pull-up
  -----------------------------------------------------------------------------
  i2c_if.scl <= scl_o when scl_oe_o = '1' else 'Z';  -- DUT
  i2c_if.sda <= sda_o when sda_oe_o = '1' else 'Z';
  i2c_if.scl <= 'H';                                  -- Pull-up
  i2c_if.sda <= 'H';

  scl_i      <= to_x01(i2c_if.scl);
  sda_i      <= to_x01(i2c_if.sda);

  -----------------------------------------------------------------------------
  -- I2C BFM (UVVM bitvis_vip_i2c)
  -----------------------------------------------------------------------------
  p_i2c_bfm : process
    variable v_config : t_i2c_bfm_config;
  begin
    i2c_if <= init_i2c_if_signals(VOID);

    loop
      wait on tb_req.bfm_req;

      -- The timings of the START / STOP conditions are one bit time : larger
      -- than the ones of the DUT master, and long enough for the
      -- synchronizers of the DUT
      v_config                                 := C_I2C_BFM_CONFIG_DEFAULT;
      v_config.i2c_bit_time                    := tb_req.bfm_bit_time;
      v_config.master_sda_to_scl               := tb_req.bfm_bit_time;
      v_config.master_scl_to_sda               := tb_req.bfm_bit_time;
      v_config.master_stop_condition_hold_time := tb_req.bfm_bit_time;
      v_config.max_wait_scl_change             := 100 us;
      v_config.max_wait_sda_change             := 100 us;
      v_config.max_wait_scl_change_severity    := ERROR;
      v_config.max_wait_sda_change_severity    := ERROR;
      v_config.i2c_bit_time_severity           := ERROR;
      v_config.acknowledge_severity            := ERROR;
      v_config.slave_mode_address              := to_unsigned(tb_req.bfm_addr, 10);
      v_config.slave_mode_address_severity     := ERROR;
      v_config.slave_rw_bit_severity           := ERROR;

      case tb_req.bfm_op is
        when BFM_SLAVE_CHECK =>
          i2c_slave_check   (tb_req.bfm_wdata(0 to tb_req.bfm_wlen-1), "BFM slave receives", i2c_if, C_WRITE_BIT, ERROR, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_SLAVE_TRANSMIT =>
          i2c_slave_transmit(tb_req.bfm_rdata(0 to tb_req.bfm_rlen-1), "BFM slave transmits", i2c_if, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_SLAVE_CHECK_TRANSMIT =>
          i2c_slave_check   (tb_req.bfm_wdata(0 to tb_req.bfm_wlen-1), "BFM slave receives", i2c_if, C_WRITE_BIT, ERROR, C_SCOPE, shared_msg_id_panel, v_config);
          i2c_slave_transmit(tb_req.bfm_rdata(0 to tb_req.bfm_rlen-1), "BFM slave transmits after a repeated START", i2c_if, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_MASTER_TRANSMIT =>
          i2c_master_transmit(to_unsigned(tb_req.bfm_addr, 7), tb_req.bfm_wdata(0 to tb_req.bfm_wlen-1), "BFM master writes", i2c_if, RELEASE_LINE_AFTER_TRANSFER, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_MASTER_CHECK =>
          i2c_master_check   (to_unsigned(tb_req.bfm_addr, 7), tb_req.bfm_rdata(0 to tb_req.bfm_rlen-1), "BFM master reads", i2c_if, RELEASE_LINE_AFTER_TRANSFER, ERROR, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_MASTER_TRANSMIT_CHECK =>
          i2c_master_transmit(to_unsigned(tb_req.bfm_addr, 7), tb_req.bfm_wdata(0 to tb_req.bfm_wlen-1), "BFM master writes", i2c_if, HOLD_LINE_AFTER_TRANSFER, C_SCOPE, shared_msg_id_panel, v_config);
          i2c_master_check   (to_unsigned(tb_req.bfm_addr, 7), tb_req.bfm_rdata(0 to tb_req.bfm_rlen-1), "BFM master reads after a repeated START", i2c_if, RELEASE_LINE_AFTER_TRANSFER, ERROR, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_MASTER_QUICK_NACK =>
          i2c_master_quick_command(to_unsigned(tb_req.bfm_addr, 7), "BFM master expects a NACK", i2c_if, C_WRITE_BIT, false, RELEASE_LINE_AFTER_TRANSFER, ERROR, C_SCOPE, shared_msg_id_panel, v_config);
      end case;

      tb_rsp.bfm_done <= tb_rsp.bfm_done + 1;
    end loop;
  end process p_i2c_bfm;

  -----------------------------------------------------------------------------
  -- Clock stretching by the bench
  -----------------------------------------------------------------------------
  p_stretch : process
  begin
    i2c_if.scl <= 'Z';

    loop
      wait on tb_req.stretch_req;

      for i in 1 to tb_req.stretch_fall loop
        wait until to_x01(i2c_if.scl) = '1';
        wait until to_x01(i2c_if.scl) = '0';
      end loop;

      i2c_if.scl          <= '0';
      wait for tb_req.stretch_time;
      i2c_if.scl          <= 'Z';
      tb_rsp.stretch_done <= tb_rsp.stretch_done + 1;
    end loop;
  end process p_stretch;

  -----------------------------------------------------------------------------
  -- SCL monitor
  -----------------------------------------------------------------------------
  p_scl_monitor : process
    variable v_rise       : time    := 0 ns;
    variable v_rise_valid : boolean := false;
    variable v_period_min : time    := 1 sec;
    variable v_high_min   : time    := 1 sec;
  begin
    wait on i2c_if.scl, tb_req.scl_mon_clear;

    if tb_req.scl_mon_clear'event
    then
      v_rise_valid := false;
      v_period_min := 1 sec;
      v_high_min   := 1 sec;
    elsif i2c_if.scl'event
    then
      if (to_x01(i2c_if.scl) = '1' and to_x01(i2c_if.scl'last_value) = '0')
      then
        if v_rise_valid and (now - v_rise) < v_period_min
        then
          v_period_min := now - v_rise;
        end if;
        v_rise       := now;
        v_rise_valid := true;
      elsif (to_x01(i2c_if.scl) = '0' and to_x01(i2c_if.scl'last_value) = '1')
      then
        if v_rise_valid and (now - v_rise) < v_high_min
        then
          v_high_min   := now - v_rise;
        end if;
      end if;
    end if;

    tb_rsp.scl_period_min <= v_period_min;
    tb_rsp.scl_high_min   <= v_high_min;
  end process p_scl_monitor;

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  p_sequencer : process
  begin
    log(ID_LOG_HDR, "TESTS_LIST : " & TESTS_LIST, C_SCOPE);

    -- Every name is checked before the first scenario
    for i in 1 to list_length(TESTS_LIST) loop
      if not list_contains(C_TESTS, list_item(TESTS_LIST, i))
      then
        alert(TB_ERROR, "Unknown test """ & list_item(TESTS_LIST, i) & """ (tests : " & C_TESTS & ")", C_SCOPE);
      end if;
    end loop;

    for i in 1 to list_length(TESTS_LIST) loop
      -- Reset pulse, bus inactive (the I2C BFM and the bench processes are
      -- idle at the end of each scenario) : each scenario starts from reset
      sbi_if <= init_sbi_if_signals(I2C_ADDR_WIDTH, I2C_DATA_WIDTH);
      do_reset(clk_i, arst_b_i);

      log(ID_LOG_HDR, "TEST " & integer'image(i) & "/" & integer'image(list_length(TESTS_LIST)) & " : " & list_item(TESTS_LIST, i), C_SCOPE);
      run_test(list_item(TESTS_LIST, i), clk_i, sbi_if, tb_req, tb_rsp, i2c_if.scl, scl_oe_o, sda_oe_o);
    end loop;

    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process p_sequencer;

end sim;
