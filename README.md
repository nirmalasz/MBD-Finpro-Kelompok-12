# MBD-Finpro-Kelompok-12 (Bobotekkom)

## Features

- 5-minute countdown timer via Timer0 overflow ISR
- PWM LED brightness control via Timer1 OC1B (full / dim / off)
- 16x2 LCD display showing timer status and light mode
- UART serial monitor output for real-time feedback
- 3-button interface (start, reset, toggle mode)

---

## Pin Mapping

| Pin | Function |
|-----|----------|
| PC0 (A0) | Button 1 — Start timer |
| PC1 (A1) | Button 2 — Reset (only when timer expired) |
| PC2 (A2) | Button 3 — Toggle light mode (full ↔ dim) |
| PB2 | LED (PWM OC1B) |
| PB0 | LCD EN |
| PB1 | LCD RS |
| PD0–PD7 | LCD data bus |

---

## Button Behavior

| Button | Condition | Action |
|--------|-----------|--------|
| B1 (PC0) | State = idle | Start timer (4:59 countdown) |
| B2 (PC1) | State = selesai | Reset to idle, restore LED |
| B3 (PC2) | State = idle / running | Toggle LED full (255) ↔ dim (128) |

---

## LED States

| Condition | OCR1B | Effect |
|-----------|-------|--------|
| System start / reset | 255 | Full brightness |
| Button 3 pressed (dim) | 128 | 50% PWM |
| Button 3 pressed (full) | 255 | Full brightness |
| Timer expired | 0 | LED off |

---

## Register Map

| Register | Role |
|----------|------|
| r18 | Minutes remaining |
| r19 | Seconds remaining |
| r20 | State (0=idle, 1=running, 2=done) |
| r21 | Tick flag (set by ISR every second) |
| r22 | Expired flag (set by ISR on timeout) |
| r25 | Light mode (0=full, 1=dim) |
| r28, r29 | Delay counters (push/pop only) |

> All subroutines and the ISR use push/pop to protect global registers. Delay routines use r28/r29 exclusively to avoid overlapping r20–r22.

---

## How to Use

1. Upload `finpro.S` via Arduino IDE (place alongside an empty `.ino` file)
2. Wire components according to the pin mapping above
3. Open serial monitor at **9600 baud**
4. Press **B1** to start the 5-minute timer
5. Press **B3** to toggle LED brightness at any time
6. When timer expires, press **B2** to reset

---

## Group Member
- Mohammad Ariq Haqi 2406431271
- Yusri Sukur	2406345305
- Nirmala Sari Zahiroh 2406425653
- Khalisa Zahra Maulana 2406425395
