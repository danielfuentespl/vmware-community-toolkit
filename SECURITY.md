# Security

Do not post credentials, tokens, accounts, private addresses, infrastructure names, original screenshots or raw logs in public issues. For a suspected vulnerability or secret, contact the maintainer through an agreed private channel first; no dedicated security email or hosted advisory channel is claimed by this local candidate. Share a fictional reproduction or value-free summary until a private disclosure method is agreed.

Treat possible exposed credentials as potentially compromised until their owner/issuer classifies them; revoke/rotate at the issuing service and review dependent jobs/activity. Never authenticate with old literals to classify them. A clean toolkit scan does not resolve findings in other repositories or rewrite history.

Use least privilege, trusted TLS, explicit authorized connections and evidence directories outside Git. Reader output may contain sensitive metadata: projection is not anonymization. No real credentials, VMware connections or infrastructure changes belong in automated tests. CI receives no VMware secrets and uses only synthetic fixtures. Do not upload raw exports, real reports or connection objects as CI artifacts.
