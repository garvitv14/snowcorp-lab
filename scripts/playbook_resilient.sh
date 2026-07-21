#!/bin/bash
# Retries the full ansible-playbook run against the given host-limit up to 30
# times with a 20s pause between attempts. WinRM connections under nested
# virtualization drop unpredictably; ansible's own task-level retries handle
# transient drops, but a fully-dropped connection mid-play still needs a
# whole-playbook re-run. This wrapper makes that re-run automatic instead of
# needing a human to notice and restart it.
cd /c/Users/Admin/snowcorp-lab || exit 1
LIMIT="${1:-all}"
for i in $(seq 1 30); do
  echo "=== attempt $i/30 ==="
  ansible-playbook ansible/site.yml -i ansible/inventory.yml --limit "$LIMIT"
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "=== SUCCESS on attempt $i ==="
    exit 0
  fi
  echo "=== attempt $i failed (exit $rc), retrying in 20s ==="
  sleep 20
done
echo "=== FAILED after 30 attempts ==="
exit 1
