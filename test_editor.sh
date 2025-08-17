#!/bin/bash
sed 's/file/renamed/' "$1" > "${1}.tmp" && mv "${1}.tmp" "$1"