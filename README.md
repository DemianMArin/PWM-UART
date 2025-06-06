# PWM Control with UART

Using tangnano20k and ipc of uart is set to 9600.

## Current States

```
    IDLE -> "i"
    DELIVERY -> "e"
    PRELOAD -> "p"
    TOP -> "t"
    INCREMENT -> "u"
    DECREMENT -> "d"
```
## Problems with UART

sudo fuser -k /dev/ttyTHS1


