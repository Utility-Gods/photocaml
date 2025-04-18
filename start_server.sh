#!/bin/bash
# Example: Replace the command below with your actual server start command
nohup dune exec photocaml > server.log 2>&1 &
echo $! > server.pid
echo "Server started with PID $(cat server.pid)"