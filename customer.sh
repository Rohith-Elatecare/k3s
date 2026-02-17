export GITHUB_TOKEN="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" && \
curl -L -O \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://github.com/Networkissue/k3s/releases/latest/download/upgrade.sh && \
chmod +x upgrade.sh && \
./upgrade.sh