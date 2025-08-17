#!/bin/bash
# Test editor that swaps first two lines
{
    sed -n '2p' "$1"
    sed -n '1p' "$1"  
    sed -n '3,$p' "$1"
} > "${1}.tmp" && mv "${1}.tmp" "$1"