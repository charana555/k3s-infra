##!/bin/bash
echo "Waiting for popos-llm to join..."
until kubectl get node popos-llm 2>/dev/null | grep -q Ready; do sleep 5; done
echo "Node ready! Restarting device plugin..."
kubectl rollout restart daemonset nvidia-device-plugin-daemonset -n kube-system
sleep 20
echo "Restarting Ollama..."
kubectl rollout restart deployment ollama -n llm
kubectl rollout status deployment ollama -n llm
echo "GPU node fully ready!"
