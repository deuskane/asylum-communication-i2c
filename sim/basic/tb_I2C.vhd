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
--              * DUT master / BFM slave : write, read, write + repeated START
--                + read, NACK of an absent slave, clock stretching by the
--                bench, SCL period and high phase for 2 prescalers
--              * BFM master / DUT slave : write, read, read with an empty TX
--                FIFO (clock stretching by the DUT), write + repeated START +
--                read, wrong address, slave disabled, I2C disabled
--              Plus : reset values of the registers.
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-22  1.0      mrosiere Created
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
use     asylum.i2c_pkg.all;
use     asylum.I2C_csr_pkg.all;

entity tb_I2C is
end tb_I2C;

architecture sim of tb_I2C is

  constant C_SCOPE            : string  := "TB_I2C";
  constant C_CLK_PERIOD       : time    := 20 ns;
  constant C_PRESCALER_RST    : std_logic_vector(7 downto 0) := x"7C";

  constant C_ADDR_BFM         : natural := 16#50#;  -- Address of the BFM slave
  constant C_ADDR_NONE        : natural := 16#51#;  -- Address without slave
  constant C_ADDR_DUT         : natural := 16#3A#;  -- Address of the DUT slave
  constant C_BIT_TIME_MASTER  : time    := 1 us;    -- SCL period of the BFM master

  -- Bits of the status register
  constant C_STATUS_BUSY      : natural := 0;
  constant C_STATUS_NACK      : natural := 1;
  constant C_STATUS_BUS_BUSY  : natural := 2;
  constant C_STATUS_ADDRESSED : natural := 3;
  constant C_STATUS_READ      : natural := 4;
  constant C_STATUS_RX_EMPTY  : natural := 5;

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

  -- I2C BFM process : operation requested by the sequencer
  type     bfm_op_t is (BFM_SLAVE_CHECK,              -- BFM slave receives bfm_wdata
                        BFM_SLAVE_TRANSMIT,           -- BFM slave transmits bfm_rdata
                        BFM_SLAVE_CHECK_TRANSMIT,     -- both, with a repeated START between
                        BFM_MASTER_TRANSMIT,          -- BFM master writes bfm_wdata
                        BFM_MASTER_CHECK,             -- BFM master reads and checks bfm_rdata
                        BFM_MASTER_TRANSMIT_CHECK,    -- both, with a repeated START between
                        BFM_MASTER_QUICK_NACK);       -- BFM master sends the address, expects a NACK
  signal   bfm_op             : bfm_op_t := BFM_SLAVE_CHECK;
  signal   bfm_addr           : natural  := 0;
  signal   bfm_bit_time       : time     := 1 us;
  signal   bfm_wdata          : t_byte_array(0 to 7) := (others => (others => '0'));
  signal   bfm_wlen           : natural  := 0;
  signal   bfm_rdata          : t_byte_array(0 to 7) := (others => (others => '0'));
  signal   bfm_rlen           : natural  := 0;
  signal   bfm_req            : natural  := 0;
  signal   bfm_done           : natural  := 0;

  -- Clock stretching by the bench : SCL held low after a falling edge
  signal   stretch_fall       : natural  := 1;       -- Number of falling edges of SCL to wait
  signal   stretch_time       : time     := 0 ns;    -- Duration of the stretching
  signal   stretch_req        : natural  := 0;
  signal   stretch_done       : natural  := 0;

  -- SCL monitor : minimum SCL period and high phase since the last clear
  signal   scl_mon_clear      : boolean  := false;
  signal   scl_period_min     : time     := 1 sec;
  signal   scl_high_min       : time     := 1 sec;

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
      wait on bfm_req;

      -- The timings of the START / STOP conditions are one bit time : larger
      -- than the ones of the DUT master, and long enough for the
      -- synchronizers of the DUT
      v_config                                 := C_I2C_BFM_CONFIG_DEFAULT;
      v_config.i2c_bit_time                    := bfm_bit_time;
      v_config.master_sda_to_scl               := bfm_bit_time;
      v_config.master_scl_to_sda               := bfm_bit_time;
      v_config.master_stop_condition_hold_time := bfm_bit_time;
      v_config.max_wait_scl_change             := 100 us;
      v_config.max_wait_sda_change             := 100 us;
      v_config.max_wait_scl_change_severity    := ERROR;
      v_config.max_wait_sda_change_severity    := ERROR;
      v_config.i2c_bit_time_severity           := ERROR;
      v_config.acknowledge_severity            := ERROR;
      v_config.slave_mode_address              := to_unsigned(bfm_addr, 10);
      v_config.slave_mode_address_severity     := ERROR;
      v_config.slave_rw_bit_severity           := ERROR;

      case bfm_op is
        when BFM_SLAVE_CHECK =>
          i2c_slave_check   (bfm_wdata(0 to bfm_wlen-1), "BFM slave receives", i2c_if, C_WRITE_BIT, ERROR, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_SLAVE_TRANSMIT =>
          i2c_slave_transmit(bfm_rdata(0 to bfm_rlen-1), "BFM slave transmits", i2c_if, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_SLAVE_CHECK_TRANSMIT =>
          i2c_slave_check   (bfm_wdata(0 to bfm_wlen-1), "BFM slave receives", i2c_if, C_WRITE_BIT, ERROR, C_SCOPE, shared_msg_id_panel, v_config);
          i2c_slave_transmit(bfm_rdata(0 to bfm_rlen-1), "BFM slave transmits after a repeated START", i2c_if, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_MASTER_TRANSMIT =>
          i2c_master_transmit(to_unsigned(bfm_addr, 7), bfm_wdata(0 to bfm_wlen-1), "BFM master writes", i2c_if, RELEASE_LINE_AFTER_TRANSFER, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_MASTER_CHECK =>
          i2c_master_check   (to_unsigned(bfm_addr, 7), bfm_rdata(0 to bfm_rlen-1), "BFM master reads", i2c_if, RELEASE_LINE_AFTER_TRANSFER, ERROR, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_MASTER_TRANSMIT_CHECK =>
          i2c_master_transmit(to_unsigned(bfm_addr, 7), bfm_wdata(0 to bfm_wlen-1), "BFM master writes", i2c_if, HOLD_LINE_AFTER_TRANSFER, C_SCOPE, shared_msg_id_panel, v_config);
          i2c_master_check   (to_unsigned(bfm_addr, 7), bfm_rdata(0 to bfm_rlen-1), "BFM master reads after a repeated START", i2c_if, RELEASE_LINE_AFTER_TRANSFER, ERROR, C_SCOPE, shared_msg_id_panel, v_config);

        when BFM_MASTER_QUICK_NACK =>
          i2c_master_quick_command(to_unsigned(bfm_addr, 7), "BFM master expects a NACK", i2c_if, C_WRITE_BIT, false, RELEASE_LINE_AFTER_TRANSFER, ERROR, C_SCOPE, shared_msg_id_panel, v_config);
      end case;

      bfm_done <= bfm_done + 1;
    end loop;
  end process p_i2c_bfm;

  -----------------------------------------------------------------------------
  -- Clock stretching by the bench
  -----------------------------------------------------------------------------
  p_stretch : process
  begin
    i2c_if.scl <= 'Z';

    loop
      wait on stretch_req;

      for i in 1 to stretch_fall loop
        wait until to_x01(i2c_if.scl) = '1';
        wait until to_x01(i2c_if.scl) = '0';
      end loop;

      i2c_if.scl   <= '0';
      wait for stretch_time;
      i2c_if.scl   <= 'Z';
      stretch_done <= stretch_done + 1;
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
    wait on i2c_if.scl, scl_mon_clear;

    if scl_mon_clear'event
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

    scl_period_min <= v_period_min;
    scl_high_min   <= v_high_min;
  end process p_scl_monitor;

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  p_main : process
    variable v_sbi_config : t_sbi_bfm_config := C_SBI_BFM_CONFIG_DEFAULT;
    variable v_poll_panel : t_msg_id_panel   := C_MSG_ID_PANEL_DEFAULT;
    variable v_ratio      : natural;
    variable v_status     : std_logic_vector(7 downto 0);

    procedure write_reg(addr : unsigned; data : std_logic_vector; msg : string) is
    begin
      sbi_write(addr, data, msg, clk_i, sbi_if, C_SCOPE, shared_msg_id_panel, v_sbi_config);
    end procedure;

    procedure check_reg(addr : unsigned; data : std_logic_vector; msg : string) is
    begin
      sbi_check(addr, data, msg, clk_i, sbi_if, ERROR, C_SCOPE, shared_msg_id_panel, v_sbi_config);
    end procedure;

    -- Poll the status register until (status and mask) = value
    procedure wait_status(mask : std_logic_vector(7 downto 0); value : std_logic_vector(7 downto 0); msg : string) is
    begin
      for i in 1 to 100000 loop
        sbi_read(I2C_STATUS, v_status, msg & " : poll status", clk_i, sbi_if, C_SCOPE, v_poll_panel, v_sbi_config);
        exit when (v_status and mask) = value;
      end loop;
      check_value(v_status and mask, value, ERROR, msg & " : status and 0x" & to_hstring(mask), C_SCOPE);
    end procedure;

    -- Configuration of the DUT : prescaler ratio and cfg (enable, slave address)
    procedure configure(ratio : natural; slave_addr : natural; enable : std_logic; msg : string) is
      variable v_cfg : std_logic_vector(7 downto 0);
    begin
      v_ratio := ratio;
      v_cfg   := std_logic_vector(to_unsigned(slave_addr, 7)) & enable;
      write_reg(I2C_CFG      , x"00", msg & " : disable I2C (i2c_core reset)");
      write_reg(I2C_PRESCALER, std_logic_vector(to_unsigned(ratio, 8)), msg & " : prescaler " & to_string(ratio));
      write_reg(I2C_CFG      , v_cfg, msg & " : cfg 0x" & to_hstring(v_cfg));
      check_reg(I2C_PRESCALER, std_logic_vector(to_unsigned(ratio, 8)), msg & " : read back prescaler");
      check_reg(I2C_CFG      , v_cfg, msg & " : read back cfg");
    end procedure;

    -- Master command : op & stop & start
    procedure command(start : boolean; stop : boolean; op : std_logic_vector(1 downto 0); msg : string) is
      variable v_start : std_logic_vector(0 downto 0) := I2C_CMD_START_DISABLE;
      variable v_stop  : std_logic_vector(0 downto 0) := I2C_CMD_STOP_DISABLE;
    begin
      if start then v_start := I2C_CMD_START_ENABLE; end if;
      if stop  then v_stop  := I2C_CMD_STOP_ENABLE;  end if;
      write_reg(I2C_CMD, "0000" & op & v_stop & v_start, msg);
    end procedure;

    -- DUT master : START, address + W, bytes, STOP (if stop)
    procedure master_write(addr : natural; data : t_byte_array; stop : boolean; msg : string) is
    begin
      write_reg(I2C_DATA, std_logic_vector(to_unsigned(addr, 7)) & '0', msg & " : TX address + W");
      command(true, false, I2C_CMD_OP_WRITE, msg & " : command START + WRITE");
      for i in data'range loop
        write_reg(I2C_DATA, data(i), msg & " : TX byte " & to_string(i));
        command(false, stop and i = data'high, I2C_CMD_OP_WRITE, msg & " : command WRITE");
      end loop;
    end procedure;

    -- DUT master : (repeated) START, address + R, nb bytes (ACK except the last one), STOP
    procedure master_read(addr : natural; nb : natural; msg : string) is
    begin
      write_reg(I2C_DATA, std_logic_vector(to_unsigned(addr, 7)) & '1', msg & " : TX address + R");
      command(true, false, I2C_CMD_OP_WRITE, msg & " : command START + WRITE");
      for i in 0 to nb-2 loop
        command(false, false, I2C_CMD_OP_READ_ACK, msg & " : command READ_ACK");
      end loop;
      command(false, true, I2C_CMD_OP_READ_NACK, msg & " : command READ_NACK + STOP");
    end procedure;

    -- Check the bytes of the RX FIFO
    procedure check_rx(data : t_byte_array; msg : string) is
    begin
      for i in data'range loop
        check_reg(I2C_DATA, data(i), msg & " : RX byte " & to_string(i));
      end loop;
    end procedure;

    -- Request an operation to the I2C BFM process
    procedure bfm_start(op : bfm_op_t; addr : natural; bit_time : time; wdata : t_byte_array; rdata : t_byte_array) is
    begin
      bfm_op       <= op;
      bfm_addr     <= addr;
      bfm_bit_time <= bit_time;
      bfm_wlen     <= wdata'length;
      bfm_rlen     <= rdata'length;
      for i in 0 to wdata'length-1 loop
        bfm_wdata(i) <= wdata(wdata'low+i);
      end loop;
      for i in 0 to rdata'length-1 loop
        bfm_rdata(i) <= rdata(rdata'low+i);
      end loop;
      bfm_req      <= bfm_req + 1;
      wait for 0 ns;
    end procedure;

    -- Wait the end of the operation of the I2C BFM process
    procedure bfm_wait(msg : string) is
    begin
      if bfm_done /= bfm_req
      then
        wait until bfm_done = bfm_req for 2 ms;
      end if;
      check_value(bfm_done, bfm_req, ERROR, msg & " : end of the I2C BFM operation", C_SCOPE);
    end procedure;

    -- Bit time of the DUT master for the BFM slave (without the synchronization of SCL)
    impure function bit_time_dut return time is
    begin
      return 4*(v_ratio+1)*C_CLK_PERIOD;
    end function;

    -- Check the SCL period and high phase of the DUT master since the last clear
    procedure check_scl(msg : string) is
    begin
      check_value(scl_period_min, (4*(v_ratio+1)+2)*C_CLK_PERIOD, ERROR, msg & " : SCL period = 4*(ratio+1)+2 clock cycles", C_SCOPE);
      check_value(scl_high_min  , (2*(v_ratio+1)+2)*C_CLK_PERIOD, ERROR, msg & " : SCL high phase >= 2*(ratio+1)+2 clock cycles", C_SCOPE);
    end procedure;

    constant C_NONE : t_byte_array(0 to -1) := (others => (others => '0'));

  begin
    v_sbi_config.max_wait_cycles := 100000;
    v_poll_panel(ID_BFM)         := DISABLED;

    sbi_if   <= init_sbi_if_signals(I2C_ADDR_WIDTH, I2C_DATA_WIDTH);
    arst_b_i <= '0';
    wait for 100 ns;
    arst_b_i <= '1';
    wait until rising_edge(clk_i);

    log(ID_SEQUENCER, "Reset released, starting I2C basic test", C_SCOPE);

    ------------------------------------------------
    log(ID_LOG_HDR, "1. Reset values", C_SCOPE);
    ------------------------------------------------
    check_reg(I2C_CFG      , x"00"          , "Reset value cfg");
    check_reg(I2C_PRESCALER, C_PRESCALER_RST, "Reset value prescaler (PRESCALER_RATIO)");
    check_reg(I2C_STATUS   , x"20"          , "Reset value status (rx_empty)");
    check_value(scl_oe_o, '0', ERROR, "I2C disabled : SCL released", C_SCOPE);
    check_value(sda_oe_o, '0', ERROR, "I2C disabled : SDA released", C_SCOPE);

    ------------------------------------------------
    log(ID_LOG_HDR, "2. DUT master write to the BFM slave", C_SCOPE);
    ------------------------------------------------
    configure(4, 0, '1', "Master");
    scl_mon_clear <= not scl_mon_clear;
    bfm_start(BFM_SLAVE_CHECK, C_ADDR_BFM, bit_time_dut, t_byte_array'(x"A5", x"3C", x"0F"), C_NONE);
    master_write(C_ADDR_BFM, t_byte_array'(x"A5", x"3C", x"0F"), true, "Master write");
    bfm_wait("Master write");
    wait_status(x"07", x"00", "Master write : not busy, ACK, bus free");
    check_scl("Master write");

    ------------------------------------------------
    log(ID_LOG_HDR, "3. DUT master read from the BFM slave", C_SCOPE);
    ------------------------------------------------
    bfm_start(BFM_SLAVE_TRANSMIT, C_ADDR_BFM, bit_time_dut, C_NONE, t_byte_array'(x"11", x"22", x"33"));
    master_read(C_ADDR_BFM, 3, "Master read");
    check_rx(t_byte_array'(x"11", x"22", x"33"), "Master read");
    bfm_wait("Master read");
    wait_status(x"27", x"20", "Master read : not busy, ACK, bus free, RX FIFO empty");

    ------------------------------------------------
    log(ID_LOG_HDR, "4. DUT master write + repeated START + read (register read)", C_SCOPE);
    ------------------------------------------------
    bfm_start(BFM_SLAVE_CHECK_TRANSMIT, C_ADDR_BFM, bit_time_dut, t_byte_array'(0 => x"07"), t_byte_array'(x"5A", x"C3"));
    master_write(C_ADDR_BFM, t_byte_array'(0 => x"07"), false, "Register read : write register address");
    master_read (C_ADDR_BFM, 2, "Register read : repeated START, read");
    check_rx(t_byte_array'(x"5A", x"C3"), "Register read");
    bfm_wait("Register read");
    wait_status(x"07", x"00", "Register read : not busy, ACK, bus free");

    ------------------------------------------------
    log(ID_LOG_HDR, "5. DUT master write to an absent slave : NACK", C_SCOPE);
    ------------------------------------------------
    master_write(C_ADDR_NONE, t_byte_array'(0 => x"55"), true, "Absent slave");
    wait_status(x"05", x"00", "Absent slave : not busy, bus free");
    check_reg(I2C_STATUS, x"22", "Absent slave : status nack = 1");

    -- A new transfer clears the NACK status
    bfm_start(BFM_SLAVE_CHECK, C_ADDR_BFM, bit_time_dut, t_byte_array'(0 => x"66"), C_NONE);
    master_write(C_ADDR_BFM, t_byte_array'(0 => x"66"), true, "Write after NACK");
    bfm_wait("Write after NACK");
    wait_status(x"07", x"00", "Write after NACK : NACK status cleared by the START");

    ------------------------------------------------
    log(ID_LOG_HDR, "6. DUT master write with SCL stretched by the bench", C_SCOPE);
    ------------------------------------------------
    scl_mon_clear <= not scl_mon_clear;
    stretch_fall  <= 5;
    stretch_time  <= 3 us;
    stretch_req   <= stretch_req + 1;
    bfm_start(BFM_SLAVE_CHECK, C_ADDR_BFM, bit_time_dut, t_byte_array'(x"C0", x"DE"), C_NONE);
    master_write(C_ADDR_BFM, t_byte_array'(x"C0", x"DE"), true, "Stretched write");
    bfm_wait("Stretched write");
    wait_status(x"07", x"00", "Stretched write : not busy, ACK, bus free");
    check_value(stretch_done, stretch_req, ERROR, "Stretched write : SCL stretched by the bench", C_SCOPE);
    check_scl("Stretched write : the high phase restarts after the stretching");

    ------------------------------------------------
    log(ID_LOG_HDR, "7. DUT master with an other prescaler", C_SCOPE);
    ------------------------------------------------
    configure(9, 0, '1', "Prescaler 9");
    scl_mon_clear <= not scl_mon_clear;
    bfm_start(BFM_SLAVE_CHECK, C_ADDR_BFM, bit_time_dut, t_byte_array'(x"81", x"7E"), C_NONE);
    master_write(C_ADDR_BFM, t_byte_array'(x"81", x"7E"), true, "Prescaler 9");
    bfm_wait("Prescaler 9");
    wait_status(x"07", x"00", "Prescaler 9 : not busy, ACK, bus free");
    check_scl("Prescaler 9");

    ------------------------------------------------
    log(ID_LOG_HDR, "8. BFM master write to the DUT slave", C_SCOPE);
    ------------------------------------------------
    configure(4, C_ADDR_DUT, '1', "Slave");
    bfm_start(BFM_MASTER_TRANSMIT, C_ADDR_DUT, C_BIT_TIME_MASTER, t_byte_array'(x"DE", x"AD", x"BE", x"EF"), C_NONE);
    wait_status(x"18", x"08", "Slave write : addressed, master writes");
    bfm_wait("Slave write");
    wait_status(x"3C", x"00", "Slave write : STOP, bus free, RX FIFO not empty");
    check_rx(t_byte_array'(x"DE", x"AD", x"BE", x"EF"), "Slave write");
    check_reg(I2C_STATUS, x"20", "Slave write : RX FIFO empty");

    ------------------------------------------------
    log(ID_LOG_HDR, "9. BFM master read from the DUT slave", C_SCOPE);
    ------------------------------------------------
    write_reg(I2C_DATA, x"12", "Slave read : TX byte 0");
    write_reg(I2C_DATA, x"34", "Slave read : TX byte 1");
    write_reg(I2C_DATA, x"56", "Slave read : TX byte 2");
    bfm_start(BFM_MASTER_CHECK, C_ADDR_DUT, C_BIT_TIME_MASTER, C_NONE, t_byte_array'(x"12", x"34", x"56"));
    wait_status(x"18", x"18", "Slave read : addressed, master reads");
    bfm_wait("Slave read");
    wait_status(x"3C", x"30", "Slave read : STOP, bus free, last direction read");

    ------------------------------------------------
    log(ID_LOG_HDR, "10. BFM master read from the DUT slave, TX FIFO empty : clock stretching", C_SCOPE);
    ------------------------------------------------
    bfm_start(BFM_MASTER_CHECK, C_ADDR_DUT, C_BIT_TIME_MASTER, C_NONE, t_byte_array'(x"9A", x"BC"));
    wait_status(x"18", x"18", "Slave stretching : addressed, master reads");
    wait for 10*C_BIT_TIME_MASTER;
    check_value(i2c_if.scl, '0', MATCH_STD, ERROR, "Slave stretching : SCL held low by the DUT", C_SCOPE);
    check_value(scl_oe_o  , '1', ERROR, "Slave stretching : DUT pulls SCL low", C_SCOPE);
    write_reg(I2C_DATA, x"9A", "Slave stretching : TX byte 0");
    write_reg(I2C_DATA, x"BC", "Slave stretching : TX byte 1");
    bfm_wait("Slave stretching");
    wait_status(x"3C", x"30", "Slave stretching : STOP, bus free");

    ------------------------------------------------
    log(ID_LOG_HDR, "11. BFM master write + repeated START + read from the DUT slave", C_SCOPE);
    ------------------------------------------------
    write_reg(I2C_DATA, x"77", "Slave register read : TX byte");
    bfm_start(BFM_MASTER_TRANSMIT_CHECK, C_ADDR_DUT, C_BIT_TIME_MASTER, t_byte_array'(0 => x"07"), t_byte_array'(0 => x"77"));
    bfm_wait("Slave register read");
    wait_status(x"3C", x"10", "Slave register read : STOP, bus free, RX FIFO not empty");
    check_rx(t_byte_array'(0 => x"07"), "Slave register read");

    ------------------------------------------------
    log(ID_LOG_HDR, "12. Wrong address, slave disabled, I2C disabled : NACK", C_SCOPE);
    ------------------------------------------------
    bfm_start(BFM_MASTER_QUICK_NACK, C_ADDR_DUT+1, C_BIT_TIME_MASTER, C_NONE, C_NONE);
    bfm_wait("Wrong address");
    check_reg(I2C_STATUS, x"30", "Wrong address : not addressed, RX FIFO empty");

    configure(4, 0, '1', "Slave disabled");
    bfm_start(BFM_MASTER_QUICK_NACK, C_ADDR_DUT, C_BIT_TIME_MASTER, C_NONE, C_NONE);
    bfm_wait("Slave disabled");
    check_reg(I2C_STATUS, x"20", "Slave disabled : not addressed, RX FIFO empty");

    configure(4, C_ADDR_DUT, '0', "I2C disabled");
    bfm_start(BFM_MASTER_QUICK_NACK, C_ADDR_DUT, C_BIT_TIME_MASTER, C_NONE, C_NONE);
    bfm_wait("I2C disabled");
    check_reg(I2C_STATUS, x"20", "I2C disabled : not addressed, RX FIFO empty");
    check_value(scl_oe_o, '0', ERROR, "I2C disabled : SCL released", C_SCOPE);
    check_value(sda_oe_o, '0', ERROR, "I2C disabled : SDA released", C_SCOPE);

    log(ID_LOG_HDR, "Simulation Finished", C_SCOPE);
    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process p_main;

end sim;
