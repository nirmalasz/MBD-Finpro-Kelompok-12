#define __SFR_OFFSET 0x00
#include "avr/io.h"

.global main

main:
  ; init LCD port
  LDI R16, 0xFF
  OUT DDRD, R16           ; port D for data
  OUT DDRB, R16           ; port B for command
  CBI PORTB, 0            ; enable = 0
  RCALL delay_ms          ; wait LCD power on

  RCALL LCD_init          ; subroutine init LCD
  
welcome:
  RCALL display_welcome   ; subroutine display welcome when init

again:  
  RCALL lcd_clear
  RCALL display_mode      ; display current mode

  LDI R17, 4              ; wait 1 sec
wait:     
  RCALL delay_seconds     
  DEC R17
  BRNE wait
  RJMP again              ; jump to again for another run

LCD_init:
        LDI   R16, 0x33         ;init LCD for 4-bit data
        RCALL command_wrt       ;send to command register
        RCALL delay_ms
        LDI   R16, 0x32         ;init LCD for 4-bit data
        RCALL command_wrt
        RCALL delay_ms
        LDI   R16, 0x28         ;LCD 2 lines, 5x7 matrix
        RCALL command_wrt
        RCALL delay_ms
        LDI   R16, 0x0C         ;disp ON, cursor OFF
        RCALL command_wrt
        LDI   R16, 0x01         ;clear LCD
        RCALL command_wrt
        RCALL delay_ms
        LDI   R16, 0x06         ;shift cursor right
        RCALL command_wrt
        RET 

command_wrt:
        MOV   R27, R16
        ANDI  R27, 0xF0         ;mask low nibble & keep hi8 nibble
        OUT   PORTD, R27        ;o/p hi8 nibble to port D
        CBI   PORTB, 1          ;RS = 0 for command
        SBI   PORTB, 0          ;EN = 1
        RCALL delay_short       ;widen EN pulse
        CBI   PORTB, 0          ;EN = 0 for H-to-L pulse
        RCALL delay_us          ;delay in micro seconds
        ;----------------------------------------------------
        MOV   R27, R16
        SWAP  R27               ;swap nibbles
        ANDI  R27, 0xF0         ;mask low nibble & keep hi8 nibble
        OUT   PORTD, R27        ;o/p hi8 nibble to port D
        SBI   PORTB, 0          ;EN = 1
        RCALL delay_short       ;widen EN pulse
        CBI   PORTB, 0          ;EN = 0 for H-to-L pulse
        RCALL delay_us          ;delay in micro seconds
        RET

data_wrt:
      MOV   R27, R16
      ANDI  R27, 0xF0         ;mask low nibble & keep hi8 nibble
      OUT   PORTD, R27        ;o/p hi8 nibble to port D
      SBI   PORTB, 1          ;RS = 1 for data
      SBI   PORTB, 0          ;EN = 1
      RCALL delay_short       ;make wide EN pulse
      CBI   PORTB, 0          ;EN = 0 for H-to-L pulse
      RCALL delay_us          ;delay in micro seconds
      ;----------------------------------------------------
      MOV   R27, R16
      SWAP  R27               ;swap nibbles
      ANDI  R27, 0xF0         ;mask low nibble & keep hi8 nibble
      OUT   PORTD, R27        ;o/p hi8 nibble to port D
      SBI   PORTB, 0          ;EN = 1
      RCALL delay_short       ;widen EN pulse
      CBI   PORTB, 0          ;EN = 0 for H-to-L pulse
      RCALL delay_us          ;delay in micro seconds
      RET


lcd_clear:
  LDI R16, 0x01           ; to clear LCD
  RCALL command_wrt       ; send command code
  RCALL delay_ms

  RET

lcd_set_cursor:
  RCALL command_wrt
  RET

lcd_print:
next_char:
  LPM R16, Z+
  CPI R16, 0
  BREQ done_print

  RCALL data_wrt
  RJMP next_char
done_print: RET


display_welcome:
  LDI R16, 0x80
  RCALL lcd_set_cursor
  
  LDI ZH, hi8(welcome_l1)
  LDI ZL, lo8(welcome_l1)
  RCALL lcd_print

  LDI R16, 0xC0
  RCALL lcd_set_cursor

  LDI ZH, hi8(welcome_l2)
  LDI ZL, lo8(welcome_l2)
  RCALL lcd_print

  RET

display_mode:
  LDI R16, 0x80
  RCALL lcd_set_cursor
  
  CPI R24, 0              ; check timer mode
  BREQ timer10

timer5:                   ; u line 1
  LDI ZH, hi8(msg_timer5)
  LDI ZL, lo8(msg_timer5)
  RJMP print_timer

timer10:
  LDI ZH, hi8(msg_timer10)
  LDI ZL, lo8(msg_timer10)

print_timer:
RCALL lcd_print

  LDI R16, 0xC0           ; u line 2
  RCALL lcd_set_cursor


  CPI R25, 0              ; cek light mode
  BREQ dim_mode

off_mode:
  LDI ZH, hi8(msg_off)
  LDI ZL, lo8(msg_off)
  RJMP print_light

dim_mode:
  LDI ZH, hi8(msg_dim)
  LDI ZL, lo8(msg_dim)

print_light:
    RCALL lcd_print
    RET

;================================================================
delay_short:
      NOP
      NOP
      RET
;------------------------
delay_us:
      LDI   R20, 90
l3:   RCALL delay_short
      DEC   R20
      BRNE  l3
      RET
;-----------------------
delay_ms:
      LDI   R21, 40
l4:   RCALL delay_us
      DEC   R21
      BRNE  l4
      RET
;================================================================
delay_seconds:        ;nested loop subroutine (max delay 3.11s)
    LDI   R20, 255    ;outer loop counter 
l5: LDI   R21, 255    ;mid loop counter
l6: LDI   R22, 20     ;inner loop counter to give 0.25s delay
l7: DEC   R22         ;decrement inner loop
    BRNE  l7          ;loop if not zero
    DEC   R21         ;decrement mid loop
    BRNE  l6          ;loop if not zero
    DEC   R20         ;decrement outer loop
    BRNE  l5          ;loop if not zero
    RET               ;return to caller
;----------------------------------------------------------------


; ============ DATA SECTION =============

welcome_l1:
    .ascii "Bobotekkom"
welcome_l2:
    .ascii "By: group 12"

msg_timer10:
    .ascii "Timer: 10 min"
msg_timer5:
    .ascii "Timer: 5 min"
msg_dim:
    .ascii "Light: dim"
msg_off:
    .ascii "Light: off"
































