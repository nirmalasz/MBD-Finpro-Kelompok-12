#define __SFR_OFFSET 0
#include <avr/io.h>

.global main
.global __vector_16

; ============================================================
; REGISTER MAP — JANGAN DIUBAH
; r18 = menit          } ISR-owned, JANGAN dipakai subroutine
; r19 = detik          }
; r20 = state          }
; r21 = flag waktu     }
; r22 = flag habis     }
; r23 = ovf_count tmp  }
;
; r24,r25 = scratch untuk delay & setup (push/pop jika perlu)
; r26     = scratch delay_ms loop
; r27     = scratch LCD nibble (push/pop di cmd/data_wrt)
; r16,r17 = scratch umum (push/pop di semua subroutine)
; r30,r31 = Z pointer (push/pop di subroutine yang pakai LPM)
;
; PC0 = tombol start
; PC1 = tombol reset
; PB2 = lampu LED (digital)
; PB0 = LCD EN,  PB1 = LCD RS
; PD[7:4] = LCD data nibble
; ============================================================

.equ OVF_PER_SEC, 61

.section .bss
ovf_count: .byte 0

.section .text

; ============================================================
; ISR Timer0 Overflow — PERSIS dari referensi
; Hanya cbi PORTB,2 (bukan PORTB,1)
; Hanya push r16,r23 — tidak menyentuh register lain
; ============================================================
__vector_16:
    push r16
    in   r16, SREG
    push r16
    push r23

    cpi  r20, 1
    brne T0_EXIT

    lds  r23, ovf_count
    inc  r23
    sts  ovf_count, r23

    cpi  r23, OVF_PER_SEC
    brlo T0_EXIT

    clr  r23
    sts  ovf_count, r23

    cpi  r19, 0
    breq CEK_MENIT

    dec  r19
    ldi  r21, 1
    rjmp T0_EXIT

CEK_MENIT:
    cpi  r18, 0
    breq TIMER_HABIS

    dec  r18
    ldi  r19, 59
    ldi  r21, 1
    rjmp T0_EXIT

TIMER_HABIS:
    ldi  r20, 2
    cbi  PORTB, 2
    ldi  r22, 1

T0_EXIT:
    pop  r23
    pop  r16
    out  SREG, r16
    pop  r16
    reti

; ============================================================
; MAIN
; ============================================================
main:
    cbi DDRC, 0
    cbi DDRC, 1
    cbi PORTC, 0
    cbi PORTC, 1

    sbi DDRB, 0             ; PB0 = LCD EN
    sbi DDRB, 1             ; PB1 = LCD RS
    sbi DDRB, 2             ; PB2 = lampu
    sbi PORTB, 2            ; lampu nyala

    ldi r24, 0xF0
    out DDRD, r24           ; PD7-PD4 output

    rcall LCD_init

    ; UART 9600
    clr r24
    sts UCSR0A, r24
    sts UBRR0H, r24
    ldi r24, 103
    sts UBRR0L, r24
    ldi r24, (1<<RXEN0)|(1<<TXEN0)
    sts UCSR0B, r24
    ldi r24, (1<<UCSZ00)|(1<<UCSZ01)
    sts UCSR0C, r24

    ; Timer0 prescaler 1024 + overflow IE
    ldi r24, (1<<CS02)|(1<<CS00)
    out TCCR0B, r24
    ldi r24, (1<<TOIE0)
    sts TIMSK0, r24

    ; Init variabel
    clr r18
    clr r19
    ldi r20, 0
    clr r21
    clr r22
    clr r23
    sts ovf_count, r23

    ldi r30, lo8(msg_ready)
    ldi r31, hi8(msg_ready)
    call uart_print

    call lcd_clear
    call display_welcome
    call lcd_clear
    call display_button_guide

    sei

; ============================================================
; MAIN LOOP
; ============================================================
loop_utama:
    sbis PINC, 0
    jmp  TOMBOL1_HANDLER

    sbis PINC, 1
    jmp  TOMBOL2_HANDLER

    cpi  r22, 1
    brne chk_tick
    jmp  HANDLE_HABIS
chk_tick:
    cpi  r21, 1
    brne loop_utama
    jmp  HANDLE_TICK

; ============================================================
; TOMBOL 1 — START
; ============================================================
TOMBOL1_HANDLER:
    call debounce
    sbic PINC, 0
    jmp  loop_utama

    cpi  r20, 0
    brne TUNGGU_LEPAS1

    ldi  r18, 4
    ldi  r19, 59
    ldi  r20, 1
    clr  r21
    clr  r22
    clr  r23
    sts  ovf_count, r23

    ldi  r30, lo8(msg_mulai)
    ldi  r31, hi8(msg_mulai)
    call uart_print
    call lcd_clear
    call display_mode

TUNGGU_LEPAS1:
    sbis PINC, 0
    rjmp TUNGGU_LEPAS1
    jmp  loop_utama

; ============================================================
; TOMBOL 2 — RESET
; ============================================================
TOMBOL2_HANDLER:
    call debounce
    sbic PINC, 1
    jmp  loop_utama

    cpi  r20, 2
    brne TUNGGU_LEPAS2

    cli
    clr  r18
    clr  r19
    ldi  r20, 0
    clr  r21
    clr  r22
    clr  r23
    sts  ovf_count, r23
    sei

    sbi  PORTB, 2

    ldi  r30, lo8(msg_reset)
    ldi  r31, hi8(msg_reset)
    call uart_print
    call lcd_clear
    call display_after_reset
    call lcd_clear
    call display_button_guide

TUNGGU_LEPAS2:
    sbis PINC, 1
    rjmp TUNGGU_LEPAS2
    jmp  loop_utama

; ============================================================
; HANDLE HABIS
; ============================================================
HANDLE_HABIS:
    clr  r22
    clr  r21

    ldi  r30, lo8(msg_habis)
    ldi  r31, hi8(msg_habis)
    call uart_print
    call lcd_clear
    call display_button_guide

    jmp  loop_utama

; ============================================================
; HANDLE TICK
; ============================================================
HANDLE_TICK:
    clr  r21

    ldi  r30, lo8(msg_sisa)
    ldi  r31, hi8(msg_sisa)
    call uart_print

    mov  r16, r18
    call print_dec2

    ldi  r16, ':'
    call uart_send

    mov  r16, r19
    call print_dec2

    ldi  r30, lo8(msg_crlf)
    ldi  r31, hi8(msg_crlf)
    call uart_print

    call lcd_clear
    call display_mode


    jmp  loop_utama

; ============================================================
; LCD SECTION
; ============================================================
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
    PUSH R27
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
    POP  R27
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
    POP  R27
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
    PUSH R16
    PUSH R30
    PUSH R31
next_char:
    LPM  R16, Z+
    CPI  R16, 0
    BREQ done_print
    
    RCALL data_wrt
    RJMP next_char
done_print:
    POP  R31
    POP  R30
    POP  R16
    RET

display_welcome:
    PUSH R16
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
    POP R16
    RET

display_mode:
    PUSH R16
    LDI R16, 0x80
    RCALL lcd_set_cursor
    LDI ZH, hi8(msg_timer5)
    LDI ZL, lo8(msg_timer5)
    RCALL lcd_print
    LDI R16, 0xC0           ; u line 2
    RCALL lcd_set_cursor
    LDI  ZH, hi8(lcd_running)
    LDI  ZL, lo8(lcd_running)
    RCALL lcd_print
    POP R16
    RET

display_after_reset:
    PUSH R16
    LDI R16, 0x80
    RCALL lcd_set_cursor
    LDI  ZH, hi8(lcd_reset1)
    LDI  ZL, lo8(lcd_reset1)
    RCALL lcd_print
    LDI R16, 0xC0           ; u line 2
    RCALL lcd_set_cursor
    LDI  ZH, hi8(lcd_reset2)
    LDI  ZL, lo8(lcd_reset2)
    RCALL lcd_print
    POP R16
    RET

display_button_guide:
    PUSH R16
    LDI R16, 0x80
    RCALL lcd_set_cursor
    LDI  ZH, hi8(lcd_guide1)
    LDI  ZL, lo8(lcd_guide1)
    RCALL lcd_print
    LDI R16, 0xC0           ; u line 2
    RCALL lcd_set_cursor
    LDI  ZH, hi8(lcd_guide2)
    LDI  ZL, lo8(lcd_guide2)
    RCALL lcd_print
    POP R16
    RET

; ============================================================
; UTIL
; ============================================================
debounce:
    push r16
    push r17
    ldi  r16, 50
db_o:
    ldi  r17, 0xFF
db_i:
    dec  r17
    brne db_i
    dec  r16
    brne db_o
    pop  r17
    pop  r16
    ret

uart_send:
    push r16
    push r25
us_w:
    lds  r25, UCSR0A
    sbrs r25, UDRE0
    rjmp us_w
    sts  UDR0, r16
    pop  r25
    pop  r16
    ret

uart_print:
    push r16
    push r30
    push r31
up_l:
    lpm  r16, Z+
    cpi  r16, 0
    breq up_e
    rcall uart_send
    rjmp up_l
up_e:
    pop  r31
    pop  r30
    pop  r16
    ret

print_dec2:
    push r16
    push r17
    mov  r17, r16
    clr  r16
pd_t:
    cpi  r17, 10
    brlo pd_u
    subi r17, 10
    inc  r16
    rjmp pd_t
pd_u:
    subi r16, -'0'
    rcall uart_send
    mov  r16, r17
    subi r16, -'0'
    rcall uart_send
    pop  r17
    pop  r16
    ret
    
delay_short:
    nop
    nop
    ret

delay_us:
    push r24
    ldi  r24, 90
du_l:
    rcall delay_short
    dec  r24
    brne du_l
    pop  r24
    ret

delay_ms:
    push r24
    push r25
    ldi  r25, 40
dm_l:
    rcall delay_us
    dec  r25
    brne dm_l
    pop  r25
    pop  r24
    ret

; ============================================================
; DATA
; ============================================================

msg_ready: .asciz "siap. tekan tombol 1\r\n"
msg_mulai: .asciz "timer mulai 5:00\r\n"
msg_habis: .asciz "waktu habis. lampu mati.\r\n"
msg_reset: .asciz "reset. lampu nyala lagi.\r\n"
msg_sisa:  .asciz "sisa "
msg_crlf:  .asciz "\r\n"

welcome_l1: 
    .ascii "== Bobotekkom =="
    .byte 0
welcome_l2 
    .ascii "= By: group 12 ="
    .byte 0
msg_timer5:    
    .ascii "= Timer: 5 min ="
    .byte 0
lcd_running:  
    .ascii "== Running... =="
    .byte 0
lcd_guide1:   
    .ascii "b1 > start timer"
    .byte 0
lcd_guide2:    
    .ascii "b2 > reset timer"
    .byte 0
lcd_reset1:   
    .ascii "= successfully ="
    .byte 0
lcd_reset2:   
    .ascii "= reset  timer ="
    .byte 0