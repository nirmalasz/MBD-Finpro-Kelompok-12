#define __SFR_OFFSET 0x00
#include "avr/io.h"

.global main
.global __vector_16

; REGISTER MAP 
; r18  : menit
; r19  : detik
; r20  : state (0=idle, 1=jalan, 2=selesai)
; r21  : flag tick (1 = ada update detik)
; r22  : flag habis (1 = timer selesai)
; r25  : light mode (0=full, 1=dim)
; --- SCRATCH (selalu push/pop di dalam subroutine) ---
; r16, r27 : LCD/scratch
; r28, r29 : delay counter (TIDAK overlap r20/r21/r22)

; === PIN MAP (sesuai kode LCD reference) ===
; PD0-PD7 : LCD data bus (PORTD full output)
; PB0     : LCD EN
; PB1     : LCD RS
; PB2     : LED (OC1B, Arduino pin 10)
; PC0 (A0): tombol start  (button 1)
; PC1 (A1): tombol reset  (button 2)  -- aktif hanya saat state selesai
; PC2 (A2): tombol mode   (button 3)  -- toggle full/dim

.equ OVF_PER_SEC, 61

.section .bss
ovf_count: .byte 0

.section .text

; ISR TIMER0 OVERFLOW — hitung waktu mundur
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
    ; Matikan LED: OCR1B = 0
    push r16
    clr  r16
    sts  OCR1BH, r16
    sts  OCR1BL, r16
    pop  r16
    ldi  r22, 1

T0_EXIT:
    pop  r23
    pop  r16
    out  SREG, r16
    pop  r16
    reti

; MAIN
main:
    ; LCD port — sama persis seperti kode reference
    LDI R16, 0xFF
    OUT DDRD, R16           ; PORTD full output (LCD data)
    OUT DDRB, R16           ; PORTB full output (LCD ctrl + LED)
    CBI PORTB, 0            ; EN = 0

    ; tombol input PC0/PC1/PC2 — no pull-up (sesuai skematik external resistor)
    cbi DDRC, 0
    cbi DDRC, 1
    cbi DDRC, 2
    cbi PORTC, 0
    cbi PORTC, 1
    cbi PORTC, 2

    ; Timer1 Fast PWM 8-bit, non-inverting OC1B (PB2)
    ; COM1B1=1, WGM10=1
    ldi r16, (1<<COM1B1) | (1<<WGM10)
    sts TCCR1A, r16
    ; WGM12=1, prescaler 8
    ldi r16, (1<<WGM12) | (1<<CS11)
    sts TCCR1B, r16

    ; LED nyala penuh di awal (OCR1B = 255)
    clr  r16
    sts  OCR1BH, r16
    ldi  r16, 255
    sts  OCR1BL, r16

    ; UART 9600 baud @ 16MHz
    clr  r16
    sts  UCSR0A, r16
    sts  UBRR0H, r16
    ldi  r16, 103
    sts  UBRR0L, r16
    ldi  r16, (1<<RXEN0)|(1<<TXEN0)
    sts  UCSR0B, r16
    ldi  r16, (1<<UCSZ00)|(1<<UCSZ01)
    sts  UCSR0C, r16

    ; Timer0 overflow prescaler 1024 (untuk hitung waktu)
    ldi  r16, (1<<CS02)|(1<<CS00)
    out  TCCR0B, r16
    ldi  r16, (1<<TOIE0)
    sts  TIMSK0, r16

    ; Init variabel global
    clr  r18                ; menit = 0
    clr  r19                ; detik = 0
    ldi  r20, 0             ; state = idle
    clr  r21                ; flag tick = 0
    clr  r22                ; flag habis = 0
    clr  r25                ; light mode = 0 (full)
    clr  r23
    sts  ovf_count, r23

    RCALL delay_ms
    RCALL LCD_init

    ldi  r30, lo8(msg_ready)
    ldi  r31, hi8(msg_ready)
    call uart_print

    RCALL display_welcome
    RCALL display_button_guide

    sei

; LOOP UTAMA
loop_utama:
    sbic PINC, 0
    rjmp cek_btn2
    jmp  TOMBOL1_HANDLER

cek_btn2:
    sbic PINC, 1
    rjmp cek_btn3
    jmp  TOMBOL2_HANDLER

cek_btn3:
    sbic PINC, 2
    rjmp cek_habis
    jmp  TOMBOL3_HANDLER

cek_habis:
    cpi  r22, 1
    brne cek_tick
    jmp  HANDLE_HABIS

cek_tick:
    cpi  r21, 1
    brne loop_utama
    jmp  HANDLE_TICK

; TOMBOL 1 - Start timer (hanya saat idle)
TOMBOL1_HANDLER:
    rcall debounce
    sbis PINC, 0
    rjmp T1_pressed
    jmp  loop_utama

T1_pressed:
    cpi  r20, 0
    brne TUNGGU_LEPAS1

    ldi  r18, 4 ;testing 1 menit
    ldi  r19, 59
    ldi  r20, 1
    clr  r21
    clr  r22
    clr  r23
    sts  ovf_count, r23

    ldi  r30, lo8(msg_mulai)
    ldi  r31, hi8(msg_mulai)
    call uart_print
    RCALL display_mode

TUNGGU_LEPAS1:
    sbis PINC, 0
    rjmp TUNGGU_LEPAS1
    jmp  loop_utama

; TOMBOL 2 - Reset (hanya saat state selesai)
TOMBOL2_HANDLER:
    rcall debounce
    sbis PINC, 1
    rjmp T2_pressed
    jmp  loop_utama

T2_pressed:
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

    ; Kembalikan LED sesuai light mode
    cpi  r25, 0
    breq reset_full
reset_dim:
    push r16
    clr  r16
    sts  OCR1BH, r16
    ldi  r16, 128
    sts  OCR1BL, r16
    pop  r16
    rjmp reset_lcd
reset_full:
    push r16
    clr  r16
    sts  OCR1BH, r16
    ldi  r16, 255
    sts  OCR1BL, r16
    pop  r16

reset_lcd:
    ldi  r30, lo8(msg_reset)
    ldi  r31, hi8(msg_reset)
    call uart_print
    RCALL display_after_reset
    RCALL display_mode

TUNGGU_LEPAS2:
    sbis PINC, 1
    rjmp TUNGGU_LEPAS2
    jmp  loop_utama

; TOMBOL 3 - Toggle light mode: full (255) <-> dim (128 PWM)
TOMBOL3_HANDLER:
    rcall debounce
    sbis PINC, 2
    rjmp T3_pressed
    jmp  loop_utama

T3_pressed:
    cpi  r20, 2
    breq TUNGGU_LEPAS3

    cpi  r25, 0
    breq SET_DIM_MODE

SET_FULL_MODE:
    clr  r25
    push r16
    clr  r16
    sts  OCR1BH, r16
    ldi  r16, 255
    sts  OCR1BL, r16
    pop  r16
    rjmp TOMBOL3_DONE

SET_DIM_MODE:
    ldi  r25, 1
    push r16
    clr  r16
    sts  OCR1BH, r16
    ldi  r16, 128
    sts  OCR1BL, r16
    pop  r16

TOMBOL3_DONE:
    ldi  r30, lo8(msg_mode_chg)
    ldi  r31, hi8(msg_mode_chg)
    call uart_print
    RCALL display_mode

TUNGGU_LEPAS3:
    sbis PINC, 2
    rjmp TUNGGU_LEPAS3
    jmp  loop_utama

; HANDLE WAKTU HABIS
HANDLE_HABIS:
    clr  r22
    clr  r21

    ldi  r30, lo8(msg_habis)
    ldi  r31, hi8(msg_habis)
    call uart_print
    RCALL display_button_guide

    jmp  loop_utama

; HANDLE TICK — update tiap detik
HANDLE_TICK:
    clr  r21

    ldi  r30, lo8(msg_sisa)
    ldi  r31, hi8(msg_sisa)
    call uart_print
    RCALL display_mode

    mov  r16, r18
    call print_dec2
    ldi  r16, ':'
    call uart_send
    mov  r16, r19
    call print_dec2

    ldi  r30, lo8(msg_crlf)
    ldi  r31, hi8(msg_crlf)
    call uart_print

    jmp  loop_utama

; LCD SECTION - IDENTIK dengan kode reference yang sudah jalan
; PD=data, PB0=EN, PB1=RS
LCD_init:
        LDI   R16, 0x33
        RCALL command_wrt
        RCALL delay_ms
        LDI   R16, 0x32
        RCALL command_wrt
        RCALL delay_ms
        LDI   R16, 0x28
        RCALL command_wrt
        RCALL delay_ms
        LDI   R16, 0x0C
        RCALL command_wrt
        LDI   R16, 0x01
        RCALL command_wrt
        RCALL delay_ms
        LDI   R16, 0x06
        RCALL command_wrt
        RET

command_wrt:
        MOV   R27, R16
        ANDI  R27, 0xF0
        OUT   PORTD, R27
        CBI   PORTB, 1 ; RS=0
        SBI   PORTB, 0 ; EN=1
        RCALL delay_short
        CBI   PORTB, 0 ; EN=0
        RCALL delay_us
        MOV   R27, R16
        SWAP  R27
        ANDI  R27, 0xF0
        OUT   PORTD, R27
        SBI   PORTB, 0
        RCALL delay_short
        CBI   PORTB, 0
        RCALL delay_us
        RET

data_wrt:
        MOV   R27, R16
        ANDI  R27, 0xF0
        OUT   PORTD, R27
        SBI   PORTB, 1 ; RS=1
        SBI   PORTB, 0 ; EN=1
        RCALL delay_short
        CBI   PORTB, 0
        RCALL delay_us
        MOV   R27, R16
        SWAP  R27
        ANDI  R27, 0xF0
        OUT   PORTD, R27
        SBI   PORTB, 0
        RCALL delay_short
        CBI   PORTB, 0
        RCALL delay_us
        RET

lcd_clear:
        LDI   R16, 0x01
        RCALL command_wrt
        RCALL delay_ms
        RET

lcd_set_cursor:
        RCALL command_wrt
        RET

lcd_print:
next_char:
        LPM   R16, Z+
        CPI   R16, 0
        BREQ  done_print
        RCALL data_wrt
        RJMP  next_char
done_print:
        RET

; --- display functions ---

display_welcome:
        LDI   R16, 0x80
        RCALL lcd_set_cursor
        LDI   ZH, hi8(welcome_l1)
        LDI   ZL, lo8(welcome_l1)
        RCALL lcd_print
        LDI   R16, 0xC0
        RCALL lcd_set_cursor
        LDI   ZH, hi8(welcome_l2)
        LDI   ZL, lo8(welcome_l2)
        RCALL lcd_print
        RET

display_mode:
        LDI   R16, 0x80
        RCALL lcd_set_cursor
        LDI   ZH, hi8(msg_timer5)
        LDI   ZL, lo8(msg_timer5)
        RCALL lcd_print

        LDI   R16, 0xC0
        RCALL lcd_set_cursor

        CPI   R25, 0
        BREQ  dm_full

dm_dim:
        LDI   ZH, hi8(msg_dim)
        LDI   ZL, lo8(msg_dim)
        RJMP  dm_print

dm_full:
        LDI   ZH, hi8(msg_full)
        LDI   ZL, lo8(msg_full)

dm_print:
        RCALL lcd_print
        RET

display_after_reset:
        LDI   R16, 0x80
        RCALL lcd_set_cursor
        LDI   ZH, hi8(after_reset1)
        LDI   ZL, lo8(after_reset1)
        RCALL lcd_print
        LDI   R16, 0xC0
        RCALL lcd_set_cursor
        LDI   ZH, hi8(after_reset2)
        LDI   ZL, lo8(after_reset2)
        RCALL lcd_print
        RET

display_button_guide:
        LDI   R16, 0x80
        RCALL lcd_set_cursor
        LDI   ZH, hi8(tell_start)
        LDI   ZL, lo8(tell_start)
        RCALL lcd_print
        LDI   R16, 0xC0
        RCALL lcd_set_cursor
        LDI   ZH, hi8(tell_mode)
        LDI   ZL, lo8(tell_mode)
        RCALL lcd_print
        RET

; UTIL
debounce:
        push  r28
        push  r29
        ldi   r28, 50
dbo:    ldi   r29, 0xFF
dbi:    dec   r29
        brne  dbi
        dec   r28
        brne  dbo
        pop   r29
        pop   r28
        ret

uart_send:
        push  r25
usw:    lds   r25, UCSR0A
        sbrs  r25, UDRE0
        rjmp  usw
        sts   UDR0, r16
        pop   r25
        ret

uart_print:
        push  r16
upl:    lpm   r16, Z+
        cpi   r16, 0
        breq  upe
        call  uart_send
        rjmp  upl
upe:    pop   r16
        ret

print_dec2:
        push  r16
        push  r17
        mov   r17, r16
        clr   r16
pdt:    cpi   r17, 10
        brlo  pdu
        subi  r17, 10
        inc   r16
        rjmp  pdt
pdu:    subi  r16, -'0'
        call  uart_send
        mov   r16, r17
        subi  r16, -'0'
        call  uart_send
        pop   r17
        pop   r16
        ret

delay_short:
        NOP
        NOP
        RET

delay_us:
        push  r28
        LDI   R28, 90
lu3:    RCALL delay_short
        DEC   R28
        BRNE  lu3
        pop   r28
        RET

delay_ms:
        push  r28
        push  r29
        LDI   R29, 40
lu4:    RCALL delay_us
        DEC   R29
        BRNE  lu4
        pop   r29
        pop   r28
        RET

delay_seconds:
        push  r28
        push  r29
        push  r26
        LDI   R28, 255
lu5:    LDI   R29, 255
lu6:    LDI   R26, 20
lu7:    DEC   R26
        BRNE  lu7
        DEC   R29
        BRNE  lu6
        DEC   R28
        BRNE  lu5
        pop   r26
        pop   r29
        pop   r28
        RET

; DATA SECTION
msg_ready:    .asciz "siap. tekan tombol 1\r\n"
msg_mulai:    .asciz "timer mulai 5:00\r\n"
msg_habis:    .asciz "waktu habis. lampu mati.\r\n"
msg_reset:    .asciz "reset.\r\n"
msg_mode_chg: .asciz "light mode changed\r\n"
msg_sisa:     .asciz "sisa "
msg_crlf:     .asciz "\r\n"

welcome_l1:   .ascii "== Bobotekkom =="
              .byte 0
welcome_l2:   .ascii "= By: group 12 ="
              .byte 0
msg_timer5:   .ascii "= Timer: 5 min ="
              .byte 0
msg_full:     .ascii "= Light: full  ="
              .byte 0
msg_dim:      .ascii "== Light: dim =="
              .byte 0
tell_start:   .ascii "b1>start b2>rst "
              .byte 0
tell_mode:    .ascii "b3>toggle light "
              .byte 0
after_reset1: .ascii " =successfully ="
              .byte 0
after_reset2: .ascii "= reset  timer ="
              .byte 0