# Saturday Vinyl Playbooks

Operational runbooks for diagnosing and recovering from production incidents.

Each playbook is written to be **read cold** during an incident — assume the on-call doesn't remember the system in detail. Lead with symptoms, then triage steps, then known scenarios. Background reading goes at the bottom.

## Contents

- **[Push Notification Firefighting](push_notification_firefighting.md)** — diagnosing why FCM pushes (alerts, "record placed" notifications) are not reaching devices. Includes APNs Auth Key creation runbook and service account rotation steps.

## Adding a new playbook

1. Create `<topic>_<scenario>.md` in this directory.
2. Use the version header from the existing playbooks.
3. Structure as: Overview → Symptoms triage → Where to look → Scenarios → Runbooks → Background.
4. Add to the Contents list above.
5. Cross-reference related protocols (`../protocols/`) and concepts (`../concepts/`) at the bottom of the doc.
