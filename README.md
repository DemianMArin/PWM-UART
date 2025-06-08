# PWM Control with UART

Using tangnano20k and ipc of uart is set to 9600.

## Current States

In order to change state send the letter corresponding to the state (lowercase). The current state will be returned in uppercase.

```
    IDLE -> "i"
    DELIVERY -> "e"
    PRELOAD -> "p"
    TOP -> "t"
    INCREMENT -> "u"
    DECREMENT -> "d"
```


## Problems with UART

If running in jetson the serial interface is

```
screen /dev/ttyTHS1 9600
sudo fuser -k /dev/ttyTHS1 # Problems with screen session

```


