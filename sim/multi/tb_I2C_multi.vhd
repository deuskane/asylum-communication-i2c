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
--              TESTS_LIST : scenarios run in sequence, separated by ','
--                           (tb_I2C_multi_tests_pkg), each one after a
--                           reset pulse ; "" : build and elaboration only
--              NB_SLAVE   : number of slave instances (1 to 3)
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-22  1.0      mrosiere Created
-- 2026-11-20  1.1      mrosiere TESTS_LIST, scenarios in
--                               tb_I2C_multi_transfers_pkg, helpers in
--                               tb_I2C_multi_bfm_pkg, reset pulse before each
--                               scenario
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
use     asylum.string_pkg.all;
use     asylum.i2c_pkg.all;
use     asylum.I2C_csr_pkg.all;

library work;
use     work.tb_I2C_multi_bfm_pkg.all;
use     work.tb_I2C_multi_tests_pkg.all;

entity tb_I2C_multi is
  generic (
    TESTS_LIST : string   := ""                       -- Scenarios, e.g. "write,stretch"
   ;NB_SLAVE   : positive := 3                        -- Number of slave instances (1 to 3)
    );
end tb_I2C_multi;

architecture sim of tb_I2C_multi is

  constant C_SCOPE            : string   := "TB_I2C_MULTI";
  constant C_NB_INST          : positive := NB_SLAVE+1;
  constant C_ADDR_WIDTH       : natural  := C_SEL_WIDTH+I2C_ADDR_WIDTH;

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
  p_sequencer : process
  begin
    log(ID_LOG_HDR, "NB_SLAVE = " & integer'image(NB_SLAVE) & ", TESTS_LIST : " & TESTS_LIST, C_SCOPE);

    -- Every name is checked before the first scenario
    for i in 1 to list_length(TESTS_LIST) loop
      if not list_contains(C_TESTS, list_item(TESTS_LIST, i))
      then
        alert(TB_ERROR, "Unknown test """ & list_item(TESTS_LIST, i) & """ (tests : " & C_TESTS & ")", C_SCOPE);
      end if;
    end loop;

    for i in 1 to list_length(TESTS_LIST) loop
      -- Reset pulse, bus inactive : each scenario starts from reset
      sbi_if <= init_sbi_if_signals(C_ADDR_WIDTH, I2C_DATA_WIDTH);
      do_reset(clk_i, arst_b_i);

      log(ID_LOG_HDR, "TEST " & integer'image(i) & "/" & integer'image(list_length(TESTS_LIST)) & " : " & list_item(TESTS_LIST, i), C_SCOPE);
      run_test(list_item(TESTS_LIST, i), NB_SLAVE, clk_i, sbi_if, i2c_scl, scl_oe);
    end loop;

    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process p_sequencer;

end sim;
