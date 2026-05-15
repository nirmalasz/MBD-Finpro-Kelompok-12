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

    rjmp loop_utama

HANDLE_TICK:
    clr r21

    ldi r30,lo8(msg_sisa)
    ldi r31,hi8(msg_sisa)
    call uart_print

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

msg_ready: .asciz "siap. tekan tombol 1\r\n"
msg_mulai: .asciz "timer mulai 5:00\r\n"
msg_habis: .asciz "waktu habis. lampu mati.\r\n"
msg_reset: .asciz "reset. lampu nyala lagi (PWM 50%).\r\n"
msg_sisa:  .asciz "sisa "
msg_crlf:  .asciz "\r\n"
