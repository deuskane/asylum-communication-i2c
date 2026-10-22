-- Generated VHDL Module for I2C


library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;

library asylum;
use     asylum.I2C_csr_pkg.ALL;
library asylum;
use     asylum.csr_pkg.ALL;
library asylum;
use     asylum.sbi_pkg.all;

--==================================
-- Module      : I2C
-- Description : CSR for I2C
-- Width       : 8
--==================================
entity I2C_registers is
  generic (
    MODULE_NAME :  string := "" -- Name of the module
   ;USER_DEFINE_PRESCALER : boolean -- Parameters to enable the User define Prescaler
   ;PRESCALER_RATIO : std_logic_vector(7 downto 0) -- Default value for prescaler ratio
   ;MASTER_ENABLE : boolean -- Master implemented (command FIFO present)
   ;DEPTH_TX : natural -- Depth of FIFO TX (SW2HW)
   ;DEPTH_RX : natural -- Depth of FIFO RX (HW2SW)
   ;DEPTH_CMD : natural -- Depth of FIFO Command (SW2HW)
  );
  port (
    -- Clock and Reset
    clk_i      : in  std_logic
   ;arst_b_i   : in  std_logic
    -- Bus
   ;sbi_ini_i  : in  sbi_ini_t
   ;sbi_tgt_o  : out sbi_tgt_t
    -- CSR
   ;sw2hw_o    : out I2C_sw2hw_t
   ;hw2sw_i    : in  I2C_hw2sw_t
  );
end entity I2C_registers;

architecture rtl of I2C_registers is

  signal   sig_wcs   : std_logic;
  signal   sig_we    : std_logic;
  signal   sig_waddr : unsigned(I2C_ADDR_WIDTH-1 downto 0);
  signal   sig_wdata : std_logic_vector(sbi_ini_i.wdata'length-1 downto 0);
  signal   sig_wbusy : std_logic;

  signal   sig_rcs   : std_logic;
  signal   sig_re    : std_logic;
  signal   sig_raddr : unsigned(I2C_ADDR_WIDTH-1 downto 0);
  signal   sig_rdata : std_logic_vector(sbi_tgt_o.rdata'length-1 downto 0);
  signal   sig_rbusy : std_logic;

  signal   sig_busy  : std_logic;

  signal   data_wcs       : std_logic;
  signal   data_we        : std_logic;
  signal   data_wdata     : std_logic_vector(8-1 downto 0);
  signal   data_wdata_sw  : std_logic_vector(8-1 downto 0);
  signal   data_wdata_hw  : std_logic_vector(8-1 downto 0);
  signal   data_wbusy     : std_logic;

  signal   data_rcs       : std_logic;
  signal   data_re        : std_logic;
  signal   data_rdata     : std_logic_vector(8-1 downto 0);
  signal   data_rdata_sw  : std_logic_vector(8-1 downto 0);
  signal   data_rdata_hw  : std_logic_vector(8-1 downto 0);
  signal   data_rbusy     : std_logic;

  signal   cmd_wcs       : std_logic;
  signal   cmd_we        : std_logic;
  signal   cmd_wdata     : std_logic_vector(8-1 downto 0);
  signal   cmd_wdata_sw  : std_logic_vector(4-1 downto 0);
  signal   cmd_wbusy     : std_logic;

  signal   cmd_rcs       : std_logic;
  signal   cmd_re        : std_logic;
  signal   cmd_rdata     : std_logic_vector(8-1 downto 0);
  signal   cmd_rdata_sw  : std_logic_vector(4-1 downto 0);
  signal   cmd_rdata_hw  : std_logic_vector(4-1 downto 0);
  signal   cmd_rbusy     : std_logic;

  signal   status_wcs       : std_logic;
  signal   status_we        : std_logic;
  signal   status_wdata     : std_logic_vector(8-1 downto 0);
  signal   status_wdata_sw  : std_logic_vector(6-1 downto 0);
  signal   status_wdata_hw  : std_logic_vector(6-1 downto 0);
  signal   status_wbusy     : std_logic;

  signal   status_rcs       : std_logic;
  signal   status_re        : std_logic;
  signal   status_rdata     : std_logic_vector(8-1 downto 0);
  signal   status_rdata_sw  : std_logic_vector(6-1 downto 0);
  signal   status_rdata_hw  : std_logic_vector(6-1 downto 0);
  signal   status_rbusy     : std_logic;

  function INIT_cfg
    return std_logic_vector is
    variable tmp : std_logic_vector(8-1 downto 0);
  begin  -- function INIT_cfg
    tmp(0 downto 0) := "0"; -- enable
    tmp(7 downto 1) := "0000000"; -- slave_addr
    return tmp;
  end function INIT_cfg;

  signal   cfg_wcs       : std_logic;
  signal   cfg_we        : std_logic;
  signal   cfg_wdata     : std_logic_vector(8-1 downto 0);
  signal   cfg_wdata_sw  : std_logic_vector(8-1 downto 0);
  signal   cfg_wbusy     : std_logic;

  signal   cfg_rcs       : std_logic;
  signal   cfg_re        : std_logic;
  signal   cfg_rdata     : std_logic_vector(8-1 downto 0);
  signal   cfg_rdata_sw  : std_logic_vector(8-1 downto 0);
  signal   cfg_rdata_hw  : std_logic_vector(8-1 downto 0);
  signal   cfg_rbusy     : std_logic;

  function INIT_prescaler
    return std_logic_vector is
    variable tmp : std_logic_vector(8-1 downto 0);
  begin  -- function INIT_prescaler
    tmp(7 downto 0) := PRESCALER_RATIO; -- ratio
    return tmp;
  end function INIT_prescaler;

  signal   prescaler_wcs       : std_logic;
  signal   prescaler_we        : std_logic;
  signal   prescaler_wdata     : std_logic_vector(8-1 downto 0);
  signal   prescaler_wdata_sw  : std_logic_vector(8-1 downto 0);
  signal   prescaler_wbusy     : std_logic;

  signal   prescaler_rcs       : std_logic;
  signal   prescaler_re        : std_logic;
  signal   prescaler_rdata     : std_logic_vector(8-1 downto 0);
  signal   prescaler_rdata_sw  : std_logic_vector(8-1 downto 0);
  signal   prescaler_rdata_hw  : std_logic_vector(8-1 downto 0);
  signal   prescaler_rbusy     : std_logic;

begin  -- architecture rtl

  -- Interface 
  sig_wcs   <= sbi_ini_i.cs;
  sig_we    <= sbi_ini_i.we;
  sig_waddr <= unsigned(sbi_ini_i.addr(I2C_ADDR_WIDTH-1 downto 0));
  sig_wdata <= sbi_ini_i.wdata;

  sig_rcs   <= sbi_ini_i.cs;
  sig_re    <= sbi_ini_i.re;
  sig_raddr <= unsigned(sbi_ini_i.addr(I2C_ADDR_WIDTH-1 downto 0));
  sbi_tgt_o.rdata <= sig_rdata;
  sbi_tgt_o.ready <= not sig_busy;

  sig_busy  <= sig_wbusy when sig_we = '1' else
               sig_rbusy when sig_re = '1' else
               '0';

  gen_data: if (True)
  generate
  --==================================
  -- Register    : data
  -- Description : Write : byte to transmit (master write or slave read), Read : byte received (master read or slave write)
  -- Address     : 0x0
  -- Width       : 8
  -- Sw Access   : rw
  -- Hw Access   : rw
  -- Hw Type     : fifo
  --==================================
  --==================================
  -- Field       : value
  -- Description : Data TX or Data RX
  -- Width       : 8
  --==================================


    data_rcs     <= '1' when (sig_raddr = I2C_DATA) else '0';
    data_re      <= sig_rcs and sig_re and data_rcs;
    data_rdata   <= (
       0 => data_rdata_sw(0) -- value(0)
      ,1 => data_rdata_sw(1) -- value(1)
      ,2 => data_rdata_sw(2) -- value(2)
      ,3 => data_rdata_sw(3) -- value(3)
      ,4 => data_rdata_sw(4) -- value(4)
      ,5 => data_rdata_sw(5) -- value(5)
      ,6 => data_rdata_sw(6) -- value(6)
      ,7 => data_rdata_sw(7) -- value(7)
      );

    data_wcs     <= '1' when       (sig_waddr = I2C_DATA)   else '0';
    data_we      <= sig_wcs and sig_we and data_wcs;
    data_wdata   <= sig_wdata;
    data_wdata_sw(7 downto 0) <= data_wdata(7 downto 0); -- value
    data_wdata_hw(7 downto 0) <= hw2sw_i.data.value; -- value
    sw2hw_o.data.value <= data_rdata_hw(7 downto 0); -- value

    ins_data : csr_fifo
      generic map
        (WIDTH         => 8
        ,BLOCKING_READ => True
        ,BLOCKING_WRITE => True
        ,DEPTH_SW2HW => DEPTH_TX
        ,DEPTH_HW2SW => DEPTH_RX
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => data_wdata_sw
        ,sw_rd_o       => data_rdata_sw
        ,sw_we_i       => data_we
        ,sw_re_i       => data_re
        ,sw_rbusy_o    => data_rbusy
        ,sw_wbusy_o    => data_wbusy
        ,hw_tx_valid_i        => hw2sw_i.data.valid
        ,hw_tx_ready_o        => sw2hw_o.data.ready
        ,hw_tx_data_i         => data_wdata_hw
        ,hw_tx_empty_o        => sw2hw_o.data.hw2sw_empty
        ,hw_tx_full_o         => sw2hw_o.data.hw2sw_full
        ,hw_rx_valid_o        => sw2hw_o.data.valid
        ,hw_rx_ready_i        => hw2sw_i.data.ready
        ,hw_rx_data_o         => data_rdata_hw
        ,hw_rx_empty_o        => sw2hw_o.data.sw2hw_empty
        ,hw_rx_full_o         => sw2hw_o.data.sw2hw_full
        );

  end generate gen_data;

  gen_data_b: if not (True)
  generate
    data_rcs     <= '0';
    data_rbusy   <= '0';
    data_rdata   <= (others => '0');
    data_wcs      <= '0';
    data_wbusy    <= '0';
    sw2hw_o.data.value <= "00000000";
    sw2hw_o.data.ready <= '0';
    sw2hw_o.data.valid <= '0';
  end generate gen_data_b;

  gen_cmd: if (MASTER_ENABLE)
  generate
  --==================================
  -- Register    : cmd
  -- Description : Master Command FIFO, write only (a read returns status). Each command is executed in this order : START (if start), byte (if op), STOP (if stop)
  -- Address     : 0x1
  -- Width       : 4
  -- Sw Access   : wo
  -- Hw Access   : ro
  -- Hw Type     : fifo
  --==================================
  --==================================
  -- Field       : start
  -- Description : Generate a START condition (a repeated START if the master already owns the bus) before the byte. A START is always generated if the master does not own the bus and op is not NONE
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : stop
  -- Description : Generate a STOP condition after the byte (ignored if the master does not own the bus)
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : op
  -- Description : Byte operation
  -- Width       : 2
  --==================================


    cmd_rcs     <= '0';
    cmd_re      <= '0';
    cmd_rdata   <= (others=>'0');

    cmd_wcs     <= '1' when       (sig_waddr = I2C_CMD)   else '0';
    cmd_we      <= sig_wcs and sig_we and cmd_wcs;
    cmd_wdata   <= sig_wdata;
    cmd_wdata_sw(0 downto 0) <= cmd_wdata(0 downto 0); -- start
    cmd_wdata_sw(1 downto 1) <= cmd_wdata(1 downto 1); -- stop
    cmd_wdata_sw(3 downto 2) <= cmd_wdata(3 downto 2); -- op
    sw2hw_o.cmd.start <= cmd_rdata_hw(0 downto 0); -- start
    sw2hw_o.cmd.stop <= cmd_rdata_hw(1 downto 1); -- stop
    sw2hw_o.cmd.op <= cmd_rdata_hw(3 downto 2); -- op

    ins_cmd : csr_fifo
      generic map
        (WIDTH         => 4
        ,BLOCKING_READ => True
        ,BLOCKING_WRITE => True
        ,DEPTH_SW2HW => DEPTH_CMD
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => cmd_wdata_sw
        ,sw_rd_o       => cmd_rdata_sw
        ,sw_we_i       => cmd_we
        ,sw_re_i       => cmd_re
        ,sw_rbusy_o    => cmd_rbusy
        ,sw_wbusy_o    => cmd_wbusy
        ,hw_tx_valid_i        => '0'
        ,hw_tx_ready_o        => open
        ,hw_tx_data_i         => (others => '0')
        ,hw_tx_empty_o        => open
        ,hw_tx_full_o         => open
        ,hw_rx_valid_o        => sw2hw_o.cmd.valid
        ,hw_rx_ready_i        => hw2sw_i.cmd.ready
        ,hw_rx_data_o         => cmd_rdata_hw
        ,hw_rx_empty_o        => sw2hw_o.cmd.sw2hw_empty
        ,hw_rx_full_o         => sw2hw_o.cmd.sw2hw_full
        );

  end generate gen_cmd;

  gen_cmd_b: if not (MASTER_ENABLE)
  generate
    cmd_rcs     <= '0';
    cmd_rbusy   <= '0';
    cmd_rdata   <= (others => '0');
    cmd_wcs      <= '0';
    cmd_wbusy    <= '0';
    sw2hw_o.cmd.start <= "0";
    sw2hw_o.cmd.stop <= "0";
    sw2hw_o.cmd.op <= "00";
    sw2hw_o.cmd.valid <= '0';
  end generate gen_cmd_b;

  gen_status: if (True)
  generate
  --==================================
  -- Register    : status
  -- Description : I2C Status Register, read at the address of cmd (cmd is write only), without latency
  -- Address     : 0x1
  -- Width       : 6
  -- Sw Access   : ro
  -- Hw Access   : wo
  -- Hw Type     : ext
  --==================================
  --==================================
  -- Field       : busy
  -- Description : Master : 0 : no command in progress or pending, 1 : command in progress or pending
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : nack
  -- Description : Master : 1 : a NACK was received on a written byte since the last START generated from a released bus
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : bus_busy
  -- Description : 0 : bus free, 1 : START detected and no STOP since
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : slave_addressed
  -- Description : Slave : 1 : the slave address was acknowledged, until the next STOP or START
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : slave_read
  -- Description : Slave : direction of the last acknowledged address. 0 : the master writes, 1 : the master reads
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : rx_empty
  -- Description : 0 : at least one byte can be read in data, 1 : RX FIFO empty (a read of data waits for a byte)
  -- Width       : 1
  --==================================


    status_rcs     <= '1' when (sig_raddr = I2C_STATUS) else '0';
    status_re      <= sig_rcs and sig_re and status_rcs;
    status_rdata   <= (
       0 => status_rdata_sw(0) -- busy(0)
      ,1 => status_rdata_sw(1) -- nack(0)
      ,2 => status_rdata_sw(2) -- bus_busy(0)
      ,3 => status_rdata_sw(3) -- slave_addressed(0)
      ,4 => status_rdata_sw(4) -- slave_read(0)
      ,5 => status_rdata_sw(5) -- rx_empty(0)
      ,others => '0'
      );

    status_wcs      <= '0';
    status_we       <= '0';
    status_wdata    <= (others=>'0');
    status_wdata_sw <= (others=>'0');
    status_wdata_hw(0 downto 0) <= hw2sw_i.status.busy; -- busy
    status_wdata_hw(1 downto 1) <= hw2sw_i.status.nack; -- nack
    status_wdata_hw(2 downto 2) <= hw2sw_i.status.bus_busy; -- bus_busy
    status_wdata_hw(3 downto 3) <= hw2sw_i.status.slave_addressed; -- slave_addressed
    status_wdata_hw(4 downto 4) <= hw2sw_i.status.slave_read; -- slave_read
    status_wdata_hw(5 downto 5) <= hw2sw_i.status.rx_empty; -- rx_empty

    ins_status : csr_ext
      generic map
        (WIDTH         => 6
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => status_wdata_sw
        ,sw_rd_o       => status_rdata_sw
        ,sw_we_i       => status_we
        ,sw_re_i       => status_re
        ,sw_rbusy_o    => status_rbusy
        ,sw_wbusy_o    => status_wbusy
        ,hw_wd_i       => status_wdata_hw
        ,hw_rd_o       => open
        ,hw_we_i       => hw2sw_i.status.we
        ,hw_sw_re_o    => sw2hw_o.status.re
        ,hw_sw_we_o      => open
        );

  end generate gen_status;

  gen_status_b: if not (True)
  generate
    status_rcs     <= '0';
    status_rbusy   <= '0';
    status_rdata   <= (others => '0');
    status_wcs      <= '0';
    status_wbusy    <= '0';
    sw2hw_o.status.re <= '0';
  end generate gen_status_b;

  gen_cfg: if (True)
  generate
  --==================================
  -- Register    : cfg
  -- Description : I2C Configuration Register
  -- Address     : 0x2
  -- Width       : 8
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : reg
  --==================================
  --==================================
  -- Field       : enable
  -- Description : 0 : I2C is disabled (held in reset, SCL and SDA released), 1 : I2C is enabled
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : slave_addr
  -- Description : 7-bit address of the slave. 0 : slave disabled (0 is the general call address)
  -- Width       : 7
  --==================================


    cfg_rcs     <= '1' when (sig_raddr = I2C_CFG) else '0';
    cfg_re      <= sig_rcs and sig_re and cfg_rcs;
    cfg_rdata   <= (
       0 => cfg_rdata_sw(0) -- enable(0)
      ,1 => cfg_rdata_sw(1) -- slave_addr(0)
      ,2 => cfg_rdata_sw(2) -- slave_addr(1)
      ,3 => cfg_rdata_sw(3) -- slave_addr(2)
      ,4 => cfg_rdata_sw(4) -- slave_addr(3)
      ,5 => cfg_rdata_sw(5) -- slave_addr(4)
      ,6 => cfg_rdata_sw(6) -- slave_addr(5)
      ,7 => cfg_rdata_sw(7) -- slave_addr(6)
      );

    cfg_wcs     <= '1' when       (sig_waddr = I2C_CFG)   else '0';
    cfg_we      <= sig_wcs and sig_we and cfg_wcs;
    cfg_wdata   <= sig_wdata;
    cfg_wdata_sw(0 downto 0) <= cfg_wdata(0 downto 0); -- enable
    cfg_wdata_sw(7 downto 1) <= cfg_wdata(7 downto 1); -- slave_addr
    sw2hw_o.cfg.enable <= cfg_rdata_hw(0 downto 0); -- enable
    sw2hw_o.cfg.slave_addr <= cfg_rdata_hw(7 downto 1); -- slave_addr

    ins_cfg : csr_reg
      generic map
        (WIDTH         => 8
        ,INIT          => INIT_cfg
        ,MODEL         => "rw"
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => cfg_wdata_sw
        ,sw_rd_o       => cfg_rdata_sw
        ,sw_we_i       => cfg_we
        ,sw_re_i       => cfg_re
        ,sw_rbusy_o    => cfg_rbusy
        ,sw_wbusy_o    => cfg_wbusy
        ,hw_wd_i       => (others => '0')
        ,hw_rd_o       => cfg_rdata_hw
        ,hw_we_i       => '0'
        ,hw_sw_re_o    => sw2hw_o.cfg.re
        ,hw_sw_we_o    => sw2hw_o.cfg.we
        );

  end generate gen_cfg;

  gen_cfg_b: if not (True)
  generate
    cfg_rcs     <= '0';
    cfg_rbusy   <= '0';
    cfg_rdata   <= (others => '0');
    cfg_wcs      <= '0';
    cfg_wbusy    <= '0';
    sw2hw_o.cfg.enable <= "0";
    sw2hw_o.cfg.slave_addr <= "0000000";
    sw2hw_o.cfg.re <= '0';
    sw2hw_o.cfg.we <= '0';
  end generate gen_cfg_b;

  gen_prescaler: if (USER_DEFINE_PRESCALER)
  generate
  --==================================
  -- Register    : prescaler
  -- Description : I2C Clock Prescaler. Master : SCL period is 4*(prescaler+1)+2 CLK cycles (the 2 cycles of synchronization of SCL extend the high phase). Slave : the data setup time after a clock stretching is (prescaler+1) CLK cycles
  -- Address     : 0x3
  -- Width       : 8
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : reg
  --==================================
  --==================================
  -- Field       : ratio
  -- Description : Number of CLK cycles minus one of a quarter of SCL period
  -- Width       : 8
  --==================================


    prescaler_rcs     <= '1' when (sig_raddr = I2C_PRESCALER) else '0';
    prescaler_re      <= sig_rcs and sig_re and prescaler_rcs;
    prescaler_rdata   <= (
       0 => prescaler_rdata_sw(0) -- ratio(0)
      ,1 => prescaler_rdata_sw(1) -- ratio(1)
      ,2 => prescaler_rdata_sw(2) -- ratio(2)
      ,3 => prescaler_rdata_sw(3) -- ratio(3)
      ,4 => prescaler_rdata_sw(4) -- ratio(4)
      ,5 => prescaler_rdata_sw(5) -- ratio(5)
      ,6 => prescaler_rdata_sw(6) -- ratio(6)
      ,7 => prescaler_rdata_sw(7) -- ratio(7)
      );

    prescaler_wcs     <= '1' when       (sig_waddr = I2C_PRESCALER)   else '0';
    prescaler_we      <= sig_wcs and sig_we and prescaler_wcs;
    prescaler_wdata   <= sig_wdata;
    prescaler_wdata_sw(7 downto 0) <= prescaler_wdata(7 downto 0); -- ratio
    sw2hw_o.prescaler.ratio <= prescaler_rdata_hw(7 downto 0); -- ratio

    ins_prescaler : csr_reg
      generic map
        (WIDTH         => 8
        ,INIT          => INIT_prescaler
        ,MODEL         => "rw"
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => prescaler_wdata_sw
        ,sw_rd_o       => prescaler_rdata_sw
        ,sw_we_i       => prescaler_we
        ,sw_re_i       => prescaler_re
        ,sw_rbusy_o    => prescaler_rbusy
        ,sw_wbusy_o    => prescaler_wbusy
        ,hw_wd_i       => (others => '0')
        ,hw_rd_o       => prescaler_rdata_hw
        ,hw_we_i       => '0'
        ,hw_sw_re_o    => sw2hw_o.prescaler.re
        ,hw_sw_we_o    => sw2hw_o.prescaler.we
        );

  end generate gen_prescaler;

  gen_prescaler_b: if not (USER_DEFINE_PRESCALER)
  generate
    prescaler_rcs     <= '0';
    prescaler_rbusy   <= '0';
    prescaler_rdata   <= (others => '0');
    prescaler_wcs      <= '0';
    prescaler_wbusy    <= '0';
    sw2hw_o.prescaler.ratio <= PRESCALER_RATIO;
    sw2hw_o.prescaler.re <= '0';
    sw2hw_o.prescaler.we <= '0';
  end generate gen_prescaler_b;

  sig_wbusy <= 
    data_wbusy when data_wcs = '1' else
    cmd_wbusy when cmd_wcs = '1' else
    status_wbusy when status_wcs = '1' else
    cfg_wbusy when cfg_wcs = '1' else
    prescaler_wbusy when prescaler_wcs = '1' else
    '0'; -- Bad Address, no busy
  sig_rbusy <= 
    data_rbusy when data_rcs = '1' else
    cmd_rbusy when cmd_rcs = '1' else
    status_rbusy when status_rcs = '1' else
    cfg_rbusy when cfg_rcs = '1' else
    prescaler_rbusy when prescaler_rcs = '1' else
    '0'; -- Bad Address, no busy
  sig_rdata <= 
    data_rdata when data_rcs = '1' else
    cmd_rdata when cmd_rcs = '1' else
    status_rdata when status_rcs = '1' else
    cfg_rdata when cfg_rcs = '1' else
    prescaler_rdata when prescaler_rcs = '1' else
    (others => '0'); -- Bad Address, return 0

  gen_tgt_info_name : if MODULE_NAME = ""
  generate
    sbi_tgt_o.info.name <= to_sbi_name("I2C");
  else generate
    sbi_tgt_o.info.name <= to_sbi_name(MODULE_NAME);
  end generate;
end architecture rtl;
