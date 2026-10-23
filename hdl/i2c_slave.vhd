-------------------------------------------------------------------------------
-- Title      : i2c_slave
-- Project    : Asylum
-------------------------------------------------------------------------------
-- File       : i2c_slave.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-22
-- Last update: 2026-10-22
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description:
-- I2C slave protocol engine, 7-bit address (cfg_slave_addr_i).
-- * After a START (or repeated START), the address byte is received. If the
--   address matches, the slave acknowledges it, else it waits the next START.
-- * Master write (R/W = 0) : each received byte is pushed into the RX stream
--   and acknowledged.
-- * Master read  (R/W = 1) : each byte is popped from the TX stream and
--   transmitted, until a NACK of the master.
-- * A STOP releases the bus and ends the transfer.
-- Clock stretching : SCL is held low after the falling edge of SCL which
-- ends a byte (or the acknowledge of the address in read), until the byte
-- is pushed into the RX stream (master write) or a byte is popped from the
-- TX stream (master read). Then SDA is driven, and SCL is released after a
-- data setup time of (cfg_prescaler_ratio_i+1) clock cycles. If the master
-- has not released SCL yet, the stretching is not visible on the bus.
-- SDA is sampled on the rising edges of SCL and changes after the falling
-- edges of SCL (events from the bus monitor of i2c_core, synchronized).
-- General call and 10-bit addressing are not supported.
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

entity i2c_slave is
  generic (
    PRESCALER_WIDTH      : natural := 8
    );
  port (
    -- Clock & Reset
    clk_i                : in  std_logic;
    arst_b_i             : in  std_logic;

    -- Data From AXI Stream To I2C (bytes read by the master)
    tx_tvalid_i          : in  std_logic;
    tx_tready_o          : out std_logic;
    tx_tdata_i           : in  std_logic_vector(8-1 downto 0);

    -- Data From I2C To AXI Stream (bytes written by the master)
    rx_tvalid_o          : out std_logic;
    rx_tready_i          : in  std_logic;
    rx_tdata_o           : out std_logic_vector(8-1 downto 0);

    -- Configuration
    cfg_enable_i         : in  std_logic;                     -- 0 : slave inactive, SCL and SDA released
    cfg_slave_addr_i     : in  std_logic_vector(7-1 downto 0);-- 7-bit address of the slave
    cfg_prescaler_ratio_i: in  std_logic_vector(PRESCALER_WIDTH-1 downto 0); -- Data setup time after a clock stretching minus one, in clock cycles

    -- Status
    sts_addressed_o      : out std_logic;                     -- Address acknowledged, until the next STOP or START
    sts_read_o           : out std_logic;                     -- R/W bit of the last acknowledged address

    -- I2C Bus (synchronized inputs and events, open drain outputs)
    sda_i                : in  std_logic;                     -- SDA level (synchronized)
    scl_rise_i           : in  std_logic;                     -- Rising  edge of SCL
    scl_fall_i           : in  std_logic;                     -- Falling edge of SCL
    bus_start_i          : in  std_logic;                     -- START condition
    bus_stop_i           : in  std_logic;                     -- STOP  condition
    scl_oe_o             : out std_logic;                     -- 1 : SCL pulled low
    sda_oe_o             : out std_logic                      -- 1 : SDA pulled low
    );
end entity i2c_slave;

architecture rtl of i2c_slave is

  type   state_t is (IDLE, ADDR, ADDR_ACK, RX, RX_PUSH, RX_ACK, TX_LOAD, TX, TX_ACK, SETUP);

  signal state_r            : state_t;
  signal bit_cnt_r          : unsigned(4-1 downto 0);          -- Number of bits received (ADDR, RX) or transmitted (TX)
  signal data_r             : std_logic_vector(8-1 downto 0);  -- Shift register (MSB first)
  signal setup_cnt_r        : unsigned(PRESCALER_WIDTH-1 downto 0);
  signal addressed_r        : std_logic;
  signal read_r             : std_logic;                       -- R/W bit of the acknowledged address
  signal ack_r              : std_logic;                       -- Acknowledge of the master (0 : ACK, 1 : NACK)
  signal rx_tvalid_r        : std_logic;
  signal scl_oe_r           : std_logic;
  signal sda_oe_r           : std_logic;

begin

  -----------------------------------------------------------------------------
  -- FSM
  -----------------------------------------------------------------------------
  process(clk_i,arst_b_i)
  begin
    if arst_b_i = '0'
    then
      state_r     <= IDLE;
      bit_cnt_r   <= (others => '0');
      data_r      <= (others => '0');
      setup_cnt_r <= (others => '0');
      addressed_r <= '0';
      read_r      <= '0';
      ack_r       <= '1';
      rx_tvalid_r <= '0';
      scl_oe_r    <= '0'; -- SCL released
      sda_oe_r    <= '0'; -- SDA released
    elsif rising_edge(clk_i)
    then
      if (cfg_enable_i = '0') or (bus_stop_i = '1')
      then
        -- Slave disabled or STOP : release the bus and wait a START
        state_r     <= IDLE;
        addressed_r <= '0';
        rx_tvalid_r <= '0';
        scl_oe_r    <= '0';
        sda_oe_r    <= '0';

      elsif bus_start_i = '1'
      then
        -- START or repeated START : receive the address
        state_r     <= ADDR;
        bit_cnt_r   <= (others => '0');
        addressed_r <= '0';
        rx_tvalid_r <= '0';
        scl_oe_r    <= '0';
        sda_oe_r    <= '0';

      else
        case state_r is

          ---------------------------------------------------------------------
          -- Not addressed : wait a START
          ---------------------------------------------------------------------
          when IDLE =>
            null;

          ---------------------------------------------------------------------
          -- Address byte : 7-bit address and R/W bit
          ---------------------------------------------------------------------
          when ADDR =>
            if scl_rise_i = '1'
            then
              data_r    <= data_r(6 downto 0) & sda_i;
              bit_cnt_r <= bit_cnt_r + 1;
            elsif (scl_fall_i = '1' and bit_cnt_r(3) = '1')
            then
              -- End of the 8th bit
              if data_r(7 downto 1) = cfg_slave_addr_i
              then
                sda_oe_r    <= '1';         -- ACK
                addressed_r <= '1';
                read_r      <= data_r(0);
                state_r     <= ADDR_ACK;
              else
                state_r     <= IDLE;        -- Not addressed
              end if;
            end if;

          ---------------------------------------------------------------------
          -- Acknowledge of the address
          ---------------------------------------------------------------------
          when ADDR_ACK =>
            if scl_fall_i = '1'
            then
              sda_oe_r    <= '0';
              bit_cnt_r   <= (others => '0');

              if read_r = '1'
              then
                scl_oe_r  <= '1';           -- Clock stretching until a byte to transmit is available
                state_r   <= TX_LOAD;
              else
                state_r   <= RX;
              end if;
            end if;

          ---------------------------------------------------------------------
          -- Receive a byte written by the master
          ---------------------------------------------------------------------
          when RX =>
            if scl_rise_i = '1'
            then
              data_r      <= data_r(6 downto 0) & sda_i;
              bit_cnt_r   <= bit_cnt_r + 1;
            elsif (scl_fall_i = '1' and bit_cnt_r(3) = '1')
            then
              -- End of the 8th bit
              scl_oe_r    <= '1';           -- Clock stretching until the byte is accepted
              rx_tvalid_r <= '1';
              state_r     <= RX_PUSH;
            end if;

          ---------------------------------------------------------------------
          -- Push the received byte, then acknowledge it
          ---------------------------------------------------------------------
          when RX_PUSH =>
            if rx_tready_i = '1'
            then
              rx_tvalid_r <= '0';
              sda_oe_r    <= '1';           -- ACK
              setup_cnt_r <= unsigned(cfg_prescaler_ratio_i);
              state_r     <= SETUP;
            end if;

          ---------------------------------------------------------------------
          -- Acknowledge of a received byte
          ---------------------------------------------------------------------
          when RX_ACK =>
            if scl_fall_i = '1'
            then
              sda_oe_r    <= '0';
              bit_cnt_r   <= (others => '0');
              state_r     <= RX;
            end if;

          ---------------------------------------------------------------------
          -- Load the byte to transmit (SCL stretched), drive its MSB
          ---------------------------------------------------------------------
          when TX_LOAD =>
            if tx_tvalid_i = '1'
            then
              data_r      <= tx_tdata_i;
              sda_oe_r    <= not tx_tdata_i(7);
              bit_cnt_r   <= (others => '0');
              setup_cnt_r <= unsigned(cfg_prescaler_ratio_i);
              state_r     <= SETUP;
            end if;

          ---------------------------------------------------------------------
          -- Data setup time, then release SCL
          ---------------------------------------------------------------------
          when SETUP =>
            if setup_cnt_r = 0
            then
              scl_oe_r    <= '0';

              if read_r = '1'
              then
                state_r   <= TX;
              else
                state_r   <= RX_ACK;
              end if;
            else
              setup_cnt_r <= setup_cnt_r - 1;
            end if;

          ---------------------------------------------------------------------
          -- Transmit a byte read by the master
          ---------------------------------------------------------------------
          when TX =>
            if scl_fall_i = '1'
            then
              if bit_cnt_r = 7
              then
                -- End of the 8th bit : release SDA for the acknowledge of the master
                sda_oe_r  <= '0';
                state_r   <= TX_ACK;
              else
                -- Next bit
                data_r    <= data_r(6 downto 0) & '0';
                sda_oe_r  <= not data_r(6);
                bit_cnt_r <= bit_cnt_r + 1;
              end if;
            end if;

          ---------------------------------------------------------------------
          -- Acknowledge of the master
          ---------------------------------------------------------------------
          when TX_ACK =>
            if scl_rise_i = '1'
            then
              ack_r       <= sda_i;
            elsif scl_fall_i = '1'
            then
              if ack_r = '0'
              then
                scl_oe_r  <= '1';           -- ACK : clock stretching until the next byte is available
                state_r   <= TX_LOAD;
              else
                state_r   <= IDLE;          -- NACK : end of the transfer, wait a STOP or a START
              end if;
            end if;

        end case;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Outputs
  -----------------------------------------------------------------------------
  tx_tready_o      <= '1' when state_r = TX_LOAD else
                      '0';

  rx_tvalid_o      <= rx_tvalid_r;
  rx_tdata_o       <= data_r;

  sts_addressed_o  <= addressed_r;
  sts_read_o       <= read_r;

  scl_oe_o         <= scl_oe_r;
  sda_oe_o         <= sda_oe_r;

end architecture rtl;
