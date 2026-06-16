#!/bin/bash
kubectl drain popos-llm --ignore-daemonsets --delete-emptydir-data
kubectl cordon popos-llm
echo "Safe to shut down now!"
