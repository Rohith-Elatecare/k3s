export GITHUB_TOKEN="<READ_ONLY_TOKEN>" && \
curl -L -O \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://github.com/Networkissue/k3s/releases/latest/download/pvt_upgrade.sh && \
chmod +x pvt_upgrade.sh && \
./pvt_upgrade.sh