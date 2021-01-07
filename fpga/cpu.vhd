-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2020 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): DOPLNIT
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- ram[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_WE    : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti 
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

 signal pc_out : std_logic_vector(11 downto 0);
 signal pc_inc : std_logic;
 signal pc_dec : std_logic;
 signal pc_ld : std_logic;
 signal pc_abus : std_logic;


 signal ptr_inc : std_logic;
 signal ptr_dec : std_logic;
 signal ptr_store : std_logic_vector(9 downto 0);


 signal ras_push : std_logic;
 signal ras_pop : std_logic;
 signal ras_top : std_logic;
 signal ras_out : std_logic_vector(11 downto 0);
 signal ras_array : std_logic_vector(191 downto 0);

 signal cnt_inc : std_logic;
 signal cnt_dec : std_logic;
 signal cnt_out : std_logic_vector(3 downto 0);

 type alu_type is (alu_ind, alu_dec, alu_inc);
 signal alu_sel : alu_type;
 signal alu_st : std_logic_vector(7 downto 0);


--decoder
 type inst_type is (halt, inc, dec, pinc, pdec, read, write, jump, jump_end, ostatni );
 signal inst_dec : inst_type;

 --fsm
 type fsm_state is (sidle, sfetch0, sfetch1, sdecode, sinc0, sdec0, swrite0, sread0, sskipcycle0, sskipcycle, shalt, sjump0, sjumpend0, sjumpend1, spwait);
 signal pstate : fsm_state;
 signal nstate : fsm_state;

 signal data_iszero : std_logic;
 signal cnt_iszero : std_logic;

begin

 -- zde dopiste vlastni VHDL kod


 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --   - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --   - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.


PC : process( CLK, RESET )
begin
  if ( RESET = '1') then
    pc_out <= (others=>'0');
  elsif ( rising_edge(CLK)) then
    if(pc_inc ='1') then
      pc_out <= pc_out + 1;
    elsif(pc_dec = '1') then
      pc_out <= pc_out - 1;
    elsif(pc_ld = '1') then
      pc_out <= ras_out;
    end if;
  end if;

end process ; -- PC

CODE_ADDR <= pc_out when (pc_abus = '1')
                    else (others=>'Z');





ptr : process( CLK, RESET, ptr_store )
begin
  if( RESET = '1') then
    ptr_store <= (others=>'0');
  elsif (rising_edge(CLK)) then
    if (ptr_inc = '1') then
      ptr_store <= ptr_store + 1;      
    elsif (ptr_dec = '1') then
      ptr_store <= ptr_store - 1; 
    end if;
  end if;  
  DATA_ADDR <= ptr_store;
end process ; -- ptr


alu : process( DATA_RDATA, alu_sel, IN_DATA, alu_st )
begin
  alu_st <= (others=>'0');
    case alu_sel is
      when alu_ind => 
      alu_st <= IN_DATA;
      when alu_inc => 
      alu_st <= DATA_RDATA + 1;
      when alu_dec => 
      alu_st <= DATA_RDATA - 1;
      when others =>
      alu_st <= DATA_RDATA; --should be useless
    end case;
    DATA_WDATA <= alu_st;
      
end process ; -- alu

ras : process( CLK, RESET )
begin
  if(RESET = '1') then
    ras_array <= (others=>'0');
  elsif ( rising_edge(CLK)) then
    if(ras_push = '1') then
      ras_array <=  pc_out & ras_array(191 downto 12);
    elsif (ras_pop = '1') then
      ras_array <= ras_array(179 downto 0) & "000000000000";
    elsif (ras_top = '1') then
      ras_out <= ras_array(191 downto 180);
    end if;
  end if;
--
end process ; -- ras



cnt : process( CLK, RESET )
begin
  if(RESET = '1') then
    cnt_out <= (others=>'0');
  elsif ( rising_edge(CLK)) then
      if(cnt_inc = '1') then
        cnt_out <= cnt_out + 1;
      elsif (cnt_dec = '1') then
        cnt_out <= cnt_out - 1;
      end if;
  end if;
end process ; -- cnt





------ FSM


decoder : process( CODE_DATA )
begin
  case CODE_DATA is
    when X"3E" => inst_dec <= pinc;
    when X"3C" => inst_dec <= pdec;
    when X"2B" => inst_dec <= inc;
    when X"2D" => inst_dec <= dec;
    when X"5B" => inst_dec <= jump;
    when X"5D" => inst_dec <= jump_end;
    when X"2E" => inst_dec <= write;
    when X"2C" => inst_dec <= read;
    when X"00" => inst_dec <= halt;
    when others => inst_dec <= ostatni;
  end case;

end process ; -- decoder 


fsm_present : process( CLK, RESET, EN )
begin
  if( RESET = '1' OR EN = '0') then
    pstate <= sidle;
  elsif ( rising_edge(CLK) ) then
    pstate <= nstate;
  end if;
end process ; -- fsm_present


fsm : process( pstate, OUT_BUSY, IN_VLD, inst_dec, cnt_iszero, data_iszero )
begin
  --init
  pc_inc <= '0';
  pc_dec <= '0';
  pc_abus <= '0';
  DATA_WE <= '0';
  CODE_EN <= '0';
  DATA_EN <= '0';
  OUT_WE <= '0';
  IN_REQ <= '0';
  ptr_inc <= '0';
  ptr_dec <= '0';
  ras_pop <= '0';
  ras_push <= '0';
  ras_top <= '0';
  cnt_inc <= '0';
  cnt_dec <= '0';
  pc_ld <= '0';
  alu_sel <= alu_dec;

  --next state and output logic
  case pstate is
    when sidle => 
      nstate <= sfetch0;
    when sfetch0 =>
      pc_abus <= '1';
      CODE_EN <= '1';
      DATA_EN <= '0';
      nstate <= sfetch1;
    when sfetch1 =>
      nstate <= sdecode;
    when sdecode =>
      --info z dekoderu
      case inst_dec is
        when inc =>
          alu_sel <= alu_inc;
          DATA_EN <= '1';
          DATA_WE <= '1';
          nstate <= sinc0;
        when dec =>
          alu_sel <= alu_dec;
          DATA_EN <= '1';
          DATA_WE <= '1';
          nstate <= sdec0;
        when read =>
          alu_sel <= alu_ind;
          DATA_EN <= '1';
          IN_REQ <= '1';
          nstate <= sread0;
        when write =>
          DATA_EN <= '1';
          nstate <= swrite0;
        when pinc =>
          ptr_inc <= '1';
          pc_inc <= '1';
          nstate <= spwait;
        when pdec =>
          ptr_dec <= '1';
          pc_inc <= '1';
          nstate <= spwait;
        when jump =>
          pc_inc <= '1';
          DATA_EN <= '1';
          nstate <= sjump0;
        when jump_end =>
          DATA_EN <= '1';
          nstate <= sjumpend0;
        when halt =>
            nstate <= shalt;
        when others => 
          pc_inc <= '1';
          nstate <= sfetch0;
    end case;

    when sinc0 =>
      alu_sel <= alu_inc;
      nstate <= sfetch0;
      pc_inc <= '1';

    when sdec0 =>
      alu_sel <= alu_dec;
      nstate <= sfetch0;
      pc_inc <= '1';

    when swrite0 =>
      DATA_EN <= '1';
      nstate <= swrite0;
      if( OUT_BUSY = '0') then 
        OUT_WE <= '1';
        nstate <= sfetch0;
        pc_inc <= '1';
      end if;

      when sread0 =>
      alu_sel <= alu_ind;
      DATA_EN <= '1';
      IN_REQ <= '1';
      nstate <= sread0;
      if( IN_VLD = '1') then
        nstate <= sfetch0;
        pc_inc <= '1';
        DATA_WE <= '1';
        IN_REQ <= '0';
      end if;

      when spwait =>     
      DATA_EN <= '1';
      nstate <= sfetch0;
    
      when sskipcycle0 =>
      pc_abus <= '1';
      DATA_EN <= '1';
      CODE_EN <= '1';
      nstate <= sskipcycle;

    when sskipcycle =>
      pc_abus <= '1';
      DATA_EN <= '1';
      CODE_EN <= '1';
      pc_inc <= '1';
      nstate <= sskipcycle0;
      if(cnt_iszero = '1') then
        nstate <= sfetch0;
        pc_inc <= '0';
      elsif (inst_dec = jump_end) then
        cnt_dec <= '1';
      elsif (inst_dec = jump) then
        cnt_inc <= '1';
      end if;

    when shalt => 
    nstate <= shalt;

    when sjump0 =>
      DATA_EN <= '1';
      if(data_iszero = '1') then
        nstate <= sskipcycle0;
        cnt_inc <= '1';
      else
        ras_push <= '1';
        nstate <= sfetch0;
      end if;

      when sjumpend0 =>
      DATA_EN <= '1';
      if(data_iszero = '1') then
        pc_inc <= '1'; 
        ras_pop <= '1';
        nstate <= sfetch0;
      else
        ras_top <= '1';
        nstate <= sjumpend1;
      end if;

      when sjumpend1 =>
      DATA_EN <= '1';
      pc_ld <= '1';
      nstate <= sfetch0;


    when others => null;
  end case;
end process; -- fsm

OUT_DATA <= DATA_RDATA when (OUT_BUSY = '0')
                    else (others=>'Z');

data_iszero <= '1' when ( DATA_RDATA = "00000000" )
                    else '0';
cnt_iszero <= '1' when ( cnt_out = "0000" )
                    else '0';

end behavioral;
 
