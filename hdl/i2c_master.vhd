-------------------------------------------------------------------------------
-- Title      : i2c_master
-- Project    : Asylum
-------------------------------------------------------------------------------
-- File       : i2c_master.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-22
-- Last update: 2026-10-22
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description:
-- I2C master protocol engine (7-bit addressing done by software : the
-- address byte is a written byte), driven by a command stream.
-- A command is executed in this order :
--   1. START or repeated START if cmd_start_i = 1
--   2. byte transfer if cmd_op_i /= I2C_OP_NONE :
--      * I2C_OP_WRITE     : byte popped from the TX stream, the acknowledge
--                           of the slave is sampled (NACK sets sts_nack_o)
--      * I2C_OP_READ_ACK  : byte pushed into the RX stream, answer ACK
--      * I2C_OP_READ_NACK : byte pushed into the RX stream, answer NACK
--                           (last byte read)
--   3. STOP if cmd_stop_i = 1
-- If the master does not own the bus, a command with a byte always begins
-- with a START, and a STOP alone is ignored. Before a START on a released
-- bus, the master waits the end of the transfer of another master
-- (bus_busy_i). Multi-master arbitration is not supported.
--
-- Timing : a SCL period is made of 4 quarters of (cfg_prescaler_ratio_i+1)
-- clock cycles. SDA changes in the middle of the low phase and is sampled in
-- the middle of the high phase :
--
--   quarter   : |   0   |   1   |   2   |   3   |   0   |   1   |
--                                _______________
--   SCL       : ________________/               \_______________
--               ________ _______________________________ _______
--   SDA       : ________X_______________________________X_______
--                       ^ SDA driven    ^ SDA sampled
--
-- SCL is released at the end of the quarter 1. While SCL is released but
-- still low (clock stretching of a slave, synchronization of scl_i), the
-- quarter counter is reloaded : the high phase lasts 2 quarters from the
-- time SCL is seen high.
-- f_scl = f_clk / (4*(ratio+1)), minus the 2 cycles of synchronization of
-- scl_i added to each high phase.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-22  1.0      mrosiere Created
-------------------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.numeric_std.ALL;
library asylum;
use     asylum.i2c_pkg.all;

entity i2c_master is
  generic (
    PRESCALER_WIDTH      : natural := 8
    );
  port (
    -- Clock & Reset
    clk_i                : in  std_logic;
    arst_b_i             : in  std_logic;

    -- Data From AXI Stream To I2C (bytes written)
    tx_tvalid_i          : in  std_logic;
    tx_tready_o          : out std_logic;
    tx_tdata_i           : in  std_logic_vector(8-1 downto 0);

    -- Data From I2C To AXI Stream (bytes read)
    rx_tvalid_o          : out std_logic;
    rx_tready_i          : in  std_logic;
    rx_tdata_o           : out std_logic_vector(8-1 downto 0);

    -- Command
    cmd_tvalid_i         : in  std_logic;
    cmd_tready_o         : out std_logic;
    cmd_start_i          : in  std_logic;                     -- START (or repeated START) before the byte
    cmd_stop_i           : in  std_logic;                     -- STOP after the byte
    cmd_op_i             : in  std_logic_vector(2-1 downto 0);-- Byte operation (I2C_OP_*)

    -- Configuration
    cfg_prescaler_ratio_i: in  std_logic_vector(PRESCALER_WIDTH-1 downto 0); -- Quarter of SCL period minus one, in clock cycles

    -- Status
    sts_busy_o           : out std_logic;                     -- Command in progress or pending
    sts_nack_o           : out std_logic;                     -- NACK received since the last START on a released bus

    -- I2C Bus (synchronized inputs, open drain outputs)
    bus_busy_i           : in  std_logic;                     -- START detected and no STOP since
    scl_i                : in  std_logic;                     -- SCL level (synchronized)
    sda_i                : in  std_logic;                     -- SDA level (synchronized)
    scl_oe_o             : out std_logic;                     -- 1 : SCL pulled low
    sda_oe_o             : out std_logic                      -- 1 : SDA pulled low
    );
end entity i2c_master;

architecture rtl of i2c_master is

  type   state_t is (IDLE, START, START_HOLD, LOAD, XFER, PUSH, STOP);

  signal state_r            : state_t;
  signal phase_r            : unsigned(2-1 downto 0);          -- Quarter of the SCL period
  signal prescaler_cnt_r    : unsigned(PRESCALER_WIDTH-1 downto 0);
  signal prescaler_reload   : std_logic;
  signal scl_hold           : std_logic;                       -- SCL released but still low
  signal tick               : std_logic;                       -- End of a quarter
  signal bit_cnt_r          : unsigned(4-1 downto 0);          -- 0 to 7 : data bits, 8 : acknowledge bit
  signal data_r             : std_logic_vector(8-1 downto 0);  -- Shift register (MSB first)
  signal cmd_tready         : std_logic;
  signal cmd_stop_r         : std_logic;
  signal cmd_op_r           : std_logic_vector(2-1 downto 0);
  signal cmd_write          : std_logic;
  signal cmd_read           : std_logic;
  signal owner_r            : std_logic;                       -- START generated and no STOP since
  signal nack_r             : std_logic;
  signal scl_oe_r           : std_logic;
  signal sda_oe_r           : std_logic;

begin

  cmd_write        <= '1' when cmd_op_r = I2C_OP_WRITE else
                      '0';
  cmd_read         <= cmd_op_r(1);                             -- I2C_OP_READ_ACK or I2C_OP_READ_NACK

  -----------------------------------------------------------------------------
  -- Prescaler
  -----------------------------------------------------------------------------
  -- The quarter counter is reloaded while the FSM waits (command, TX byte,
  -- RX space) : the first quarter of a sequence always lasts ratio+1 cycles.
  -- It is also reloaded while SCL is released but still low.
  scl_hold         <= not scl_oe_r and not scl_i;

  prescaler_reload <= '1' when (state_r = IDLE or
                                state_r = LOAD or
                                state_r = PUSH) else
                      scl_hold;

  tick             <= '1' when (prescaler_cnt_r = 0 and prescaler_reload = '0') else
                      '0';

  process(clk_i,arst_b_i)
  begin
    if arst_b_i = '0'
    then
      prescaler_cnt_r <= (others => '0');
    elsif rising_edge(clk_i)
    then
      if (prescaler_reload = '1') or (prescaler_cnt_r = 0)
      then
        prescaler_cnt_r <= unsigned(cfg_prescaler_ratio_i);
      else
        prescaler_cnt_r <= prescaler_cnt_r - 1;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- FSM
  -----------------------------------------------------------------------------
  -- A command is accepted in IDLE, if the master owns the bus or if the bus
  -- is free
  cmd_tready       <= '1' when (state_r = IDLE and (owner_r = '1' or bus_busy_i = '0')) else
                      '0';

  process(clk_i,arst_b_i)
  begin
    if arst_b_i = '0'
    then
      state_r     <= IDLE;
      phase_r     <= (others => '0');
      bit_cnt_r   <= (others => '0');
      data_r      <= (others => '0');
      cmd_stop_r  <= '0';
      cmd_op_r    <= I2C_OP_NONE;
      owner_r     <= '0';
      nack_r      <= '0';
      scl_oe_r    <= '0'; -- SCL released
      sda_oe_r    <= '0'; -- SDA released
    elsif rising_edge(clk_i)
    then
      case state_r is

        -----------------------------------------------------------------------
        -- Wait a command
        -----------------------------------------------------------------------
        when IDLE =>
          phase_r <= (others => '0');

          if (cmd_tvalid_i = '1' and cmd_tready = '1')
          then
            cmd_stop_r <= cmd_stop_i;
            cmd_op_r   <= cmd_op_i;

            if (cmd_start_i = '1') or (owner_r = '0' and cmd_op_i /= I2C_OP_NONE)
            then
              -- New transfer on a released bus : clear the NACK status
              if owner_r = '0'
              then
                nack_r  <= '0';
              end if;
              state_r   <= START;
            elsif cmd_op_i /= I2C_OP_NONE
            then
              state_r   <= LOAD;
            elsif (cmd_stop_i = '1' and owner_r = '1')
            then
              state_r   <= STOP;
            end if;
          end if;

        -----------------------------------------------------------------------
        -- START or repeated START condition
        -----------------------------------------------------------------------
        when START =>
          if tick = '1'
          then
            phase_r <= phase_r + 1;

            case phase_r is
              when "00"   =>
                sda_oe_r  <= '0';   -- Release SDA (SCL is low after a byte, high on a released bus)
              when "01"   =>
                scl_oe_r  <= '0';   -- Release SCL
              when "10"   =>
                null;               -- SCL high : setup time of the START
              when others =>
                sda_oe_r  <= '1';   -- START : SDA falls while SCL is high
                owner_r   <= '1';
                state_r   <= START_HOLD;
            end case;
          end if;

        -----------------------------------------------------------------------
        -- Hold time of the START condition (2 quarters), then SCL low
        -----------------------------------------------------------------------
        when START_HOLD =>
          if tick = '1'
          then
            phase_r <= phase_r + 1;

            if phase_r(0) = '1'
            then
              scl_oe_r  <= '1';
              phase_r   <= (others => '0');

              if cmd_op_r /= I2C_OP_NONE
              then
                state_r <= LOAD;
              elsif cmd_stop_r = '1'
              then
                state_r <= STOP;
              else
                state_r <= IDLE;
              end if;
            end if;
          end if;

        -----------------------------------------------------------------------
        -- Wait the byte to write (SCL kept low)
        -----------------------------------------------------------------------
        when LOAD =>
          phase_r   <= (others => '0');
          bit_cnt_r <= (others => '0');

          if cmd_write = '0'
          then
            state_r <= XFER;
          elsif tx_tvalid_i = '1'
          then
            data_r  <= tx_tdata_i;
            state_r <= XFER;
          end if;

        -----------------------------------------------------------------------
        -- 8 data bits (MSB first) then the acknowledge bit
        -----------------------------------------------------------------------
        when XFER =>
          if tick = '1'
          then
            phase_r <= phase_r + 1;

            case phase_r is
              when "00"   =>
                -- SCL low : drive SDA
                if bit_cnt_r(3) = '0'
                then
                  -- Data bit : MSB of the shift register if write, released if read
                  sda_oe_r <= cmd_write and not data_r(7);
                else
                  -- Acknowledge bit : released if write (acknowledge of the slave),
                  -- low if READ_ACK, released if READ_NACK
                  sda_oe_r <= cmd_read  and not cmd_op_r(0);
                end if;

              when "01"   =>
                scl_oe_r <= '0';    -- Release SCL

              when "10"   =>
                -- SCL high : sample SDA
                if bit_cnt_r(3) = '0'
                then
                  data_r <= data_r(6 downto 0) & sda_i;
                elsif (cmd_write = '1' and sda_i = '1')
                then
                  nack_r <= '1';    -- The slave does not acknowledge the byte
                end if;

              when others =>
                scl_oe_r  <= '1';   -- SCL low : end of the bit
                bit_cnt_r <= bit_cnt_r + 1;

                if bit_cnt_r(3) = '1'
                then
                  -- End of the acknowledge bit
                  if cmd_read = '1'
                  then
                    state_r <= PUSH;
                  elsif cmd_stop_r = '1'
                  then
                    state_r <= STOP;
                  else
                    state_r <= IDLE;
                  end if;
                end if;
            end case;
          end if;

        -----------------------------------------------------------------------
        -- Push the byte read (SCL kept low)
        -----------------------------------------------------------------------
        when PUSH =>
          phase_r <= (others => '0');

          if rx_tready_i = '1'
          then
            if cmd_stop_r = '1'
            then
              state_r <= STOP;
            else
              state_r <= IDLE;
            end if;
          end if;

        -----------------------------------------------------------------------
        -- STOP condition
        -----------------------------------------------------------------------
        when STOP =>
          if tick = '1'
          then
            phase_r <= phase_r + 1;

            case phase_r is
              when "00"   =>
                sda_oe_r  <= '1';   -- SDA low while SCL is low
              when "01"   =>
                scl_oe_r  <= '0';   -- Release SCL
              when "10"   =>
                null;               -- SCL high : setup time of the STOP
              when others =>
                sda_oe_r  <= '0';   -- STOP : SDA rises while SCL is high
                owner_r   <= '0';
                state_r   <= IDLE;
            end case;
          end if;

      end case;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Outputs
  -----------------------------------------------------------------------------
  cmd_tready_o     <= cmd_tready;

  tx_tready_o      <= '1' when (state_r = LOAD and cmd_write = '1') else
                      '0';

  rx_tvalid_o      <= '1' when state_r = PUSH else
                      '0';
  rx_tdata_o       <= data_r;

  sts_busy_o       <= '1' when state_r /= IDLE else
                      cmd_tvalid_i;
  sts_nack_o       <= nack_r;

  scl_oe_o         <= scl_oe_r;
  sda_oe_o         <= sda_oe_r;

end architecture rtl;
