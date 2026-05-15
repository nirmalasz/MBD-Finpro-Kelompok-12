#define __SFR_OFFSET 0
#include <avr/io.h>

.global main
.global __vector_16   

; r18 menit
; r19 detik
; r20 state (0 idle, 1 jalan, 2 selesai)
; r21 flag update waktu
; r22 flag timer habis

; PC0 tombol start
; PC1 tombol reset
; PB1 lampu (pwm)

.equ OVF_PER_SEC, 61

.section .bss
ovf_count: .byte 0

.section .text

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
    
    ; Matikan LED dengan mengatur PWM Duty Cycle ke 0
    clr  r16
    sts  OCR1AH, r16
    sts  OCR1AL, r16
    
    ldi  r22, 1

T0_EXIT:
    pop  r23
    pop  r16
    out  SREG, r16
    pop  r16
    reti

main:
    ; tombol input
    cbi DDRC,0
    cbi DDRC,1
    cbi PORTC,0
    cbi PORTC,1

    ; lampu output (PB1 / OC1A)
    sbi DDRB,1

    ; setup timer1 pwm
    ldi r24, (1<<COM1A1) | (1<<WGM10)
    sts TCCR1A, r24

    ; Prescaler 8
    ldi r24, (1<<WGM12) | (1<<CS11)
    sts TCCR1B, r24

    ; Set duty cycle awal 50% (128 dari 255)
    clr r24
    sts OCR1AH, r24
    ldi r24, 128
    sts OCR1AL, r24

    ; UART 9600
    clr r24
    sts UCSR0A,r24
    sts UBRR0H,r24
    ldi r24,103
    sts UBRR0L,r24
    ldi r24,(1<<RXEN0)|(1<<TXEN0)
    sts UCSR0B,r24
    ldi r24,(1<<UCSZ00)|(1<<UCSZ01)
    sts UCSR0C,r24

    ; timer0 start
    ldi r24,(1<<CS02)|(1<<CS00)
    out TCCR0B,r24
    ldi r24,(1<<TOIE0)
    sts TIMSK0,r24

    ; init variabel
    clr r18
    clr r19
    ldi r20,0
    clr r21
    clr r22
    clr r23
    sts ovf_count,r23

    ldi r30,lo8(msg_ready)
    ldi r31,hi8(msg_ready)
    call uart_print
    call display_welcome
    call display_button_guide

    sei

loop_utama:
    sbis PINC,0
    rjmp TOMBOL1_HANDLER

    sbis PINC,1
    rjmp TOMBOL2_HANDLER

    cpi r22,1
    breq HANDLE_HABIS

    cpi r21,1
    breq HANDLE_TICK

    rjmp loop_utama

TOMBOL1_HANDLER:
    call debounce
    sbic PINC,0
    rjmp loop_utama

    cpi r20,0
    brne TUNGGU_LEPAS1

    ldi r18,4
    ldi r19,59
    ldi r20,1
    clr r21
    clr r22
    clr r23
    sts ovf_count,r23

    ldi r30,lo8(msg_mulai)
    ldi r31,hi8(msg_mulai)
    call uart_print
    call display_mode


TUNGGU_LEPAS1:
    sbis PINC,0
    rjmp TUNGGU_LEPAS1
    rjmp loop_utama

TOMBOL2_HANDLER:
    call debounce
    sbic PINC,1
    rjmp loop_utama

    cpi r20,2
    brne TUNGGU_LEPAS2

    cli
    clr r18
    clr r19
    ldi r20,0
    clr r21
    clr r22
    clr r23
    sts ovf_count,r23
    sei

    ; Nyalakan LED lagi dengan PWM 50%
    clr r16
    sts OCR1AH, r16
    ldi r16, 128
    sts OCR1AL, r16

    ldi r30,lo8(msg_reset)
    ldi r31,hi8(msg_reset)
    call uart_print
    call display_after_reset
    call display_mode

TUNGGU_LEPAS2:
    sbis PINC,1
    rjmp TUNGGU_LEPAS2
    rjmp loop_utama

HANDLE_HABIS:
    clr r22
    clr r21

    ldi r30,lo8(msg_habis)
    ldi r31,hi8(msg_habis)
    call uart_print
    call display_button_guide

    rjmp loop_utama

HANDLE_TICK:
    clr r21

    ldi r30,lo8(msg_sisa)
    ldi r31,hi8(msg_sisa)
    call uart_print
    call display_mode

    mov r16,r18
    call print_dec2

    ldi r16,':'
    call uart_send

    mov r16,r19
    call print_dec2

    ldi r30,lo8(msg_crlf)
    ldi r31,hi8(msg_crlf)
    call uart_print

    rjmp loop_utama

; LCD SECTION

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

    LDI ZH, hi8(msg_timer5)
    LDI ZL, lo8(msg_timer5)

print_timer: RCALL lcd_print

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

display_after_reset:
    LDI R16, 0x80
    RCALL lcd_set_cursor
    
    LDI ZH, hi8(after_reset1)
    LDI ZL, lo8(after_reset1)
    RCALL lcd_print

    LDI R16, 0xC0
    RCALL lcd_set_cursor

    LDI ZH, hi8(after_reset2)
    LDI ZL, lo8(after_reset2)
    RCALL lcd_print

    RET
display_button_guide:
    LDI R16, 0x80
    RCALL lcd_set_cursor
    
    LDI ZH, hi8(tell_reset)
    LDI ZL, lo8(tell_reset)
    RCALL lcd_print

    LDI R16, 0xC0
    RCALL lcd_set_cursor

    LDI ZH, hi8(tell_mode)
    LDI ZL, lo8(tell_mode)
    RCALL lcd_print

    RET

; UTIL SECTION

debounce:
    push r16
    push r17
    ldi r16,50
db_o:
    ldi r17,0xFF
db_i:
    dec r17
    brne db_i
    dec r16
    brne db_o
    pop r17
    pop r16
    ret

uart_send:
    push r25
us_w:
    lds r25,UCSR0A
    sbrs r25,UDRE0
    rjmp us_w
    sts UDR0,r16
    pop r25
    ret

uart_print:
    push r16
up_l:
    lpm r16,Z+
    cpi r16,0
    breq up_e
    call uart_send
    rjmp up_l
up_e:
    pop r16
    ret

print_dec2:
    push r16
    push r17
    mov r17,r16
    clr r16
pd_t:
    cpi r17,10
    brlo pd_u
    subi r17,10
    inc r16
    rjmp pd_t
pd_u:
    subi r16,-'0'
    call uart_send
    mov r16,r17
    subi r16,-'0'
    call uart_send
    pop r17
    pop r16
    ret

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


; DATA SECTION

msg_ready: .asciz "siap. tekan tombol 1\r\n"
msg_mulai: .asciz "timer mulai 5:00\r\n"
msg_habis: .asciz "waktu habis. lampu mati.\r\n"
msg_reset: .asciz "reset. lampu nyala lagi (PWM 50%).\r\n"
msg_sisa:  .asciz "sisa "
msg_crlf:  .asciz "\r\n"

welcome_l1:
    .ascii "== Bobotekkom =="
welcome_l2:
    .ascii "= By: group 12 ="

msg_timer5:
    .ascii "= Timer: 5 min ="
msg_dim:
    .ascii "== Light: dim =="
msg_off:
    .ascii "== Light: off =="
tell_reset:
    .ascii "Press b1 > reset"
tell_mode:
    .ascii "b2>off    b3>dim"
after_reset1:
    .ascii " =successfully ="
after_reset2:
    .ascii "= reset  timer ="