#!/bin/bash
# CPU and RAM segment for ccstatusline: "CPU 12% | RAM ████░░░░░░ 14GB (40%)"
ncpu=$(sysctl -n hw.ncpu)
cpu=$(ps -A -o %cpu= | awk -v n="$ncpu" '{s+=$1} END {printf "%d", s/n}')
total=$(sysctl -n hw.memsize)
free=$(memory_pressure | awk '/free percentage/ {gsub("%","",$NF); print $NF}')
used=$((100 - free))
gb=$(awk -v t="$total" -v u="$used" 'BEGIN {printf "%d", t*u/100/1073741824 + 0.5}')
filled=$(( (used + 5) / 10 ))
bar=$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' $((10 - filled)) '' | tr ' ' '░')
printf 'CPU %s%% | RAM %s %sGB (%s%%)' "$cpu" "$bar" "$gb" "$used"
