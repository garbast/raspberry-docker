#!/bin/bash

netplan generate
netplan apply
networkctl
