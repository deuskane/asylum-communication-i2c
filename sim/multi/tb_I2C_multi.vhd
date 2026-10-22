-------------------------------------------------------------------------------
-- Title      : tb_I2C_multi
-- Project    : I2C
-------------------------------------------------------------------------------
-- File       : tb_I2C_multi.vhd
-- Author     : mrosiere
-------------------------------------------------------------------------------
-- Description: UVVM self-checking testbench with several sbi_I2C on the
--              same I2C bus (open drain, pull-up) :
--              * I2C0 : master (MASTER_ENABLE = true , SLAVE_ENABLE = false)
--              * I2Ck : slave  (MASTER_ENABLE = false, SLAVE_ENABLE = true),
--                       k = 1 to NB_SLAVE, address 0x10 + k
--              The CSR of all the instances are accessed with one SBI BFM :
--              the 2 MSB of the SBI address select the instance.
--              1. the master writes to each slave (only the addressed slave
--                 receives the bytes)
--              2. the master reads from each slave
--              3. write to a slave + repeated START + read from an other
--                 slave
--              4. read from a slave with an empty TX FIFO : clock stretching
--                 by the slave until the software writes the bytes
--              5. write to an absent address : NACK, no slave addressed
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

library asylum;
use     asylum.sbi_pkg.all;
use     asylum.i2c_pkg.all;
use     asylum.I2C_csr_pkg.all;

entity tb_I2C_multi is
  generic (
    NB_SLAVE : positive := 3                          -- Number of slave instances (1 to 3)
    );
end tb_I2C_multi;

architecture sim of tb_I2C_multi is

  constant C_SCOPE            : string   := "TB_I2C_MULTI";
  constant C_CLK_PERIOD       : time     := 20 ns;
  constant C_RATIO            : natural  := 4;        -- Prescaler of all the instances
  constant C_NB_INST          : positive := NB_SLAVE+1;
  constant C_SEL_WIDTH        : natural  := 2;        -- SBI address bits selecting the instance
  constant C_ADDR_WIDTH       : natural  := C_SEL_WIDTH+I2C_ADDR_WIDTH;
  constant C_ADDR_SLAVE_BASE  : natural  := 16#10#;   -- Address of the slave I2Ck : 0x10 + k
  constant C_ADDR_NONE        : natural  := 16#20#;   -- Address without slave

  type     slv8_array_t is array (natural range <>) of std_logic_vector(8-1 downto 0);

  signal   clk_i              : std_logic := '0';
  signal   clk_ena            : boolean   := true;
  signal   arst_b_i           : std_logic := '0';

  -- SBI : one BFM, the instance is selected by the MSB of the address
  signal   sbi_if             : t_sbi_if(addr (C_ADDR_WIDTH-1 downto 0),
                                         wdata(I2C_DATA_WIDTH-1 downto 0),
                                         rdata(I2C_DATA_WIDTH-1 downto 0));
  signal   sbi_sel            : natural range 0 to 2**C_SEL_WIDTH-1;
  signal   inst_ready         : std_logic_vector(0 to 2**C_SEL_WIDTH-1);
  signal   inst_rdata         : slv8_array_t    (0 to 2**C_SEL_WIDTH-1);

  -- I2C bus (open drain with pull-up)
  signal   i2c_scl            : std_logic;
  signal   i2c_sda            : std_logic;
  signal   i2c_scl_in         : std_logic;
  signal   i2c_sda_in         : std_logic;
  signal   scl_oe             : std_logic_vector(0 to C_NB_INST-1);
  signal   sda_oe             : std_logic_vector(0 to C_NB_INST-1);

  -- Data patterns
  function pattern(seed : natural; i : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned((seed*37 + i*53 + 16#5A#) mod 256, 8));
  end function;

  -- 7-bit address of the slave I2Ck
  function slave_addr(k : natural) return natural is
  begin
    return C_ADDR_SLAVE_BASE + k;
  end function;

begin

  assert NB_SLAVE <= 2**C_SEL_WIDTH-1
    report "NB_SLAVE must be lower than " & integer'image(2**C_SEL_WIDTH)
    severity failure;

  clock_generator(clk_i, clk_ena, C_CLK_PERIOD, "TB Clock");

  -----------------------------------------------------------------------------
  -- SBI : instance selection and read back
  -----------------------------------------------------------------------------
  sbi_sel                                 <= to_integer(sbi_if.addr(C_ADDR_WIDTH-1 downto I2C_ADDR_WIDTH));
  sbi_if.ready                            <= inst_ready(sbi_sel);
  sbi_if.rdata(I2C_DATA_WIDTH-1 downto 0) <= inst_rdata(sbi_sel);

  -- No instance : always ready, read 0
  gen_none : for k in C_NB_INST to 2**C_SEL_WIDTH-1 generate
    inst_ready(k) <= '1';
    inst_rdata(k) <= (others => '0');
  end generate gen_none;

  -----------------------------------------------------------------------------
  -- DUT : I2C0 master, I2C1 to I2C<NB_SLAVE> slaves
  -----------------------------------------------------------------------------
  gen_inst : for k in 0 to C_NB_INST-1 generate
    signal sbi_ini : sbi_ini_t(addr (I2C_ADDR_WIDTH-1 downto 0),
                               wdata(I2C_DATA_WIDTH-1 downto 0));
    signal sbi_tgt : sbi_tgt_t(rdata(I2C_DATA_WIDTH-1 downto 0));
    signal scl_o   : std_logic;
    signal sda_o   : std_logic;
  begin
    sbi_ini.cs    <= sbi_if.cs when sbi_sel = k else '0';
    sbi_ini.re    <= sbi_if.rena;
    sbi_ini.we    <= sbi_if.wena;
    sbi_ini.addr  <= std_logic_vector(sbi_if.addr(I2C_ADDR_WIDTH-1 downto 0));
    sbi_ini.wdata <= sbi_if.wdata(I2C_DATA_WIDTH-1 downto 0);
    inst_ready(k) <= sbi_tgt.ready;
    inst_rdata(k) <= sbi_tgt.rdata;

    dut : sbi_I2C
      generic map (
        NAME                  => "I2C" & integer'image(k)
       ,USER_DEFINE_PRESCALER => true
       ,PRESCALER_RATIO       => x"7C"
       ,MASTER_ENABLE         => (k = 0)
       ,SLAVE_ENABLE          => (k /= 0)
       ,DEPTH_CMD             => 4
       ,DEPTH_TX              => 8
       ,DEPTH_RX              => 8
       ,FILENAME_CMD          => "dump_i2c" & integer'image(k) & "_cmd.txt"
       ,FILENAME_TX           => "dump_i2c" & integer'image(k) & "_tx.txt"
       ,FILENAME_RX           => "dump_i2c" & integer'image(k) & "_rx.txt"
      )
      port map (
        clk_i      => clk_i
       ,arst_b_i   => arst_b_i
       ,sbi_ini_i  => sbi_ini
       ,sbi_tgt_o  => sbi_tgt
       ,scl_i      => i2c_scl_in
       ,scl_o      => scl_o
       ,scl_oe_o   => scl_oe(k)
       ,sda_i      => i2c_sda_in
       ,sda_o      => sda_o
       ,sda_oe_o   => sda_oe(k)
      );

    -- Open drain pads
    i2c_scl <= scl_o when scl_oe(k) = '1' else 'Z';
    i2c_sda <= sda_o when sda_oe(k) = '1' else 'Z';
  end generate gen_inst;

  -- Pull-up
  i2c_scl    <= 'H';
  i2c_sda    <= 'H';

  i2c_scl_in <= to_x01(i2c_scl);
  i2c_sda_in <= to_x01(i2c_sda);

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  p_main : process
    variable v_sbi_config : t_sbi_bfm_config := C_SBI_BFM_CONFIG_DEFAULT;
    variable v_poll_panel : t_msg_id_panel   := C_MSG_ID_PANEL_DEFAULT;
    variable v_status     : std_logic_vector(7 downto 0);

    -- SBI address of the register addr of the instance inst
    function inst_addr(inst : natural; addr : unsigned) return unsigned is
    begin
      return to_unsigned(inst, C_SEL_WIDTH) & addr;
    end function;

    procedure write_reg(inst : natural; addr : unsigned; data : std_logic_vector; msg : string) is
    begin
      sbi_write(inst_addr(inst, addr), data, "I2C" & to_string(inst) & " : " & msg, clk_i, sbi_if, C_SCOPE, shared_msg_id_panel, v_sbi_config);
    end procedure;

    procedure check_reg(inst : natural; addr : unsigned; data : std_logic_vector; msg : string) is
    begin
      sbi_check(inst_addr(inst, addr), data, "I2C" & to_string(inst) & " : " & msg, clk_i, sbi_if, ERROR, C_SCOPE, shared_msg_id_panel, v_sbi_config);
    end procedure;

    -- Poll the status register of the instance until (status and mask) = value
    procedure wait_status(inst : natural; mask : std_logic_vector(7 downto 0); value : std_logic_vector(7 downto 0); msg : string) is
    begin
      for i in 1 to 100000 loop
        sbi_read(inst_addr(inst, I2C_STATUS), v_status, msg & " : poll status", clk_i, sbi_if, C_SCOPE, v_poll_panel, v_sbi_config);
        exit when (v_status and mask) = value;
      end loop;
      check_value(v_status and mask, value, ERROR, "I2C" & to_string(inst) & " : " & msg & " : status and 0x" & to_hstring(mask), C_SCOPE);
    end procedure;

    -- Prescaler and cfg (enable, slave address) of the instance
    procedure configure(inst : natural; addr : natural) is
      variable v_cfg : std_logic_vector(7 downto 0);
    begin
      v_cfg := std_logic_vector(to_unsigned(addr, 7)) & '1';
      write_reg(inst, I2C_PRESCALER, std_logic_vector(to_unsigned(C_RATIO, 8)), "prescaler " & to_string(C_RATIO));
      write_reg(inst, I2C_CFG      , v_cfg, "cfg 0x" & to_hstring(v_cfg));
      check_reg(inst, I2C_CFG      , v_cfg, "read back cfg");
    end procedure;

    -- Master command (I2C0) : op & stop & start
    procedure command(start : boolean; stop : boolean; op : std_logic_vector(1 downto 0); msg : string) is
      variable v_start : std_logic_vector(0 downto 0) := I2C_CMD_START_DISABLE;
      variable v_stop  : std_logic_vector(0 downto 0) := I2C_CMD_STOP_DISABLE;
    begin
      if start then v_start := I2C_CMD_START_ENABLE; end if;
      if stop  then v_stop  := I2C_CMD_STOP_ENABLE;  end if;
      write_reg(0, I2C_CMD, "0000" & op & v_stop & v_start, msg);
    end procedure;

    -- Master (I2C0) : START, address + W, bytes, STOP (if stop)
    procedure master_write(addr : natural; data : t_byte_array; stop : boolean; msg : string) is
    begin
      write_reg(0, I2C_DATA, std_logic_vector(to_unsigned(addr, 7)) & '0', msg & " : TX address + W");
      command(true, false, I2C_CMD_OP_WRITE, msg & " : command START + WRITE");
      for i in data'range loop
        write_reg(0, I2C_DATA, data(i), msg & " : TX byte " & to_string(i));
        command(false, stop and i = data'high, I2C_CMD_OP_WRITE, msg & " : command WRITE");
      end loop;
    end procedure;

    -- Master (I2C0) : (repeated) START, address + R, nb bytes (ACK except the last one), STOP
    procedure master_read(addr : natural; nb : natural; msg : string) is
    begin
      write_reg(0, I2C_DATA, std_logic_vector(to_unsigned(addr, 7)) & '1', msg & " : TX address + R");
      command(true, false, I2C_CMD_OP_WRITE, msg & " : command START + WRITE");
      for i in 0 to nb-2 loop
        command(false, false, I2C_CMD_OP_READ_ACK, msg & " : command READ_ACK");
      end loop;
      command(false, true, I2C_CMD_OP_READ_NACK, msg & " : command READ_NACK + STOP");
    end procedure;

    -- Check the bytes of the RX FIFO of the instance
    procedure check_rx(inst : natural; data : t_byte_array; msg : string) is
    begin
      for i in data'range loop
        check_reg(inst, I2C_DATA, data(i), msg & " : RX byte " & to_string(i));
      end loop;
    end procedure;

  begin
    v_sbi_config.max_wait_cycles := 100000;
    v_poll_panel(ID_BFM)         := DISABLED;

    sbi_if   <= init_sbi_if_signals(C_ADDR_WIDTH, I2C_DATA_WIDTH);
    arst_b_i <= '0';
    wait for 100 ns;
    arst_b_i <= '1';
    wait until rising_edge(clk_i);

    ------------------------------------------------
    log(ID_LOG_HDR, "Configuration : I2C0 master, I2C1 to I2C" & to_string(NB_SLAVE) & " slaves", C_SCOPE);
    ------------------------------------------------
    configure(0, 0);
    for k in 1 to NB_SLAVE loop
      configure(k, slave_addr(k));
    end loop;

    ------------------------------------------------
    log(ID_LOG_HDR, "1. The master writes to each slave", C_SCOPE);
    ------------------------------------------------
    for k in 1 to NB_SLAVE loop
      master_write(slave_addr(k), t_byte_array'(pattern(k, 0), pattern(k, 1)), true, "Write to I2C" & to_string(k));
      wait_status(0, x"07", x"00", "Write to I2C" & to_string(k) & " : not busy, ACK, bus free");
      check_rx(k, t_byte_array'(pattern(k, 0), pattern(k, 1)), "Write to I2C" & to_string(k));
      for j in 1 to NB_SLAVE loop
        wait_status(j, x"2C", x"20", "Write to I2C" & to_string(k) & " : bus free, not addressed, RX FIFO empty");
      end loop;
    end loop;

    ------------------------------------------------
    log(ID_LOG_HDR, "2. The master reads from each slave", C_SCOPE);
    ------------------------------------------------
    for k in 1 to NB_SLAVE loop
      for i in 0 to 2 loop
        write_reg(k, I2C_DATA, pattern(k+10, i), "Read from I2C" & to_string(k) & " : TX byte " & to_string(i));
      end loop;
      master_read(slave_addr(k), 3, "Read from I2C" & to_string(k));
      check_rx(0, t_byte_array'(pattern(k+10, 0), pattern(k+10, 1), pattern(k+10, 2)), "Read from I2C" & to_string(k));
      wait_status(0, x"07", x"00", "Read from I2C" & to_string(k) & " : not busy, ACK, bus free");
      wait_status(k, x"3C", x"30", "Read from I2C" & to_string(k) & " : bus free, not addressed, last direction read, RX FIFO empty");
    end loop;

    ------------------------------------------------
    log(ID_LOG_HDR, "3. Write to I2C1 + repeated START + read from I2C" & to_string(NB_SLAVE), C_SCOPE);
    ------------------------------------------------
    write_reg(NB_SLAVE, I2C_DATA, x"C3", "Register read : TX byte");
    master_write(slave_addr(1), t_byte_array'(0 => x"5A"), false, "Register read : write I2C1");
    wait_status(0, x"07", x"04", "Register read : write done, ACK, bus kept by the master");
    wait_status(1, x"18", x"08", "Register read : addressed, master writes");
    if NB_SLAVE > 1
    then
      wait_status(NB_SLAVE, x"08", x"00", "Register read : not addressed");
    end if;
    master_read(slave_addr(NB_SLAVE), 1, "Register read : repeated START, read I2C" & to_string(NB_SLAVE));
    check_rx(0, t_byte_array'(0 => x"C3"), "Register read");
    wait_status(0, x"07", x"00", "Register read : not busy, ACK, bus free");
    check_rx(1, t_byte_array'(0 => x"5A"), "Register read");
    wait_status(1, x"08", x"00", "Register read : not addressed after the repeated START");
    wait_status(NB_SLAVE, x"18", x"10", "Register read : not addressed after the STOP, last direction read");

    ------------------------------------------------
    log(ID_LOG_HDR, "4. Read from I2C" & to_string(NB_SLAVE) & " with an empty TX FIFO : clock stretching", C_SCOPE);
    ------------------------------------------------
    master_read(slave_addr(NB_SLAVE), 2, "Slave stretching");
    wait_status(NB_SLAVE, x"18", x"18", "Slave stretching : addressed, master reads");
    wait for 20 us;
    check_value(i2c_scl         , '0', MATCH_STD, ERROR, "Slave stretching : SCL held low", C_SCOPE);
    check_value(scl_oe(NB_SLAVE), '1', ERROR, "Slave stretching : I2C" & to_string(NB_SLAVE) & " pulls SCL low", C_SCOPE);
    check_value(scl_oe(0)       , '0', ERROR, "Slave stretching : the master releases SCL", C_SCOPE);
    wait_status(0, x"01", x"01", "Slave stretching : master busy");
    write_reg(NB_SLAVE, I2C_DATA, x"9A", "Slave stretching : TX byte 0");
    write_reg(NB_SLAVE, I2C_DATA, x"BC", "Slave stretching : TX byte 1");
    check_rx(0, t_byte_array'(x"9A", x"BC"), "Slave stretching");
    wait_status(0, x"07", x"00", "Slave stretching : not busy, ACK, bus free");

    ------------------------------------------------
    log(ID_LOG_HDR, "5. Write to an absent address : NACK", C_SCOPE);
    ------------------------------------------------
    master_write(C_ADDR_NONE, t_byte_array'(0 => x"55"), true, "Absent address");
    wait_status(0, x"05", x"00", "Absent address : not busy, bus free");
    check_reg(0, I2C_STATUS, x"22", "Absent address : nack = 1, RX FIFO empty");
    for k in 1 to NB_SLAVE loop
      wait_status(k, x"2C", x"20", "Absent address : not addressed, RX FIFO empty");
    end loop;

    log(ID_LOG_HDR, "Simulation Finished", C_SCOPE);
    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process p_main;

end sim;
