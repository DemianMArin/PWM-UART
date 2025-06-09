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

Analog to ROS2
```
   0 idle/load -> i
   1 preload -> p
   2 load/idle -> l
   3 raise -> t // top in fpga
   4 unload -> e
```

Measurements in real life
```
 idle_count = 21_499, // 5cm
 preload_count = 12_499, // 0.6 cm
 load_count = 21_499, // 5cm
 delivery_count = 39_499, // 20cm
 top_count = 42_999, // 23cm
```


## Problems with UART

If running in jetson the serial interface is

```
screen /dev/ttyTHS1 9600
sudo fuser -k /dev/ttyTHS1 # Problems with screen session

```


