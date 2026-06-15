#!/bin/bash
kubectl uncordon popos-llm
kubectl rollout restart deployment ollama -n llm
kubectl rollout status deployment ollama -n llm
echo "GPU node ready!"
