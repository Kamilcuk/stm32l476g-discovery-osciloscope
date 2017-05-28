#!/bin/bash

f=/dev/ttyACM0
sudo stty -F $f 115200 clocal cread cs8 -cstopb parenb crtscts
sudo screen  $f 115200


